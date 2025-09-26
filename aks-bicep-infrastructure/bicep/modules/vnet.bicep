// =============================================================================
// Virtual Network Module with Security-First Design
// =============================================================================
// This module creates a hub-and-spoke network architecture with proper
// subnet segmentation for AKS, Application Gateway, and monitoring components.

@description('Virtual network name')
param vnetName string

@description('Azure region for the virtual network')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

// =============================================================================
// NETWORK CONFIGURATION
// =============================================================================

// Address space planning for enterprise-grade network segmentation
var vnetAddressPrefix = '10.0.0.0/16'

// Subnet configuration with security zones
var subnets = [
  {
    name: 'AKS-Subnet'
    addressPrefix: '10.0.1.0/24'
    purpose: 'AKS cluster nodes and pods'
    delegations: []
    routeTable: 'AKS-RouteTable'
    nsg: 'AKS-NSG'
  }
  {
    name: 'AppGateway-Subnet'
    addressPrefix: '10.0.2.0/24'
    purpose: 'Application Gateway frontend'
    delegations: []
    routeTable: ''
    nsg: 'AppGateway-NSG'
  }
  {
    name: 'Monitoring-Subnet'
    addressPrefix: '10.0.3.0/24'
    purpose: 'Monitoring and logging services'
    delegations: []
    routeTable: ''
    nsg: 'Monitoring-NSG'
  }
  {
    name: 'Management-Subnet'
    addressPrefix: '10.0.4.0/24'
    purpose: 'Management and bastion services'
    delegations: []
    routeTable: ''
    nsg: 'Management-NSG'
  }
]

// =============================================================================
// NETWORK SECURITY GROUPS
// =============================================================================

// NSG for AKS subnet - restrictive by default
resource aksNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'AKS-NSG'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-AKS-Internal'
        properties: {
          description: 'Allow internal AKS communication'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '10.0.1.0/24'
          destinationAddressPrefix: '10.0.1.0/24'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-AppGateway-to-AKS'
        properties: {
          description: 'Allow Application Gateway to reach AKS services'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['80', '443', '8080']
          sourceAddressPrefix: '10.0.2.0/24'
          destinationAddressPrefix: '10.0.1.0/24'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-Monitoring'
        properties: {
          description: 'Allow monitoring traffic from monitoring subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['9090', '3000', '8080']
          sourceAddressPrefix: '10.0.3.0/24'
          destinationAddressPrefix: '10.0.1.0/24'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4000
          direction: 'Inbound'
        }
      }
    ]
  }
}

// NSG for Application Gateway subnet
resource appGatewayNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'AppGateway-NSG'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          description: 'Allow HTTP traffic from internet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          description: 'Allow HTTPS traffic from internet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-AppGateway-Management'
        properties: {
          description: 'Allow Application Gateway management traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
    ]
  }
}

// NSG for Monitoring subnet
resource monitoringNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'Monitoring-NSG'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Prometheus'
        properties: {
          description: 'Allow Prometheus scraping'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '9090'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-Grafana'
        properties: {
          description: 'Allow Grafana dashboard access'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3000'
          sourceAddressPrefix: '10.0.2.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// NSG for Management subnet
resource managementNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'Management-NSG'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          description: 'Allow SSH for management'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.4.0/24'
          destinationAddressPrefix: '10.0.0.0/16'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

// =============================================================================
// ROUTE TABLES
// =============================================================================

// Route table for AKS subnet
resource aksRouteTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: 'AKS-RouteTable'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'InternetRoute'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
    ]
  }
}

// =============================================================================
// VIRTUAL NETWORK
// =============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: union(tags, {
    Description: 'Hub virtual network for AKS infrastructure'
    NetworkType: 'Hub'
  })
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    enableDdosProtection: false
    subnets: [
      {
        name: subnets[0].name
        properties: {
          addressPrefix: subnets[0].addressPrefix
          networkSecurityGroup: {
            id: aksNsg.id
          }
          routeTable: {
            id: aksRouteTable.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: subnets[1].name
        properties: {
          addressPrefix: subnets[1].addressPrefix
          networkSecurityGroup: {
            id: appGatewayNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: subnets[2].name
        properties: {
          addressPrefix: subnets[2].addressPrefix
          networkSecurityGroup: {
            id: monitoringNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: subnets[3].name
        properties: {
          addressPrefix: subnets[3].addressPrefix
          networkSecurityGroup: {
            id: managementNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The resource ID of the virtual network')
output vnetId string = vnet.id

@description('The name of the virtual network')
output vnetName string = vnet.name

@description('The address prefix of the virtual network')
output vnetAddressPrefix string = vnetAddressPrefix

@description('The name of the AKS subnet')
output aksSubnetName string = subnets[0].name

@description('The resource ID of the AKS subnet')
output aksSubnetId string = vnet.properties.subnets[0].id

@description('The name of the Application Gateway subnet')
output appGatewaySubnetName string = subnets[1].name

@description('The resource ID of the Application Gateway subnet')
output appGatewaySubnetId string = vnet.properties.subnets[1].id

@description('The name of the Monitoring subnet')
output monitoringSubnetName string = subnets[2].name

@description('The resource ID of the Monitoring subnet')
output monitoringSubnetId string = vnet.properties.subnets[2].id

@description('The name of the Management subnet')
output managementSubnetName string = subnets[3].name

@description('The resource ID of the Management subnet')
output managementSubnetId string = vnet.properties.subnets[3].id