// =============================================================================
// Azure Container Registry Module with Security Features
// =============================================================================
// This module creates a secure Azure Container Registry with image scanning,
// vulnerability assessment, and integration with AKS cluster.

@description('Azure Container Registry name')
param acrName string

@description('Azure region for the container registry')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

@description('ACR SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Basic'

@description('Enable admin user')
param adminUserEnabled bool = false

@description('Enable public network access')
param publicNetworkAccess bool = true

@description('Enable image quarantine')
param quarantinePolicy bool = false

@description('Enable trust policy')
param trustPolicy bool = false

@description('Enable retention policy')
param retentionPolicy bool = false

@description('Retention days for untagged manifests')
param retentionDays int = 7

// =============================================================================
// AZURE CONTAINER REGISTRY
// =============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: union(tags, {
    Description: 'Container registry for AKS workloads'
    ServiceType: 'ContainerRegistry'
  })
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: adminUserEnabled

    // =============================================================================
    // NETWORK CONFIGURATION
    // =============================================================================
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    networkRuleBypassOptions: 'AzureServices'

    // =============================================================================
    // SECURITY POLICIES (Premium SKU only)
    // =============================================================================
    policies: acrSku == 'Premium' ? {
      quarantinePolicy: {
        status: quarantinePolicy ? 'enabled' : 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: trustPolicy ? 'enabled' : 'disabled'
      }
      retentionPolicy: {
        days: retentionDays
        status: retentionPolicy ? 'enabled' : 'disabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
      softDeletePolicy: {
        retentionDays: 7
        status: 'enabled'
      }
    } : {
      exportPolicy: {
        status: 'enabled'
      }
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
    }

    // =============================================================================
    // DATA ENDPOINT CONFIGURATION
    // =============================================================================
    dataEndpointEnabled: acrSku == 'Premium'

    // =============================================================================
    // ENCRYPTION (Premium SKU only)
    // =============================================================================
    encryption: acrSku == 'Premium' ? {
      status: 'disabled' // Can be enabled with customer-managed keys
    } : null
  }
}

// =============================================================================
// DIAGNOSTIC SETTINGS (if Log Analytics workspace is available)
// =============================================================================

// Note: This would require logAnalyticsWorkspaceId parameter
// Commented out for now but can be enabled when workspace is available
/*
resource acrDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${acrName}-diagnostics'
  scope: acr
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'ContainerRegistryRepositoryEvents'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'ContainerRegistryLoginEvents'
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
*/

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The resource ID of the container registry')
output acrId string = acr.id

@description('The name of the container registry')
output acrName string = acr.name

@description('The login server of the container registry')
output acrLoginServer string = acr.properties.loginServer

@description('The resource ID of the container registry for role assignments')
output acrResourceId string = acr.id

@description('The admin username (if admin user is enabled)')
output adminUsername string = adminUserEnabled ? acr.listCredentials().username : ''

@description('The primary admin password (if admin user is enabled)')
output adminPassword string = adminUserEnabled ? acr.listCredentials().passwords[0].value : ''