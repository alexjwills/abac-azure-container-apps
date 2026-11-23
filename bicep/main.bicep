targetScope = 'subscription' 
param location string = 'uksouth'
param resourceName string = 'rg-abac-bicep'

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceName
  location: location
  tags: {
    project: 'abac-azure'
    managed_by: 'bicep'
  }
}

module identity 'identity.bicep' = {
  name: 'identity-deployment'
  scope: rg
  params: {
    location: location
  }
}

output principalId string = identity.outputs.principalId
