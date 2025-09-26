# AKS Infrastructure with Bicep

A comprehensive Azure Kubernetes Service (AKS) infrastructure deployment using Azure Bicep templates. This project demonstrates enterprise-grade DevOps practices with Infrastructure as Code (IaC), security best practices, and comprehensive monitoring.

## 🏗️ Architecture Overview

This infrastructure deploys a production-ready AKS cluster with:

- **Custom Virtual Network** with security-first subnet segmentation
- **AKS Cluster** with system and user node pools
- **Azure Container Registry** for container image management
- **Application Gateway** with Web Application Firewall (WAF)
- **Log Analytics Workspace** with comprehensive monitoring
- **Managed Identity** for secure Azure resource access

### Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Virtual Network (10.0.0.0/16)           │
├─────────────────────────────────────────────────────────────┤
│ AKS Subnet          │ App Gateway Subnet │ Monitoring Subnet │
│ (10.0.1.0/24)       │ (10.0.2.0/24)      │ (10.0.3.0/24)     │
│                     │                    │                   │
│ ┌─────────────────┐ │ ┌────────────────┐ │ ┌───────────────┐ │
│ │ System Nodes    │ │ │ App Gateway    │ │ │ Log Analytics │ │
│ │ User Nodes      │ │ │ with WAF       │ │ │ Prometheus    │ │
│ │ Pods Network    │ │ │                │ │ │ Grafana       │ │
│ └─────────────────┘ │ └────────────────┘ │ └───────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 📋 Prerequisites

Before deploying this infrastructure, ensure you have:

### Required Tools
- **Azure CLI** (version 2.40+)
- **Bicep CLI** (version 0.15+)
- **kubectl** (for cluster management)
- **Bash shell** (for deployment scripts)

### Azure Requirements
- **Azure Subscription** with Contributor access
- **Resource Group** created in your target region
- **Sufficient quota** for the VM sizes you plan to use

### Cost Considerations
- **Development**: ~$7-10/day (~$200-300/month)
- **Production**: ~$15-25/day (~$400-750/month)

## 🚀 Quick Start

### 1. Clone and Setup

```bash
# Clone the repository
git clone <repository-url>
cd aks-bicep-infrastructure

# Make scripts executable
chmod +x scripts/*.sh
```

### 2. Configure Parameters

Edit the parameter files for your environment:

```bash
# For development
vim bicep/parameters/dev.bicepparam

# For production
vim bicep/parameters/prod.bicepparam
```

### 3. Deploy Infrastructure

```bash
# Development deployment
./scripts/deploy.sh \
  --environment dev \
  --resource-group my-aks-rg \
  --subscription 12345678-1234-1234-1234-123456789012

# Production deployment
./scripts/deploy.sh \
  --environment prod \
  --resource-group my-prod-aks-rg \
  --subscription 12345678-1234-1234-1234-123456789012
```

### 4. Verify Deployment

```bash
# Check cluster status
kubectl get nodes

# Check pods
kubectl get pods --all-namespaces

# Check services
kubectl get services
```

## 📁 Project Structure

```
aks-bicep-infrastructure/
├── main.bicep                          # Main orchestration template
├── bicep/
│   ├── modules/                        # Reusable Bicep modules
│   │   ├── vnet.bicep                 # Virtual network with NSGs
│   │   ├── aks.bicep                  # AKS cluster configuration
│   │   ├── acr.bicep                  # Container registry
│   │   ├── application-gateway.bicep  # App Gateway with WAF
│   │   ├── log-analytics.bicep        # Monitoring workspace
│   │   ├── managed-identity.bicep     # Identity management
│   │   └── public-ip.bicep           # Public IP for App Gateway
│   └── parameters/                    # Environment-specific parameters
│       ├── dev.bicepparam            # Development environment
│       └── prod.bicepparam           # Production environment
├── scripts/
│   ├── deploy.sh                     # Main deployment script
│   └── cleanup.sh                    # Resource cleanup script
├── docs/                             # Additional documentation
├── monitoring/                       # Monitoring configurations
└── README.md                         # This file
```

## 🔧 Configuration

### Environment Parameters

#### Development Environment (`dev.bicepparam`)
```bicep
param namePrefix = 'devops-demo'
param environment = 'dev'
param systemNodeVmSize = 'Standard_B2s'    // Cost-optimized
param userNodeVmSize = 'Standard_B2s'      // Cost-optimized
param systemNodeCount = 1                   // Minimal
param userNodeCount = 1                     // Minimal
```

#### Production Environment (`prod.bicepparam`)
```bicep
param namePrefix = 'devops-prod'
param environment = 'prod'
param systemNodeVmSize = 'Standard_D2s_v3'  // Performance
param userNodeVmSize = 'Standard_D2s_v3'    // Performance
param systemNodeCount = 3                    // High availability
param userNodeCount = 3                      // Load distribution
```

### Customization Options

You can customize the deployment by modifying:

1. **VM Sizes**: Change `systemNodeVmSize` and `userNodeVmSize`
2. **Node Counts**: Adjust `systemNodeCount` and `userNodeCount`
3. **Kubernetes Version**: Update `kubernetesVersion`
4. **Features**: Toggle `enableMonitoring` and `enableAGIC`

## 🔒 Security Features

### Network Security
- **Network Security Groups (NSGs)** with restrictive rules
- **Private networking** for all internal communications
- **WAF protection** on Application Gateway
- **Network policies** for pod-to-pod communication

### Identity and Access
- **Managed Identity** for AKS cluster
- **Azure AD integration** for RBAC
- **Role-based access control** for Azure resources
- **Workload Identity** for pod authentication

### Security Monitoring
- **Azure Defender** for container security
- **Policy enforcement** with Azure Policy
- **Secret management** with Key Vault integration
- **Security scanning** for container images

## 📊 Monitoring and Observability

### Azure Monitor Integration
- **Container Insights** for cluster monitoring
- **Log Analytics** for centralized logging
- **Custom queries** for troubleshooting
- **Alert rules** for proactive monitoring

### Built-in Dashboards
- **Cluster health** and resource utilization
- **Node performance** metrics
- **Pod status** and lifecycle events
- **Network traffic** analysis

### Custom Monitoring
The infrastructure supports additional monitoring tools:
- **Prometheus** for metrics collection
- **Grafana** for visualization
- **Jaeger** for distributed tracing
- **Fluentd** for log forwarding

## 🛠️ Management Operations

### Scaling Operations

```bash
# Scale user node pool
az aks nodepool scale \
  --resource-group my-aks-rg \
  --cluster-name my-aks-cluster \
  --name user \
  --node-count 5

# Enable cluster autoscaler
az aks nodepool update \
  --resource-group my-aks-rg \
  --cluster-name my-aks-cluster \
  --name user \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 10
```

### Upgrade Operations

```bash
# Check available versions
az aks get-upgrades \
  --resource-group my-aks-rg \
  --name my-aks-cluster

# Upgrade cluster
az aks upgrade \
  --resource-group my-aks-rg \
  --name my-aks-cluster \
  --kubernetes-version 1.29.0
```

### Backup and Recovery

```bash
# Backup cluster configuration
kubectl get all --all-namespaces -o yaml > cluster-backup.yaml

# Backup persistent volumes
kubectl get pv -o yaml > pv-backup.yaml
```

## 🧹 Cleanup

To avoid ongoing costs, clean up the infrastructure when not needed:

```bash
# Safe cleanup with confirmations
./scripts/cleanup.sh \
  --resource-group my-aks-rg \
  --subscription 12345678-1234-1234-1234-123456789012

# Force cleanup (no prompts)
./scripts/cleanup.sh \
  --resource-group my-aks-rg \
  --subscription 12345678-1234-1234-1234-123456789012 \
  --force
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Deployment Failures
```bash
# Check deployment status
az deployment group show \
  --resource-group my-aks-rg \
  --name <deployment-name>

# View error details
az deployment group list \
  --resource-group my-aks-rg \
  --query "[?properties.provisioningState=='Failed']"
```

#### 2. Network Connectivity
```bash
# Test pod connectivity
kubectl run test-pod --image=busybox --rm -it -- /bin/sh

# Check DNS resolution
kubectl exec -it test-pod -- nslookup kubernetes.default
```

#### 3. Authentication Issues
```bash
# Refresh AKS credentials
az aks get-credentials \
  --resource-group my-aks-rg \
  --name my-aks-cluster \
  --overwrite-existing

# Check cluster connection
kubectl auth can-i "*" "*" --all-namespaces
```

### Log Analysis

```bash
# View cluster logs
kubectl logs -l app=my-app --tail=100

# Check system pods
kubectl get pods -n kube-system

# Monitor events
kubectl get events --sort-by='.metadata.creationTimestamp'
```

## 📚 Additional Resources

### Azure Documentation
- [AKS Best Practices](https://docs.microsoft.com/en-us/azure/aks/best-practices)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Application Gateway Ingress Controller](https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview)

### Learning Resources
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Azure Monitor for Containers](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

For issues and questions:
1. Check the troubleshooting section
2. Review Azure documentation
3. Open an issue in the repository
4. Contact the DevOps team

---

**Built with ❤️ for DevOps excellence**