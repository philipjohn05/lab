#!/bin/bash

# =============================================================================
# AKS Infrastructure Deployment Script
# =============================================================================
# This script deploys the complete AKS infrastructure using Azure Bicep.
# It includes proper error handling, logging, and validation steps.

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/deployment.log"

# Default values
ENVIRONMENT="dev"
RESOURCE_GROUP=""
LOCATION="australiasoutheast"
SUBSCRIPTION_ID=""
DRY_RUN=false
VERBOSE=false

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Success logging
success() {
    log "SUCCESS" "$1"
}

# Info logging
info() {
    log "INFO" "$1"
}

# Verbose logging
verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "VERBOSE" "$1"
    fi
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_help() {
    cat << EOF
AKS Infrastructure Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -e, --environment ENV       Environment to deploy (dev/staging/prod) [default: dev]
    -g, --resource-group RG     Azure resource group name [REQUIRED]
    -l, --location LOCATION     Azure region [default: australiasoutheast]
    -s, --subscription ID       Azure subscription ID [REQUIRED]
    -d, --dry-run              Validate deployment without executing
    -v, --verbose              Enable verbose logging
    -h, --help                 Show this help message

EXAMPLES:
    # Deploy development environment
    $0 -e dev -g my-aks-rg -s 12345678-1234-1234-1234-123456789012

    # Dry run for production
    $0 -e prod -g my-prod-rg -s 12345678-1234-1234-1234-123456789012 --dry-run

    # Verbose deployment
    $0 -e dev -g my-aks-rg -s 12345678-1234-1234-1234-123456789012 -v

PREREQUISITES:
    - Azure CLI installed and authenticated
    - Bicep CLI installed
    - Contributor access to Azure subscription
    - Resource group must exist before deployment

EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use -h or --help for usage information."
                ;;
        esac
    done
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_environment() {
    info "Validating environment: $ENVIRONMENT"

    case $ENVIRONMENT in
        dev|staging|prod)
            success "Environment '$ENVIRONMENT' is valid"
            ;;
        *)
            error_exit "Invalid environment: $ENVIRONMENT. Must be dev, staging, or prod."
            ;;
    esac
}

validate_prerequisites() {
    info "Validating prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    verbose "Azure CLI found"

    # Check if Bicep CLI is installed
    if ! command -v bicep &> /dev/null; then
        if ! az bicep version &> /dev/null; then
            error_exit "Bicep CLI is not installed. Please install it first."
        fi
    fi
    verbose "Bicep CLI found"

    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    verbose "Azure authentication verified"

    success "All prerequisites validated"
}

validate_parameters() {
    info "Validating deployment parameters..."

    # Check required parameters
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error_exit "Resource group name is required. Use -g or --resource-group."
    fi

    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error_exit "Subscription ID is required. Use -s or --subscription."
    fi

    # Validate parameter file exists
    local param_file="$PROJECT_ROOT/bicep/parameters/${ENVIRONMENT}.bicepparam"
    if [[ ! -f "$param_file" ]]; then
        error_exit "Parameter file not found: $param_file"
    fi
    verbose "Parameter file found: $param_file"

    success "All parameters validated"
}

validate_azure_resources() {
    info "Validating Azure resources..."

    # Set subscription
    az account set --subscription "$SUBSCRIPTION_ID" || error_exit "Failed to set subscription"
    verbose "Subscription set to: $SUBSCRIPTION_ID"

    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error_exit "Resource group '$RESOURCE_GROUP' does not exist. Please create it first."
    fi
    verbose "Resource group verified: $RESOURCE_GROUP"

    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        error_exit "Invalid location: $LOCATION"
    fi
    verbose "Location verified: $LOCATION"

    success "Azure resources validated"
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

compile_bicep() {
    info "Compiling Bicep templates..."

    local main_bicep="$PROJECT_ROOT/main.bicep"
    local compiled_arm="$PROJECT_ROOT/main.json"

    # Compile main template
    az bicep build --file "$main_bicep" --outfile "$compiled_arm" || error_exit "Failed to compile Bicep template"
    verbose "Compiled: $main_bicep -> $compiled_arm"

    success "Bicep templates compiled successfully"
}

validate_deployment() {
    info "Validating deployment template..."

    local main_bicep="$PROJECT_ROOT/main.bicep"
    local param_file="$PROJECT_ROOT/bicep/parameters/${ENVIRONMENT}.bicepparam"

    # Validate deployment
    az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$main_bicep" \
        --parameters "$param_file" \
        --output table || error_exit "Deployment validation failed"

    success "Deployment template validated successfully"
}

deploy_infrastructure() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Skipping actual deployment"
        return 0
    fi

    info "Starting infrastructure deployment..."

    local main_bicep="$PROJECT_ROOT/main.bicep"
    local param_file="$PROJECT_ROOT/bicep/parameters/${ENVIRONMENT}.bicepparam"
    local deployment_name="aks-infrastructure-$(date +%Y%m%d-%H%M%S)"

    # Deploy infrastructure
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$main_bicep" \
        --parameters "$param_file" \
        --name "$deployment_name" \
        --output table || error_exit "Deployment failed"

    success "Infrastructure deployed successfully"

    # Get deployment outputs
    info "Retrieving deployment outputs..."
    az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$deployment_name" \
        --query "properties.outputs" \
        --output table
}

configure_kubectl() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Skipping kubectl configuration"
        return 0
    fi

    info "Configuring kubectl for AKS cluster..."

    # Get AKS cluster name from deployment
    local cluster_name=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv)

    if [[ -n "$cluster_name" ]]; then
        az aks get-credentials \
            --resource-group "$RESOURCE_GROUP" \
            --name "$cluster_name" \
            --overwrite-existing || error_exit "Failed to configure kubectl"

        # Test connection
        kubectl get nodes || error_exit "Failed to connect to AKS cluster"
        success "kubectl configured successfully"
    else
        error_exit "Could not find AKS cluster in resource group"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    info "Starting AKS infrastructure deployment"
    info "Script: $0"
    info "Arguments: $*"

    # Initialize log file
    echo "=== AKS Infrastructure Deployment Log ===" > "$LOG_FILE"
    echo "Start Time: $(date)" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"

    # Parse command line arguments
    parse_arguments "$@"

    # Display configuration
    info "Deployment Configuration:"
    info "  Environment: $ENVIRONMENT"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Subscription: $SUBSCRIPTION_ID"
    info "  Dry Run: $DRY_RUN"
    info "  Verbose: $VERBOSE"

    # Run validation steps
    validate_environment
    validate_prerequisites
    validate_parameters
    validate_azure_resources

    # Compile and validate
    compile_bicep
    validate_deployment

    # Deploy infrastructure
    deploy_infrastructure

    # Configure kubectl
    configure_kubectl

    success "Deployment completed successfully!"
    info "Log file: $LOG_FILE"

    if [[ "$DRY_RUN" == "false" ]]; then
        info "Next steps:"
        info "1. Verify cluster status: kubectl get nodes"
        info "2. Deploy sample applications to test the infrastructure"
        info "3. Check monitoring dashboards in Azure Portal"
    fi
}

# Execute main function with all arguments
main "$@"