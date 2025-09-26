// =============================================================================
// Application Gateway Module with WAF Protection
// =============================================================================
// This module creates an Application Gateway with Web Application Firewall
// for secure ingress to AKS workloads.

@description('Application Gateway name')
param appGatewayName string

@description('Azure region')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

@description('Virtual network name')
param vnetName string

@description('Subnet name for Application Gateway')
param subnetName string

@description('Public IP name')
param publicIpName string

@description('Application Gateway SKU')
@allowed(['Standard_v2', 'WAF_v2'])
param gatewaySku string = 'WAF_v2'

@description('Application Gateway tier')
@allowed(['Standard_v2', 'WAF_v2'])
param gatewayTier string = 'WAF_v2'

@description('Minimum capacity units')
@minValue(0)
@maxValue(125)
param minCapacity int = 1

@description('Maximum capacity units')
@minValue(2)
@maxValue(125)
param maxCapacity int = 3

// =============================================================================
// EXISTING RESOURCES
// =============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: subnetName
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' existing = {
  name: publicIpName
}

// =============================================================================
// APPLICATION GATEWAY
// =============================================================================

resource applicationGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: appGatewayName
  location: location
  tags: union(tags, {
    Description: 'Application Gateway with WAF for AKS ingress'
    ServiceType: 'ApplicationGateway'
  })
  properties: {
    sku: {
      name: gatewaySku
      tier: gatewayTier
    }

    // =============================================================================
    // AUTO SCALING CONFIGURATION
    // =============================================================================
    autoscaleConfiguration: {
      minCapacity: minCapacity
      maxCapacity: maxCapacity
    }

    // =============================================================================
    // GATEWAY IP CONFIGURATION
    // =============================================================================
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnet.id
          }
        }
      }
    ]

    // =============================================================================
    // FRONTEND IP CONFIGURATIONS
    // =============================================================================
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]

    // =============================================================================
    // FRONTEND PORTS
    // =============================================================================
    frontendPorts: [
      {
        name: 'port80'
        properties: {
          port: 80
        }
      }
      {
        name: 'port443'
        properties: {
          port: 443
        }
      }
    ]

    // =============================================================================
    // BACKEND ADDRESS POOLS
    // =============================================================================
    backendAddressPools: [
      {
        name: 'defaultBackendPool'
        properties: {
          backendAddresses: []
        }
      }
    ]

    // =============================================================================
    // BACKEND HTTP SETTINGS
    // =============================================================================
    backendHttpSettingsCollection: [
      {
        name: 'defaultHttpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          connectionDraining: {
            enabled: true
            drainTimeoutInSec: 60
          }
          requestTimeout: 30
        }
      }
      {
        name: 'httpsSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          connectionDraining: {
            enabled: true
            drainTimeoutInSec: 60
          }
          requestTimeout: 30
        }
      }
    ]

    // =============================================================================
    // HTTP LISTENERS
    // =============================================================================
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'appGatewayFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'port80')
          }
          protocol: 'Http'
        }
      }
    ]

    // =============================================================================
    // REQUEST ROUTING RULES
    // =============================================================================
    requestRoutingRules: [
      {
        name: 'defaultRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'httpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'defaultBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'defaultHttpSettings')
          }
        }
      }
    ]

    // =============================================================================
    // WEB APPLICATION FIREWALL (WAF) CONFIGURATION
    // =============================================================================
    webApplicationFirewallConfiguration: gatewaySku == 'WAF_v2' ? {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
      disabledRuleGroups: []
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      exclusions: []
    } : null

    // =============================================================================
    // SSL POLICY
    // =============================================================================
    sslPolicy: {
      policyType: 'Predefined'
      policyName: 'AppGwSslPolicy20220101'
    }

    // =============================================================================
    // ENABLE HTTP2
    // =============================================================================
    enableHttp2: true

    // =============================================================================
    // FIREWALL POLICY (for WAF_v2)
    // =============================================================================
    firewallPolicy: gatewaySku == 'WAF_v2' ? {
      id: wafPolicy.id
    } : null
  }
}

// =============================================================================
// WAF POLICY (for WAF_v2 SKU)
// =============================================================================

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = if (gatewaySku == 'WAF_v2') {
  name: '${appGatewayName}-waf-policy'
  location: location
  tags: tags
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Prevention'
      requestBodyInspectLimitInKB: 128
      fileUploadEnforcement: true
      requestBodyEnforcement: true
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '0.1'
          ruleGroupOverrides: []
        }
      ]
      exclusions: []
    }
    customRules: [
      {
        name: 'BlockHighRiskCountries'
        priority: 100
        ruleType: 'MatchRule'
        action: 'Block'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'GeoMatch'
            negationConditon: false
            matchValues: [
              'CN'
              'RU'
              'KP'
            ]
          }
        ]
      }
    ]
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The resource ID of the Application Gateway')
output appGatewayId string = applicationGateway.id

@description('The name of the Application Gateway')
output appGatewayName string = applicationGateway.name

@description('The public IP address of the Application Gateway')
output publicIpAddress string = publicIp.properties.ipAddress

@description('The FQDN of the Application Gateway')
output fqdn string = publicIp.properties.dnsSettings.fqdn

@description('The resource ID of the WAF policy (if WAF is enabled)')
output wafPolicyId string = gatewaySku == 'WAF_v2' ? wafPolicy.id : ''