param location string = 'uksouth'
param resourceName string = 'id-abac-workload-bicep'

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: resourceName
  location: location
  tags: {
    project: 'abac-azure'
    managed_by: 'bicep'
  }
}

output principalId string = userAssignedIdentity.properties.principalId
output clientId string = userAssignedIdentity.properties.clientId
