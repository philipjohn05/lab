// =============================================================================
// AKS Infrastructure with Custom VNet, Monitoring, and Security
// =============================================================================
// This is the main Bicep template that orchestrates the entire infrastructure
// deployment including VNet, AKS cluster, ACR, Application Gateway, and monitoring.

targetScope = 'resourceGroup'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('The name prefix for all resources')
param namePrefix string = 'devops'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('AKS cluster version')
param kubernetesVersion string = '1.30.6'

@description('VM size for AKS system nodes')
param systemNodeVmSize string = 'Standard_B2s'

@description('VM size for AKS user nodes')
param userNodeVmSize string = 'Standard_B2s'

@description('Number of nodes in the system node pool')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 2

@description('Number of nodes in the user node pool')
@minValue(1)
@maxValue(10)
param userNodeCount int = 2

@description('Enable Azure Monitor for containers')
param enableMonitoring bool = true

@description('Enable Application Gateway Ingress Controller')
param enableAGIC bool = true

// =============================================================================
// VARIABLES
// =============================================================================

var commonTags = {
  Environment: environment
  Project: 'AKS-DevOps-Infrastructure'
  ManagedBy: 'Bicep'
  Owner: 'DevOps-Team'
}

var resourceNames = {
  vnet: '${namePrefix}-vnet-${environment}'
  aks: '${namePrefix}-aks-${environment}'
  acr: '${namePrefix}acr${environment}${uniqueString(resourceGroup().id)}'
  appGateway: '${namePrefix}-agw-${environment}'
  logAnalytics: '${namePrefix}-logs-${environment}'
  publicIp: '${namePrefix}-agw-pip-${environment}'
  managedIdentity: '${namePrefix}-identity-${environment}'
}

// =============================================================================
// MODULE DEPLOYMENTS
// =============================================================================

// Deploy Log Analytics Workspace (needed for monitoring)
module logAnalytics 'bicep/modules/log-analytics.bicep' = if (enableMonitoring) {
  name: 'logAnalytics-deployment'
  params: {
    workspaceName: resourceNames.logAnalytics
    location: location
    tags: commonTags
  }
}

// Deploy Virtual Network with subnets
module vnet 'bicep/modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    vnetName: resourceNames.vnet
    location: location
    tags: commonTags
  }
}

// Deploy Azure Container Registry
module acr 'bicep/modules/acr.bicep' = {
  name: 'acr-deployment'
  params: {
    acrName: resourceNames.acr
    location: location
    tags: commonTags
  }
}

// Deploy Managed Identity for AKS
module managedIdentity 'bicep/modules/managed-identity.bicep' = {
  name: 'managedIdentity-deployment'
  params: {
    identityName: resourceNames.managedIdentity
    location: location
    tags: commonTags
  }
}

// Deploy Public IP for Application Gateway
module publicIp 'bicep/modules/public-ip.bicep' = if (enableAGIC) {
  name: 'publicIp-deployment'
  params: {
    publicIpName: resourceNames.publicIp
    location: location
    tags: commonTags
  }
}

// Deploy Application Gateway
module appGateway 'bicep/modules/application-gateway.bicep' = if (enableAGIC) {
  name: 'appGateway-deployment'
  params: {
    appGatewayName: resourceNames.appGateway
    location: location
    tags: commonTags
    vnetName: vnet.outputs.vnetName
    subnetName: vnet.outputs.appGatewaySubnetName
    publicIpName: enableAGIC ? publicIp.outputs.publicIpName : ''
  }
  dependsOn: [
    vnet
    publicIp
  ]
}

// Deploy AKS Cluster
module aks 'bicep/modules/aks.bicep' = {
  name: 'aks-deployment'
  params: {
    clusterName: resourceNames.aks
    location: location
    tags: commonTags
    kubernetesVersion: kubernetesVersion
    systemNodeVmSize: systemNodeVmSize
    userNodeVmSize: userNodeVmSize
    systemNodeCount: systemNodeCount
    userNodeCount: userNodeCount
    vnetName: vnet.outputs.vnetName
    subnetName: vnet.outputs.aksSubnetName
    acrName: acr.outputs.acrName
    managedIdentityName: managedIdentity.outputs.identityName
    logAnalyticsWorkspaceId: enableMonitoring ? logAnalytics.outputs.workspaceId : ''
    appGatewayName: enableAGIC ? appGateway.outputs.appGatewayName : ''
    enableMonitoring: enableMonitoring
    enableAGIC: enableAGIC
  }
  dependsOn: [
    vnet
    acr
    managedIdentity
    logAnalytics
    appGateway
  ]
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The name of the AKS cluster')
output aksClusterName string = aks.outputs.clusterName

@description('The FQDN of the AKS cluster')
output aksClusterFqdn string = aks.outputs.clusterFqdn

@description('The name of the Azure Container Registry')
output acrName string = acr.outputs.acrName

@description('The login server of the Azure Container Registry')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('The name of the virtual network')
output vnetName string = vnet.outputs.vnetName

@description('The Application Gateway public IP (if enabled)')
output appGatewayPublicIp string = enableAGIC ? appGateway.outputs.publicIpAddress : ''

@description('The Log Analytics workspace ID (if monitoring enabled)')
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalytics.outputs.workspaceId : ''