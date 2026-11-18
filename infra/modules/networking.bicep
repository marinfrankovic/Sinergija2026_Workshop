// Dedicated workshop network: apps reach the private vault without policy exemptions.
param location string
param tags object
param name string
param keyVaultId string
param keyVaultName string

resource vnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.214.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-containerapps'
        properties: {
          addressPrefix: '10.214.0.0/24'
          delegations: [
            {
              name: 'containerapps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.214.1.0/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource vaultZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource vaultZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: vaultZone
  name: name
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource vaultEndpoint 'Microsoft.Network/privateEndpoints@2026-03-01' = {
  name: 'pe-${keyVaultName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/snet-private-endpoints'
    }
    privateLinkServiceConnections: [
      {
        name: 'keyvault'
        properties: {
          privateLinkServiceId: keyVaultId
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource vaultZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2026-03-01' = {
  parent: vaultEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyvault'
        properties: {
          privateDnsZoneId: vaultZone.id
        }
      }
    ]
  }
}

output infrastructureSubnetId string = '${vnet.id}/subnets/snet-containerapps'
