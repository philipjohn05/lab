// =============================================================================
// Log Analytics Workspace Module for Monitoring
// =============================================================================
// This module creates a Log Analytics workspace for centralized logging
// and monitoring of AKS cluster and infrastructure components.

@description('Log Analytics workspace name')
param workspaceName string

@description('Azure region')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

@description('Workspace SKU')
@allowed(['Free', 'Standalone', 'PerNode', 'PerGB2018'])
param workspaceSku string = 'PerGB2018'

@description('Data retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Daily quota in GB (-1 for unlimited)')
param dailyQuotaGb int = -1

// =============================================================================
// LOG ANALYTICS WORKSPACE
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: union(tags, {
    Description: 'Log Analytics workspace for AKS monitoring'
    ServiceType: 'LogAnalytics'
  })
  properties: {
    sku: {
      name: workspaceSku
    }
    retentionInDays: retentionInDays
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: dailyQuotaGb > 0 ? {
      dailyQuotaGb: dailyQuotaGb
    } : null
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// MONITORING SOLUTIONS
// =============================================================================

// Container Insights solution for AKS monitoring
resource containerInsightsSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ContainerInsights(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'ContainerInsights(${logAnalyticsWorkspace.name})'
    product: 'OMSGallery/ContainerInsights'
    publisher: 'Microsoft'
    promotionCode: ''
  }
}

// Security solution for security monitoring
resource securitySolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'Security(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'Security(${logAnalyticsWorkspace.name})'
    product: 'OMSGallery/Security'
    publisher: 'Microsoft'
    promotionCode: ''
  }
}

// Service Map solution for dependency mapping
resource serviceMapSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ServiceMap(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'ServiceMap(${logAnalyticsWorkspace.name})'
    product: 'OMSGallery/ServiceMap'
    publisher: 'Microsoft'
    promotionCode: ''
  }
}

// =============================================================================
// CUSTOM LOG QUERIES AND ALERTS
// =============================================================================

// Saved search for high CPU usage
resource highCpuSearch 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'HighCpuUsage'
  properties: {
    category: 'AKS Monitoring'
    displayName: 'High CPU Usage Alert'
    query: '''
Perf
| where ObjectName == "K8SContainer" and CounterName == "cpuUsageNanoCores"
| where TimeGenerated > ago(5m)
| summarize AvgCPU = avg(CounterValue) by Computer, InstanceName
| where AvgCPU > 80
| project Computer, InstanceName, AvgCPU
'''
    version: 2
  }
}

// Saved search for memory pressure
resource highMemorySearch 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'HighMemoryUsage'
  properties: {
    category: 'AKS Monitoring'
    displayName: 'High Memory Usage Alert'
    query: '''
Perf
| where ObjectName == "K8SContainer" and CounterName == "memoryWorkingSetBytes"
| where TimeGenerated > ago(5m)
| summarize AvgMemory = avg(CounterValue) by Computer, InstanceName
| where AvgMemory > 1073741824
| project Computer, InstanceName, AvgMemoryGB = AvgMemory/1024/1024/1024
'''
    version: 2
  }
}

// Saved search for failed pods
resource failedPodsSearch 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'FailedPods'
  properties: {
    category: 'AKS Monitoring'
    displayName: 'Failed Pods Alert'
    query: '''
KubePodInventory
| where TimeGenerated > ago(10m)
| where PodStatus in ("Failed", "Unknown")
| summarize count() by Namespace, Name, PodStatus
| project Namespace, PodName = Name, Status = PodStatus, Count = count_
'''
    version: 2
  }
}

// =============================================================================
// DATA COLLECTION RULES (for newer monitoring)
// =============================================================================

// Data Collection Endpoint
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: '${workspaceName}-dce'
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The resource ID of the Log Analytics workspace')
output workspaceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics workspace')
output workspaceName string = logAnalyticsWorkspace.name

@description('The workspace ID (GUID) for Log Analytics')
output workspaceGuid string = logAnalyticsWorkspace.properties.customerId

@description('The primary shared key for the workspace')
output workspaceKey string = logAnalyticsWorkspace.listKeys().primarySharedKey

@description('The resource ID of the data collection endpoint')
output dataCollectionEndpointId string = dataCollectionEndpoint.id