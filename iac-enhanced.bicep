@description('The name prefix for the VMSS')
param vmssName string = 'vmss'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The VM size for the VMSS instances')
param vmSize string = 'Standard_B2s'

@description('Minimum number of VM instances for autoscaling')
param minInstanceCount int = 2

@description('Maximum number of VM instances for autoscaling')
param maxInstanceCount int = 10

@description('Default number of VM instances')
param defaultInstanceCount int = 2

@description('Admin username for the VMs')
param adminUsername string = 'azureadmin'

@description('Admin password for the VMs')
@secure()
param adminPassword string

@description('Email address for autoscale notifications')
param notificationEmail string

// Log Analytics Workspace for monitoring and diagnostics
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${vmssName}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Storage Account for Boot Diagnostics
resource bootDiagnosticsStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${uniqueString(resourceGroup().id)}diag'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// DDoS Protection Plan (recommended for production workloads)
resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2023-04-01' = {
  name: '${vmssName}-ddos-plan'
  location: location
  properties: {}
}

// Network Security Group for subnet
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${vmssName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          priority: 1010
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 1020
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

// Virtual Network with DDoS Protection
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: '${vmssName}-vnet'
  location: location
  tags: {
    environment: 'production'
    resilient: 'true'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    enableDdosProtection: true
    ddosProtectionPlan: {
      id: ddosProtectionPlan.id
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// Virtual Machine Scale Set (Zone-Resilient with Self-Healing)
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: vmssName
  location: location
  zones: [
    '1'
    '2'
    '3'
  ]
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: defaultInstanceCount
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    // Automatic instance repair for self-healing
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: 'PT30M'
      repairAction: 'Replace'
    }
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-Datacenter'
          version: 'latest'
        }
      }
      osProfile: {
        adminUsername: adminUsername
        adminPassword: adminPassword
        windowsConfiguration: {
          enableAutomaticUpdates: true
          patchSettings: {
            patchMode: 'AutomaticByPlatform'
            assessmentMode: 'AutomaticByPlatform'
            automaticByPlatformSettings: {
              rebootSetting: 'IfRequired'
            }
          }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: vnet.properties.subnets[0].id
                    }
                  }
                }
              ]
            }
          }
        ]
      }
      // Boot diagnostics for troubleshooting
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
          storageUri: bootDiagnosticsStorage.properties.primaryEndpoints.blob
        }
      }
      // Application Health Extension for monitoring
      extensionProfile: {
        extensions: [
          {
            name: 'HealthExtension'
            properties: {
              autoUpgradeMinorVersion: true
              publisher: 'Microsoft.ManagedServices'
              type: 'ApplicationHealthWindows'
              typeHandlerVersion: '1.0'
              settings: {
                protocol: 'tcp'
                port: 3389
                intervalInSeconds: 5
                numberOfProbes: 1
                gracePeriod: 600
              }
            }
          }
        ]
      }
    }
  }
}

// Autoscale Settings for elastic scalability
resource autoscaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${vmssName}-autoscale'
  location: location
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'Default autoscale profile'
        capacity: {
          minimum: string(minInstanceCount)
          maximum: string(maxInstanceCount)
          default: string(defaultInstanceCount)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 75
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
    notifications: [
      {
        operation: 'Scale'
        email: {
          sendToSubscriptionAdministrator: false
          sendToSubscriptionCoAdministrators: false
          customEmails: [
            notificationEmail
          ]
        }
      }
    ]
  }
}

// Diagnostic Settings for VMSS
resource vmssDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${vmssName}-diagnostics'
  scope: vmss
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for VNet
resource vnetDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${vmssName}-vnet-diagnostics'
  scope: vnet
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Outputs
output vmssId string = vmss.id
output vmssName string = vmss.name
output vnetId string = vnet.id
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output autoscaleSettingsId string = autoscaleSettings.id
