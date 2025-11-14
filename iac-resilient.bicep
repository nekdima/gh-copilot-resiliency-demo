@description('The name prefix for the VMSS')
param vmssName string = 'vmss'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The VM size for the VMSS instances')
param vmSize string = 'Standard_B2s'

@description('The number of VM instances')
@minValue(3)
param instanceCount int = 3

@description('Admin username for the VMs')
param adminUsername string

@description('Admin password for the VMs')
@secure()
param adminPassword string

@description('Availability zones to deploy VMSS instances across')
param zones array = ['1', '2', '3']

@description('Enable automatic OS upgrades')
param enableAutomaticOSUpgrade bool = true

@description('Grace period for automatic repairs (in minutes)')
@minValue(30)
@maxValue(90)
param repairGracePeriod int = 30

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
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

// Virtual Machine Scale Set with Flexible orchestration and zone redundancy
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-03-01' = {
  name: vmssName
  location: location
  zones: zones
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: instanceCount
  }
  properties: {
    // APRL: Use Flex orchestration mode for better scalability and availability
    orchestrationMode: 'Flexible'
    // APRL: Disable strict zone balancing to avoid scale operation failures
    platformFaultDomainCount: 1
    singlePlacementGroup: false
    // APRL: Enable automatic repairs for high availability
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: 'PT${repairGracePeriod}M'
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
          deleteOption: 'Delete'
        }
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-datacenter-azure-edition'
          version: 'latest'
        }
      }
      osProfile: {
        computerNamePrefix: vmssName
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
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}-nic'
            properties: {
              primary: true
              enableAcceleratedNetworking: false
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: vnet.properties.subnets[0].id
                    }
                    primary: true
                  }
                }
              ]
            }
          }
        ]
      }
      // APRL: Enable application health monitoring extension
      extensionProfile: {
        extensions: [
          {
            name: 'HealthExtension'
            properties: {
              publisher: 'Microsoft.ManagedServices'
              type: 'ApplicationHealthWindows'
              typeHandlerVersion: '1.0'
              autoUpgradeMinorVersion: true
              settings: {
                protocol: 'tcp'
                port: 80
                intervalInSeconds: 30
                numberOfProbes: 3
              }
            }
          }
        ]
      }
    }
    // APRL: Configure upgrade policy for automatic OS upgrades
    upgradePolicy: {
      mode: enableAutomaticOSUpgrade ? 'Automatic' : 'Manual'
      automaticOSUpgradePolicy: enableAutomaticOSUpgrade
        ? {
            enableAutomaticOSUpgrade: true
            disableAutomaticRollback: false
            useRollingUpgradePolicy: true
          }
        : null
      rollingUpgradePolicy: enableAutomaticOSUpgrade
        ? {
            maxBatchInstancePercent: 20
            maxUnhealthyInstancePercent: 20
            maxUnhealthyUpgradedInstancePercent: 20
            pauseTimeBetweenBatches: 'PT0S'
            prioritizeUnhealthyInstances: false
            rollbackFailedInstancesOnPolicyBreach: false
          }
        : null
    }
  }
}

// APRL: Configure autoscale settings for scalability
resource autoscaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${vmssName}-autoscale'
  location: location
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    // APRL: Enable predictive autoscale for forecast-based scaling
    predictiveAutoscalePolicy: {
      scaleMode: 'ForecastOnly'
      scaleLookAheadTime: 'PT10M'
    }
    profiles: [
      {
        name: 'Auto created scale condition'
        capacity: {
          default: string(instanceCount)
          minimum: '3'
          maximum: '10'
        }
        rules: [
          {
            scaleAction: {
              type: 'ChangeCount'
              direction: 'Increase'
              cooldown: 'PT5M'
              value: '1'
            }
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'microsoft.compute/virtualmachinescalesets'
              metricResourceUri: vmss.id
              operator: 'GreaterThan'
              statistic: 'Average'
              threshold: 75
              timeAggregation: 'Average'
              timeGrain: 'PT1M'
              timeWindow: 'PT5M'
            }
          }
          {
            scaleAction: {
              type: 'ChangeCount'
              direction: 'Decrease'
              cooldown: 'PT5M'
              value: '1'
            }
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'microsoft.compute/virtualmachinescalesets'
              metricResourceUri: vmss.id
              operator: 'LessThan'
              statistic: 'Average'
              threshold: 25
              timeAggregation: 'Average'
              timeGrain: 'PT1M'
              timeWindow: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}

// Outputs
output vmssId string = vmss.id
output vmssName string = vmss.name
output vnetId string = vnet.id
output autoscaleSettingsId string = autoscaleSettings.id
