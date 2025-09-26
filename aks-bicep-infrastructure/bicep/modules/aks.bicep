// =============================================================================
// AKS Cluster Module with Production-Ready Configuration
// =============================================================================
// This module creates an enterprise-grade AKS cluster with system and user
// node pools, integrated monitoring, security features, and AGIC support.

@description('AKS cluster name')
param clusterName string

@description('Azure region for the AKS cluster')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

@description('Kubernetes version')
param kubernetesVersion string = '1.30.6'

@description('VM size for system node pool')
param systemNodeVmSize string = 'Standard_B2s'

@description('VM size for user node pool')
param userNodeVmSize string = 'Standard_B2s'

@description('Number of nodes in system node pool')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 2

@description('Number of nodes in user node pool')
@minValue(1)
@maxValue(10)
param userNodeCount int = 2

@description('Virtual network name')
param vnetName string

@description('Subnet name for AKS cluster')
param subnetName string

@description('Azure Container Registry name')
param acrName string

@description('Managed identity name for AKS')
param managedIdentityName string

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string = ''

@description('Application Gateway name')
param appGatewayName string = ''

@description('Enable Azure Monitor for containers')
param enableMonitoring bool = true

@description('Enable Application Gateway Ingress Controller')
param enableAGIC bool = true

// =============================================================================
// VARIABLES
// =============================================================================

var nodeResourceGroupName = 'MC_${resourceGroup().name}_${clusterName}_${location}'

// =============================================================================
// EXISTING RESOURCES
// =============================================================================

// Reference to existing virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
}

// Reference to existing subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: subnetName
}

// Reference to existing ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Reference to existing managed identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
}

// Reference to existing Application Gateway (if AGIC is enabled)
resource appGateway 'Microsoft.Network/applicationGateways@2023-09-01' existing = if (enableAGIC) {
  name: appGatewayName
}

// =============================================================================
// AKS CLUSTER
// =============================================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-10-01' = {
  name: clusterName
  location: location
  tags: union(tags, {
    Description: 'Production-ready AKS cluster with monitoring and security'
    ClusterType: 'AKS'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    nodeResourceGroup: nodeResourceGroupName
    dnsPrefix: '${clusterName}-dns'

    // =============================================================================
    // NETWORK CONFIGURATION
    // =============================================================================
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      serviceCidr: '10.100.0.0/16'
      dnsServiceIP: '10.100.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }

    // =============================================================================
    // SYSTEM NODE POOL
    // =============================================================================
    agentPoolProfiles: [
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: subnet.id
        maxPods: 30
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        nodeLabels: {
          'nodepool-type': 'system'
          'environment': 'production'
          'nodepoolos': 'linux'
        }
        enableAutoScaling: true
        minCount: 1
        maxCount: systemNodeCount + 2
        enableNodePublicIP: false
        enableEncryptionAtHost: false
        upgradeSettings: {
          maxSurge: '33%'
        }
      }
    ]

    // =============================================================================
    // SECURITY CONFIGURATION
    // =============================================================================
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: enableMonitoring ? logAnalyticsWorkspaceId : null
        securityMonitoring: {
          enabled: enableMonitoring
        }
      }
      workloadIdentity: {
        enabled: true
      }
    }

    // =============================================================================
    // ADDON PROFILES
    // =============================================================================
    addonProfiles: union(
      // Base addons
      {
        azureKeyvaultSecretsProvider: {
          enabled: true
          config: {
            enableSecretRotation: 'true'
            rotationPollInterval: '2m'
          }
        }
        azurepolicy: {
          enabled: true
        }
      },
      // Conditional monitoring addon
      enableMonitoring ? {
        omsagent: {
          enabled: true
          config: {
            logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          }
        }
      } : {},
      // Conditional AGIC addon
      enableAGIC ? {
        ingressApplicationGateway: {
          enabled: true
          config: {
            applicationGatewayId: appGateway.id
          }
        }
      } : {}
    )

    // =============================================================================
    // RBAC AND AAD INTEGRATION
    // =============================================================================
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: []
    }

    // =============================================================================
    // API SERVER CONFIGURATION
    // =============================================================================
    apiServerAccessProfile: {
      enablePrivateCluster: false
      enablePrivateClusterPublicFQDN: false
      authorizedIPRanges: []
    }

    // =============================================================================
    // AUTO UPGRADE CONFIGURATION
    // =============================================================================
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }

    // =============================================================================
    // FEATURES
    // =============================================================================
    oidcIssuerProfile: {
      enabled: true
    }

    disableLocalAccounts: false
    enableRBAC: true

    // =============================================================================
    // STORAGE PROFILE
    // =============================================================================
    storageProfile: {
      blobCSIDriver: {
        enabled: true
      }
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
  }
}

// =============================================================================
// USER NODE POOL
// =============================================================================

resource userNodePool 'Microsoft.ContainerService/managedClusters/agentPools@2023-10-01' = {
  parent: aksCluster
  name: 'user'
  properties: {
    count: userNodeCount
    vmSize: userNodeVmSize
    osType: 'Linux'
    osSKU: 'Ubuntu'
    mode: 'User'
    type: 'VirtualMachineScaleSets'
    vnetSubnetID: subnet.id
    maxPods: 30
    nodeLabels: {
      'nodepool-type': 'user'
      'environment': 'production'
      'nodepoolos': 'linux'
    }
    enableAutoScaling: true
    minCount: 1
    maxCount: userNodeCount + 3
    enableNodePublicIP: false
    enableEncryptionAtHost: false
    upgradeSettings: {
      maxSurge: '33%'
    }
  }
}

// =============================================================================
// ROLE ASSIGNMENTS
// =============================================================================

// Assign AcrPull role to AKS cluster identity for ACR access
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, managedIdentity.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Network Contributor role to AKS cluster identity for subnet access
resource networkContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subnet.id, managedIdentity.id, 'NetworkContributor')
  scope: subnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7') // Network Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Contributor role to Application Gateway if AGIC is enabled
resource agicContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAGIC) {
  name: guid(appGateway.id, managedIdentity.id, 'Contributor')
  scope: appGateway
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The resource ID of the AKS cluster')
output clusterId string = aksCluster.id

@description('The name of the AKS cluster')
output clusterName string = aksCluster.name

@description('The FQDN of the AKS cluster')
output clusterFqdn string = aksCluster.properties.fqdn

@description('The node resource group name')
output nodeResourceGroup string = nodeResourceGroupName

@description('The OIDC issuer URL')
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL

@description('The kubelet identity client ID')
output kubeletIdentityClientId string = aksCluster.properties.identityProfile.kubeletidentity.clientId

@description('The kubelet identity object ID')
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId