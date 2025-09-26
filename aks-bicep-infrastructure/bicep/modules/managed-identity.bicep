// =============================================================================
// Managed Identity Module for AKS
// =============================================================================

@description('Managed identity name')
param identityName string

@description('Azure region')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

// =============================================================================
// USER ASSIGNED MANAGED IDENTITY
// =============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: union(tags, {
    Description: 'Managed identity for AKS cluster'
    ServiceType: 'ManagedIdentity'
  })
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The resource ID of the managed identity')
output identityId string = managedIdentity.id

@description('The name of the managed identity')
output identityName string = managedIdentity.name

@description('The principal ID of the managed identity')
output principalId string = managedIdentity.properties.principalId

@description('The client ID of the managed identity')
output clientId string = managedIdentity.properties.clientId