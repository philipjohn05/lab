// =============================================================================
// Development Environment Parameters
// =============================================================================
// This parameter file contains configuration for the development environment.
// Optimized for cost savings and development workflows.

using '../main.bicep'

// =============================================================================
// BASIC CONFIGURATION
// =============================================================================

param namePrefix = 'devops-demo'
param environment = 'dev'
param location = 'Australia Southeast'

// =============================================================================
// AKS CONFIGURATION
// =============================================================================

param kubernetesVersion = '1.30.6'

// Development-optimized VM sizes for cost savings
param systemNodeVmSize = 'Standard_B2s'  // 2 vCPU, 4GB RAM - ~$30/month
param userNodeVmSize = 'Standard_B2s'    // 2 vCPU, 4GB RAM - ~$30/month

// Minimal node counts for development
param systemNodeCount = 1  // Minimum for system workloads
param userNodeCount = 1    // Minimal for cost savings

// =============================================================================
// FEATURE FLAGS
// =============================================================================

// Enable monitoring for learning purposes
param enableMonitoring = true

// Enable AGIC to showcase ingress capabilities
param enableAGIC = true