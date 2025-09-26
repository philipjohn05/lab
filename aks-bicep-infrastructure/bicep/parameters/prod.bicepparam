// =============================================================================
// Production Environment Parameters
// =============================================================================
// This parameter file contains configuration for the production environment.
// Optimized for high availability, security, and performance.

using '../main.bicep'

// =============================================================================
// BASIC CONFIGURATION
// =============================================================================

param namePrefix = 'devops-prod'
param environment = 'prod'
param location = 'Australia Southeast'

// =============================================================================
// AKS CONFIGURATION
// =============================================================================

param kubernetesVersion = '1.30.6'

// Production-grade VM sizes for performance and reliability
param systemNodeVmSize = 'Standard_D2s_v3'  // 2 vCPU, 8GB RAM
param userNodeVmSize = 'Standard_D2s_v3'    // 2 vCPU, 8GB RAM

// Higher node counts for availability and load distribution
param systemNodeCount = 3  // High availability for system workloads
param userNodeCount = 3    // Load distribution and availability

// =============================================================================
// FEATURE FLAGS
// =============================================================================

// Enable all monitoring for production observability
param enableMonitoring = true

// Enable AGIC for production ingress with WAF protection
param enableAGIC = true