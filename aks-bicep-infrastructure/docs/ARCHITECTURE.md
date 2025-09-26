# AKS Infrastructure Architecture

This document provides a detailed overview of the architecture, design decisions, and best practices implemented in this AKS infrastructure project.

## 🏗️ Architecture Overview

### High-Level Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Region                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                Resource Group                           │   │
│  │                                                         │   │
│  │  ┌──────────────────────────────────────────────────┐  │   │
│  │  │               Virtual Network                     │  │   │
│  │  │               (10.0.0.0/16)                      │  │   │
│  │  │                                                  │  │   │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ │  │   │
│  │  │  │App Gateway  │ │AKS Subnet   │ │Monitoring   │ │  │   │
│  │  │  │Subnet       │ │             │ │Subnet       │ │  │   │
│  │  │  │10.0.2.0/24  │ │10.0.1.0/24  │ │10.0.3.0/24  │ │  │   │
│  │  │  │             │ │             │ │             │ │  │   │
│  │  │  │┌───────────┐│ │┌───────────┐│ │┌───────────┐│ │  │   │
│  │  │  ││    WAF    ││ ││System Pool││ ││Log Analytics││ │  │   │
│  │  │  ││App Gateway││ ││User Pool  ││ ││Prometheus ││ │  │   │
│  │  │  │└───────────┘│ │└───────────┘│ │└───────────┘│ │  │   │
│  │  │  └─────────────┘ └─────────────┘ └─────────────┘ │  │   │
│  │  └──────────────────────────────────────────────────┘  │   │
│  │                                                         │   │
│  │  ┌──────────────────────────────────────────────────┐  │   │
│  │  │           Azure Container Registry                │  │   │
│  │  └──────────────────────────────────────────────────┘  │   │
│  │                                                         │   │
│  │  ┌──────────────────────────────────────────────────┐  │   │
│  │  │            Managed Identity                      │  │   │
│  │  └──────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## 🔧 Component Architecture

### 1. Network Layer

#### Virtual Network Design
- **Address Space**: `10.0.0.0/16` (65,536 IP addresses)
- **Subnet Segmentation**: Security-first approach with dedicated subnets
- **Network Security Groups**: Restrictive rules with explicit allow policies

```
VNet: 10.0.0.0/16
├── AKS Subnet: 10.0.1.0/24 (254 IPs)
│   ├── System Node Pool
│   ├── User Node Pool
│   └── Pod Network (CNI)
├── App Gateway Subnet: 10.0.2.0/24 (254 IPs)
│   └── Application Gateway + WAF
├── Monitoring Subnet: 10.0.3.0/24 (254 IPs)
│   ├── Log Analytics
│   └── Monitoring Tools
└── Management Subnet: 10.0.4.0/24 (254 IPs)
    └── Bastion/Jump Servers
```

#### Network Security Groups (NSGs)

**AKS Subnet NSG Rules:**
```
Priority | Direction | Action | Protocol | Source      | Destination | Ports
100      | Inbound   | Allow  | *        | 10.0.1.0/24 | 10.0.1.0/24 | *
110      | Inbound   | Allow  | TCP      | 10.0.2.0/24 | 10.0.1.0/24 | 80,443,8080
120      | Inbound   | Allow  | TCP      | 10.0.3.0/24 | 10.0.1.0/24 | 9090,3000,8080
4000     | Inbound   | Deny   | *        | *           | *           | *
```

**Application Gateway Subnet NSG Rules:**
```
Priority | Direction | Action | Protocol | Source        | Destination | Ports
100      | Inbound   | Allow  | TCP      | Internet      | *           | 80
110      | Inbound   | Allow  | TCP      | Internet      | *           | 443
120      | Inbound   | Allow  | TCP      | GatewayManager| *           | 65200-65535
```

### 2. Compute Layer

#### AKS Cluster Configuration

**System Node Pool:**
- **Purpose**: Kubernetes system components only
- **Taints**: `CriticalAddonsOnly=true:NoSchedule`
- **VM Size**: Configurable (B2s for dev, D2s_v3 for prod)
- **Auto-scaling**: Enabled (min: 1, max: configurable)

**User Node Pool:**
- **Purpose**: Application workloads
- **VM Size**: Configurable (B2s for dev, D2s_v3 for prod)
- **Auto-scaling**: Enabled with higher max limits
- **Spot Instances**: Optional for cost optimization

#### Node Pool Specifications

| Environment | System Pool | User Pool | Monthly Cost |
|-------------|-------------|-----------|--------------|
| Development | 1x B2s      | 1x B2s    | ~$60        |
| Staging     | 2x B2s      | 2x B2s    | ~$120       |
| Production  | 3x D2s_v3   | 3x D2s_v3 | ~$400       |

### 3. Container Registry

#### Azure Container Registry (ACR)
- **SKU**: Basic (dev) / Standard (staging) / Premium (prod)
- **Features**:
  - Image vulnerability scanning (Premium)
  - Geo-replication (Premium)
  - Private endpoints (Premium)
  - Webhook integration
  - Image signing and trust policies

### 4. Ingress and Load Balancing

#### Application Gateway with WAF
- **SKU**: WAF_v2 (Web Application Firewall v2)
- **Auto-scaling**: 1-3 capacity units (configurable)
- **Features**:
  - OWASP 3.2 rule set
  - Bot protection
  - Geographic blocking
  - SSL termination
  - Path-based routing

#### AGIC (Application Gateway Ingress Controller)
- **Integration**: Native AKS addon
- **Configuration**: Automatic based on Kubernetes Ingress resources
- **Benefits**:
  - No additional load balancer costs
  - WAF protection for all ingress traffic
  - Azure-native SSL certificate management

### 5. Monitoring and Observability

#### Azure Monitor Integration
- **Container Insights**: Cluster and node monitoring
- **Log Analytics**: Centralized logging
- **Application Insights**: Application performance monitoring
- **Azure Monitor Alerts**: Proactive alerting

#### Custom Monitoring Stack
```
Prometheus (Metrics Collection)
    ↓
Grafana (Visualization)
    ↓
AlertManager (Alert Routing)
    ↓
Azure Monitor (Alert Actions)
```

#### Monitoring Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring Stack                        │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │  Prometheus  │    │   Grafana    │    │ AlertManager │ │
│  │   (Metrics)  │───▶│ (Dashboard)  │───▶│  (Alerts)    │ │
│  └──────────────┘    └──────────────┘    └──────────────┘ │
│          │                    │                    │       │
│          ▼                    ▼                    ▼       │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              Azure Monitor                           │ │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────┐ │ │
│  │  │Log Analytics│  │App Insights│  │Monitor Alerts  │ │ │
│  │  └────────────┘  └────────────┘  └────────────────┘ │ │
│  └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 🔐 Security Architecture

### 1. Identity and Access Management

#### Managed Identity Design
```
AKS Cluster Managed Identity
├── Azure Container Registry (AcrPull)
├── Virtual Network (Network Contributor)
├── Application Gateway (Contributor)
└── Key Vault (Secrets Reader)
```

#### RBAC Configuration
- **Azure AD Integration**: Enabled for cluster access
- **Azure RBAC**: Enabled for Kubernetes API authorization
- **Workload Identity**: Enabled for pod-to-Azure authentication

### 2. Network Security

#### Defense in Depth
```
Internet → WAF → App Gateway → NSG → AKS → Network Policy → Pod
```

#### Security Layers
1. **WAF Protection**: OWASP rules, bot protection, geo-blocking
2. **Network Security Groups**: Subnet-level firewall rules
3. **Kubernetes Network Policies**: Pod-to-pod communication control
4. **Private Endpoints**: Secure Azure service access
5. **Azure Policy**: Compliance and governance enforcement

### 3. Container Security

#### Security Scanning Pipeline
```
Developer Push → ACR → Vulnerability Scan → Policy Gate → Deployment
```

#### Security Features
- **Image vulnerability scanning** with Twistlock/Aqua integration
- **Pod Security Standards** enforcement
- **Secret management** with Azure Key Vault
- **Network isolation** with Calico/Azure CNI
- **Runtime security** with Azure Defender

## 📊 Scalability Architecture

### 1. Horizontal Scaling

#### Cluster Autoscaler
```yaml
Configuration:
  System Pool: 1-5 nodes (conservative)
  User Pool: 1-10 nodes (aggressive)
  Scale-up delay: 10 seconds
  Scale-down delay: 10 minutes
  Scale-down utilization: 50%
```

#### Pod Autoscaling
- **Horizontal Pod Autoscaler (HPA)**: CPU/Memory based
- **Vertical Pod Autoscaler (VPA)**: Resource right-sizing
- **KEDA**: Event-driven autoscaling

### 2. Application Scaling Patterns

#### Microservices Scaling
```
Frontend (Web)
├── Auto-scale: 2-10 replicas
├── Resources: 100m CPU, 128Mi memory
└── Scaling metric: HTTP requests/sec

API Gateway
├── Auto-scale: 2-8 replicas
├── Resources: 200m CPU, 256Mi memory
└── Scaling metric: Active connections

Backend Services
├── Auto-scale: 1-5 replicas per service
├── Resources: Variable based on service
└── Scaling metric: Queue depth + CPU
```

## 💾 Data Architecture

### 1. Storage Classes

#### Available Storage Options
```yaml
Storage Classes:
  - default (Azure Disk - StandardSSD)
  - managed-premium (Azure Disk - Premium)
  - azurefile (Azure Files - Standard)
  - azurefile-premium (Azure Files - Premium)
  - azureblob (Azure Blob - Hot tier)
```

### 2. Persistent Volume Management
- **Dynamic provisioning** with CSI drivers
- **Backup integration** with Velero
- **Snapshot policies** for data protection
- **Encryption at rest** with Azure Key Vault

## 🔄 CI/CD Integration Architecture

### 1. GitOps Workflow
```
Git Repository → GitHub Actions → ACR → ArgoCD → AKS
```

### 2. Pipeline Stages
1. **Source Control**: Git-based infrastructure and application code
2. **Build**: Container image building and scanning
3. **Test**: Automated testing and validation
4. **Security**: Vulnerability scanning and policy checks
5. **Deploy**: GitOps-based deployment to clusters
6. **Monitor**: Continuous monitoring and alerting

## 🌐 Multi-Environment Strategy

### Environment Isolation
```
Production Subscription
├── Production Resource Group
│   ├── AKS Cluster (prod)
│   ├── ACR (prod)
│   └── Monitoring (prod)
│
Staging Subscription
├── Staging Resource Group
│   ├── AKS Cluster (staging)
│   ├── ACR (staging)
│   └── Monitoring (staging)
│
Development Subscription
├── Development Resource Group
│   ├── AKS Cluster (dev)
│   ├── ACR (dev)
│   └── Monitoring (dev)
```

### Configuration Management
- **Environment-specific parameters** in Bicep parameter files
- **Namespace isolation** within clusters
- **RBAC boundaries** between environments
- **Network isolation** with separate VNets or subnets

## 📈 Performance Architecture

### 1. Resource Optimization

#### Node Pool Optimization
```
System Pool:
  - Dedicated for system workloads
  - Tainted to prevent user workload scheduling
  - Optimized for cluster management overhead

User Pool:
  - Sized for application workloads
  - Auto-scaling enabled
  - Multiple instance types for cost optimization
```

#### Network Performance
- **Azure CNI**: Native Azure networking for performance
- **Accelerated Networking**: SR-IOV for high throughput
- **Proximity Placement Groups**: Reduced latency for tightly coupled workloads

### 2. Monitoring and Alerting

#### Key Performance Indicators (KPIs)
```yaml
Cluster Health:
  - Node availability: >99%
  - Pod restart rate: <5%
  - Resource utilization: 60-80%

Application Performance:
  - Response time: <500ms p95
  - Error rate: <1%
  - Throughput: Variable by application

Infrastructure Metrics:
  - Network latency: <10ms intra-region
  - Storage IOPS: Based on workload requirements
  - CPU/Memory utilization: 60-80% target
```

## 🔧 Operational Excellence

### 1. Disaster Recovery

#### Backup Strategy
- **Cluster state backup** with Velero
- **Persistent volume snapshots**
- **Configuration backup** in Git repositories
- **Cross-region replication** for critical data

#### Recovery Procedures
1. **RTO (Recovery Time Objective)**: 4 hours
2. **RPO (Recovery Point Objective)**: 1 hour
3. **Automated failover** for stateless applications
4. **Manual intervention** for stateful workloads

### 2. Maintenance Windows

#### Update Strategy
- **Rolling updates** for applications
- **Blue-green deployment** for critical services
- **Canary releases** for new features
- **Scheduled maintenance** windows for infrastructure

---

This architecture provides a solid foundation for enterprise-grade Kubernetes workloads with security, scalability, and operational excellence built-in from day one.