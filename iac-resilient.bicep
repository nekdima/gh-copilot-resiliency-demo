@description('The name prefix for the VMSS')
param vmssName string = 'vmss'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The VM size for the VMSS instances')
param vmSize string = 'Standard_D2s_v5'

@description('The number of VM instances (will be distributed across 3 availability zones)')
param instanceCount int = 3

@description('Admin username for the VMs')
param adminUsername string = 'azureadmin'

@description('Admin password for the VMs')
@secure()
param adminPassword string

@description('Health probe port')
param healthProbePort int = 80

@description('Health probe path')
param healthProbePath string = '/health'

// Public IP for Load Balancer (Standard SKU, Zone-Redundant)
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${vmssName}-pip'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${vmssName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vmss-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Standard Load Balancer (Zone-Redundant)
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: '${vmssName}-lb'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'vmss-backend-pool'
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${vmssName}-lb', 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${vmssName}-lb', 'vmss-backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${vmssName}-lb', 'health-probe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default'
          enableTcpReset: true
        }
      }
    ]
    probes: [
      {
        name: 'health-probe'
        properties: {
          protocol: 'Http'
          port: healthProbePort
          requestPath: healthProbePath
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
  }
}

// Network Security Group for VMSS subnet
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${vmssName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTP'
        properties: {
          priority: 1000
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
        name: 'AllowHealthProbe'
        properties: {
          priority: 1010
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

// Update VNet subnet to include NSG
resource vnetSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: 'vmss-subnet'
  properties: {
    addressPrefix: '10.0.1.0/24'
    networkSecurityGroup: {
      id: nsg.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

// Virtual Machine Scale Set (Zone-Resilient with Flexible Orchestration)
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-07-01' = {
  name: vmssName
  location: location
  zones: ['1', '2', '3']
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: instanceCount
  }
  properties: {
    // Flexible orchestration mode for better VM API compatibility and resiliency
    orchestrationMode: 'Flexible'
    
    // Platform fault domain configuration for maximum spreading across zones
    platformFaultDomainCount: 1
    
    // Strict zone balancing for even distribution
    zoneBalance: true
    
    // Automatic instance repairs with health monitoring
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: 'PT10M'
      repairAction: 'Replace'
    }
    
    // Rolling upgrade policy for zero-downtime updates
    upgradePolicy: {
      mode: 'Rolling'
      rollingUpgradePolicy: {
        maxBatchInstancePercent: 20
        maxUnhealthyInstancePercent: 20
        maxUnhealthyUpgradedInstancePercent: 20
        pauseTimeBetweenBatches: 'PT5M'
        enableCrossZoneUpgrade: true
        prioritizeUnhealthyInstances: true
        rollbackFailedInstancesOnPolicyBreach: true
      }
      automaticOSUpgradePolicy: {
        enableAutomaticOSUpgrade: true
        disableAutomaticRollback: false
        useRollingUpgradePolicy: true
      }
    }
    
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_ZRS' // Zone-redundant storage for 12-nines durability
          }
          diskSizeGB: 128
        }
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-Datacenter'
          version: 'latest'
        }
      }
      osProfile: {
        computerNamePrefix: substring(vmssName, 0, min(length(vmssName), 9))
        adminUsername: adminUsername
        adminPassword: adminPassword
        windowsConfiguration: {
          provisionVMAgent: true
          enableAutomaticUpdates: true
          patchSettings: {
            patchMode: 'AutomaticByPlatform'
            automaticByPlatformSettings: {
              rebootSetting: 'IfRequired'
            }
            assessmentMode: 'AutomaticByPlatform'
          }
        }
      }
      networkProfile: {
        healthProbe: {
          id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancer.name, 'health-probe')
        }
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}-nic'
            properties: {
              primary: true
              enableAcceleratedNetworking: true
              networkSecurityGroup: {
                id: nsg.id
              }
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: vnetSubnet.id
                    }
                    primary: true
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancer.name, 'vmss-backend-pool')
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      // Application Health Extension for monitoring and auto-repair
      extensionProfile: {
        extensions: [
          {
            name: 'HealthExtension'
            properties: {
              publisher: 'Microsoft.ManagedServices'
              type: 'ApplicationHealthWindows'
              autoUpgradeMinorVersion: true
              typeHandlerVersion: '1.0'
              settings: {
                protocol: 'http'
                port: healthProbePort
                requestPath: healthProbePath
                intervalInSeconds: 5
                numberOfProbes: 1
              }
            }
          }
          {
            name: 'CustomScriptExtension'
            properties: {
              publisher: 'Microsoft.Compute'
              type: 'CustomScriptExtension'
              typeHandlerVersion: '1.10'
              autoUpgradeMinorVersion: true
              settings: {
                commandToExecute: 'powershell.exe -Command "New-Item -Path C:\\inetpub\\wwwroot\\health -ItemType File -Force; Set-Content -Path C:\\inetpub\\wwwroot\\health\\index.html -Value \'OK\'; Install-WindowsFeature -Name Web-Server -IncludeManagementTools"'
              }
            }
          }
        ]
      }
      // Boot diagnostics for troubleshooting
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
        }
      }
    }
  }
  dependsOn: [
    loadBalancer
    vnetSubnet
  ]
}

// Outputs for reference
output vmssId string = vmss.id
output vmssName string = vmss.name
output loadBalancerPublicIP string = publicIP.properties.ipAddress
output loadBalancerFQDN string = publicIP.properties.dnsSettings.fqdn
output healthProbeEndpoint string = 'http://${publicIP.properties.ipAddress}${healthProbePath}'
