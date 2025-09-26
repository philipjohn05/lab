# AKS Infrastructure Deployment Guide

This comprehensive guide walks you through deploying enterprise-grade AKS infrastructure using Azure Bicep templates.

## 📋 Pre-Deployment Checklist

### Azure Account Setup
- [ ] Azure subscription with sufficient credits/budget
- [ ] Contributor or Owner role on the subscription
- [ ] Resource group created in target region
- [ ] Azure CLI installed and authenticated
- [ ] Bicep CLI installed (or use `az bicep`)

### Resource Quotas
Verify you have sufficient quota for:
- [ ] Virtual machines (4-10 cores minimum)
- [ ] Public IP addresses (1-2 required)
- [ ] Load balancers (1-2 required)
- [ ] Storage accounts (2-3 required)

### Cost Planning
- [ ] Understand daily/monthly cost implications
- [ ] Set up budget alerts in Azure
- [ ] Plan for auto-shutdown if needed

## 🔧 Step-by-Step Deployment

### Step 1: Environment Preparation

```bash
# 1. Login to Azure
az login

# 2. Set your subscription
az account set --subscription "your-subscription-id"

# 3. Create resource group (if not exists)
az group create \
  --name "aks-demo-rg" \
  --location "Australia Southeast"

# 4. Verify Bicep installation
az bicep version
```

### Step 2: Parameter Configuration

Choose your deployment size based on requirements:

#### Development Environment
- **Cost**: ~$7-10/day
- **Use case**: Learning, testing, small workloads
- **Configuration**: Minimal resources

```bash
# Edit dev parameters
vim bicep/parameters/dev.bicepparam
```

Key settings for development:
```bicep
param systemNodeVmSize = 'Standard_B2s'  // 2 vCPU, 4GB RAM
param userNodeVmSize = 'Standard_B2s'    // 2 vCPU, 4GB RAM
param systemNodeCount = 1                // Minimum for system
param userNodeCount = 1                  // Minimal user workload
```

#### Production Environment
- **Cost**: ~$15-25/day
- **Use case**: Production workloads, high availability
- **Configuration**: Robust, scalable resources

```bash
# Edit production parameters
vim bicep/parameters/prod.bicepparam
```

Key settings for production:
```bicep
param systemNodeVmSize = 'Standard_D2s_v3'  // 2 vCPU, 8GB RAM
param userNodeVmSize = 'Standard_D2s_v3'    // 2 vCPU, 8GB RAM
param systemNodeCount = 3                   // High availability
param userNodeCount = 3                     // Load distribution
```

### Step 3: Pre-Deployment Validation

```bash
# 1. Validate Bicep syntax
az bicep build --file main.bicep

# 2. Dry run deployment
./scripts/deploy.sh \
  --environment dev \
  --resource-group aks-demo-rg \
  --subscription your-subscription-id \
  --dry-run

# 3. Check resource quotas
az vm list-usage --location "Australia Southeast" --output table
```

### Step 4: Execute Deployment

#### Option A: Using the Deployment Script (Recommended)

```bash
# Development deployment
./scripts/deploy.sh \
  --environment dev \
  --resource-group aks-demo-rg \
  --subscription your-subscription-id \
  --verbose

# Production deployment
./scripts/deploy.sh \
  --environment prod \
  --resource-group aks-prod-rg \
  --subscription your-subscription-id \
  --verbose
```

#### Option B: Manual Azure CLI Deployment

```bash
# Deploy with Azure CLI
az deployment group create \
  --resource-group aks-demo-rg \
  --template-file main.bicep \
  --parameters bicep/parameters/dev.bicepparam \
  --name "aks-infrastructure-$(date +%Y%m%d-%H%M%S)"
```

### Step 5: Monitor Deployment Progress

The deployment typically takes 15-25 minutes. Monitor progress:

```bash
# Watch deployment status
az deployment group list \
  --resource-group aks-demo-rg \
  --output table

# Monitor specific deployment
az deployment group show \
  --resource-group aks-demo-rg \
  --name your-deployment-name \
  --output table
```

### Step 6: Post-Deployment Configuration

#### Configure kubectl Access

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group aks-demo-rg \
  --name your-aks-cluster-name \
  --overwrite-existing

# Verify connection
kubectl get nodes
kubectl get pods --all-namespaces
```

#### Verify Infrastructure Components

```bash
# Check cluster status
kubectl cluster-info

# Verify node pools
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Verify ingress controller (if AGIC enabled)
kubectl get pods -n kube-system | grep agic
```

## 🔍 Deployment Verification

### Infrastructure Health Checks

```bash
# 1. Check all Azure resources
az resource list \
  --resource-group aks-demo-rg \
  --output table

# 2. Verify AKS cluster
az aks show \
  --resource-group aks-demo-rg \
  --name your-aks-cluster \
  --query "{name:name,status:provisioningState,version:kubernetesVersion}"

# 3. Check Application Gateway (if enabled)
az network application-gateway show \
  --resource-group aks-demo-rg \
  --name your-app-gateway \
  --query "{name:name,status:provisioningState}"

# 4. Verify Container Registry
az acr show \
  --name your-acr-name \
  --query "{name:name,status:provisioningState,loginServer:loginServer}"
```

### Kubernetes Cluster Validation

```bash
# 1. Node readiness
kubectl get nodes

# 2. System components
kubectl get componentstatuses

# 3. Storage classes
kubectl get storageclass

# 4. Network policies (if enabled)
kubectl get networkpolicies --all-namespaces

# 5. Ingress resources
kubectl get ingress --all-namespaces
```

### Monitoring and Logging Verification

```bash
# 1. Check Log Analytics workspace
az monitor log-analytics workspace show \
  --resource-group aks-demo-rg \
  --workspace-name your-workspace-name

# 2. Verify Container Insights
kubectl get pods -n kube-system | grep oms

# 3. Test log collection
kubectl logs -n kube-system -l component=oms-agent --tail=10
```

## 🧪 Testing Your Deployment

### Deploy Sample Application

```bash
# 1. Create test namespace
kubectl create namespace test-app

# 2. Deploy nginx test app
kubectl create deployment nginx-test \
  --image=nginx:latest \
  --namespace=test-app

# 3. Expose the service
kubectl expose deployment nginx-test \
  --port=80 \
  --target-port=80 \
  --type=ClusterIP \
  --namespace=test-app

# 4. Test internal connectivity
kubectl run test-pod \
  --image=busybox \
  --rm -it \
  --namespace=test-app \
  -- wget -qO- nginx-test
```

### Test Application Gateway Ingress (if enabled)

```yaml
# ingress-test.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: test-app
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-test
            port:
              number: 80
```

```bash
# Apply ingress
kubectl apply -f ingress-test.yaml

# Check ingress status
kubectl get ingress -n test-app

# Get Application Gateway IP
az network public-ip show \
  --resource-group aks-demo-rg \
  --name your-app-gateway-ip \
  --query ipAddress
```

## 🚨 Common Deployment Issues

### Issue 1: Insufficient Quota

**Symptom**: Deployment fails with quota exceeded error

**Solution**:
```bash
# Check current quota
az vm list-usage --location "Australia Southeast" --output table

# Request quota increase if needed
# (Use Azure Portal > Subscriptions > Usage + quotas)
```

### Issue 2: Network Security Group Rules

**Symptom**: Pods can't communicate or reach external services

**Solution**:
```bash
# Check NSG rules
az network nsg list --resource-group aks-demo-rg --output table

# Review NSG rules
az network nsg rule list \
  --resource-group aks-demo-rg \
  --nsg-name AKS-NSG \
  --output table
```

### Issue 3: RBAC Issues

**Symptom**: Permission denied errors when accessing cluster

**Solution**:
```bash
# Re-authenticate with Azure
az login

# Get fresh credentials
az aks get-credentials \
  --resource-group aks-demo-rg \
  --name your-aks-cluster \
  --overwrite-existing \
  --admin  # Use admin credentials if needed
```

### Issue 4: Application Gateway Ingress Controller

**Symptom**: Ingress not working with AGIC

**Solution**:
```bash
# Check AGIC pod status
kubectl get pods -n kube-system | grep agic

# Check AGIC logs
kubectl logs -n kube-system -l app=ingress-appgw

# Verify AGIC configuration
kubectl get configmap -n kube-system agic-config -o yaml
```

## 📊 Cost Optimization

### Development Environment Optimizations

```bash
# 1. Use spot instances for user nodes (after initial deployment)
az aks nodepool add \
  --resource-group aks-demo-rg \
  --cluster-name your-aks-cluster \
  --name spot \
  --node-count 1 \
  --node-vm-size Standard_B2s \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1

# 2. Enable cluster autoscaler
az aks nodepool update \
  --resource-group aks-demo-rg \
  --cluster-name your-aks-cluster \
  --name user \
  --enable-cluster-autoscaler \
  --min-count 0 \
  --max-count 3

# 3. Stop cluster when not in use
az aks stop \
  --resource-group aks-demo-rg \
  --name your-aks-cluster

# 4. Start cluster when needed
az aks start \
  --resource-group aks-demo-rg \
  --name your-aks-cluster
```

### Monitoring Costs

```bash
# Set up cost alerts
az consumption budget create \
  --subscription your-subscription-id \
  --budget-name "AKS-Monthly-Budget" \
  --amount 200 \
  --time-grain Monthly \
  --time-period start-date="2024-01-01T00:00:00Z" \
  --resource-group aks-demo-rg
```

## 🔄 Updating and Maintenance

### Cluster Updates

```bash
# Check available updates
az aks get-upgrades \
  --resource-group aks-demo-rg \
  --name your-aks-cluster

# Upgrade cluster
az aks upgrade \
  --resource-group aks-demo-rg \
  --name your-aks-cluster \
  --kubernetes-version 1.29.0
```

### Infrastructure Updates

```bash
# Update Bicep templates and redeploy
az deployment group create \
  --resource-group aks-demo-rg \
  --template-file main.bicep \
  --parameters bicep/parameters/dev.bicepparam \
  --mode Incremental
```

## 🧹 Cleanup

When you're done with the infrastructure:

```bash
# Safe cleanup with confirmations
./scripts/cleanup.sh \
  --resource-group aks-demo-rg \
  --subscription your-subscription-id

# Force cleanup (careful!)
./scripts/cleanup.sh \
  --resource-group aks-demo-rg \
  --subscription your-subscription-id \
  --force
```

## 📚 Next Steps

After successful deployment:

1. **Deploy applications** to test the infrastructure
2. **Configure monitoring** dashboards in Azure Portal
3. **Set up CI/CD pipelines** for your applications
4. **Implement backup strategies** for persistent data
5. **Configure security policies** and compliance scanning
6. **Optimize costs** based on actual usage patterns

---

**Congratulations!** You now have a production-ready AKS infrastructure deployed with enterprise-grade security, monitoring, and scalability features.