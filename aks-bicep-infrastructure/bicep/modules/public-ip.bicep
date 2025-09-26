// =============================================================================
// Public IP Module for Application Gateway
// =============================================================================

@description('Public IP name')
param publicIpName string

@description('Azure region')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

@description('Public IP allocation method')
@allowed(['Static', 'Dynamic'])
param allocationMethod string = 'Static'

@description('Public IP SKU')
@allowed(['Basic', 'Standard'])
param publicIpSku string = 'Standard'

// =============================================================================
// PUBLIC IP ADDRESS
// =============================================================================

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  tags: union(tags, {
    Description: 'Public IP for Application Gateway'
    ServiceType: 'PublicIP'
  })
  sku: {
    name: publicIpSku
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: allocationMethod
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${publicIpName}-${uniqueString(resourceGroup().id)}')
    }
    idleTimeoutInMinutes: 4
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The resource ID of the public IP')
output publicIpId string = publicIp.id

@description('The name of the public IP')
output publicIpName string = publicIp.name

@description('The IP address')
output publicIpAddress string = publicIp.properties.ipAddress

@description('The FQDN')
output fqdn string = publicIp.properties.dnsSettings.fqdn