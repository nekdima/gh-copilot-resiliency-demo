@description('The name prefix for the VMSS')
param vmssName string = 'vmss'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The VM size for the VMSS instances')
param vmSize string = 'Standard_B2s'

@description('The number of VM instances')
param instanceCount int = 2

@description('Admin username for the VMs')
param adminUsername string

@description('Admin password for the VMs')
@secure()
param adminPassword string

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
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

// Virtual Machine Scale Set (NOT zone resilient)
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-03-01' = {
  name: vmssName
  location: location
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: instanceCount
  }
  properties: {
    orchestrationMode: 'Uniform'
    upgradePolicy: {
      mode: 'Manual'
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
        computerNamePrefix: vmssName
        adminUsername: adminUsername
        adminPassword: adminPassword
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
    }
  }
}
