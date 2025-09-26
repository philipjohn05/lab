#!/bin/bash

# =============================================================================
# AKS Infrastructure Cleanup Script
# =============================================================================
# This script safely removes the AKS infrastructure to avoid ongoing costs.
# Includes safeguards and confirmation prompts for production environments.

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default values
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
FORCE=false
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

    echo "[$timestamp] [$level] $message"
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

# Warning logging
warn() {
    log "WARNING" "$1"
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_help() {
    cat << EOF
AKS Infrastructure Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -g, --resource-group RG     Azure resource group name [REQUIRED]
    -s, --subscription ID       Azure subscription ID [REQUIRED]
    -f, --force                Skip confirmation prompts (dangerous!)
    -v, --verbose              Enable verbose logging
    -h, --help                 Show this help message

EXAMPLES:
    # Safe cleanup with confirmations
    $0 -g my-aks-rg -s 12345678-1234-1234-1234-123456789012

    # Force cleanup (no prompts)
    $0 -g my-aks-rg -s 12345678-1234-1234-1234-123456789012 --force

WARNING:
    This script will permanently delete Azure resources.
    Make sure you have backups of any important data.

EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
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

validate_parameters() {
    info "Validating parameters..."

    if [[ -z "$RESOURCE_GROUP" ]]; then
        error_exit "Resource group name is required. Use -g or --resource-group."
    fi

    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error_exit "Subscription ID is required. Use -s or --subscription."
    fi

    success "Parameters validated"
}

validate_azure_access() {
    info "Validating Azure access..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed."
    fi

    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi

    # Set subscription
    az account set --subscription "$SUBSCRIPTION_ID" || error_exit "Failed to set subscription"

    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error_exit "Resource group '$RESOURCE_GROUP' does not exist."
    fi

    success "Azure access validated"
}

# =============================================================================
# SAFETY FUNCTIONS
# =============================================================================

confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        warn "Force mode enabled - skipping confirmations"
        return 0
    fi

    warn "You are about to DELETE the following resource group and ALL its contents:"
    warn "  Resource Group: $RESOURCE_GROUP"
    warn "  Subscription: $SUBSCRIPTION_ID"
    echo

    # Show resources that will be deleted
    info "Resources that will be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --output table || true
    echo

    warn "This action is IRREVERSIBLE!"
    echo

    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi

    # Double confirmation for production-like names
    if [[ $RESOURCE_GROUP =~ (prod|production|live) ]]; then
        warn "PRODUCTION ENVIRONMENT DETECTED!"
        warn "Resource group name contains production keywords: $RESOURCE_GROUP"
        echo
        read -p "This appears to be a production environment. Type 'DELETE PRODUCTION' to confirm: " -r
        if [[ ! $REPLY == "DELETE PRODUCTION" ]]; then
            info "Cleanup cancelled - production safety check failed"
            exit 0
        fi
    fi

    success "User confirmed deletion"
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

stop_aks_cluster() {
    info "Stopping AKS cluster to minimize costs during cleanup..."

    # Find AKS cluster in the resource group
    local cluster_name
    cluster_name=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")

    if [[ -n "$cluster_name" ]]; then
        info "Found AKS cluster: $cluster_name"
        info "Stopping cluster to save costs during cleanup..."

        az aks stop --resource-group "$RESOURCE_GROUP" --name "$cluster_name" || {
            warn "Failed to stop AKS cluster (this is non-critical)"
        }
        success "AKS cluster stopped"
    else
        info "No AKS cluster found in resource group"
    fi
}

cleanup_deployments() {
    info "Cleaning up deployment history..."

    # Delete deployment history to avoid issues
    local deployments
    deployments=$(az deployment group list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")

    if [[ -n "$deployments" ]]; then
        info "Found deployment history, cleaning up..."
        while IFS= read -r deployment; do
            if [[ -n "$deployment" ]]; then
                az deployment group delete --resource-group "$RESOURCE_GROUP" --name "$deployment" --no-wait || {
                    warn "Failed to delete deployment: $deployment"
                }
            fi
        done <<< "$deployments"
        success "Deployment history cleanup initiated"
    else
        info "No deployment history found"
    fi
}

delete_resource_group() {
    info "Deleting resource group: $RESOURCE_GROUP"

    # Start the deletion
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait || error_exit "Failed to initiate resource group deletion"

    success "Resource group deletion initiated"
    info "Deletion is running in the background"
    info "You can monitor progress in the Azure Portal or with:"
    info "  az group show --name $RESOURCE_GROUP"
}

monitor_deletion() {
    info "Monitoring deletion progress..."

    local max_wait=1800  # 30 minutes
    local wait_time=0
    local check_interval=30

    while [[ $wait_time -lt $max_wait ]]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            success "Resource group deleted successfully!"
            return 0
        fi

        info "Still deleting... (waited ${wait_time}s)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done

    warn "Deletion is taking longer than expected"
    info "Please check the Azure Portal for status"
}

# =============================================================================
# COST ESTIMATION
# =============================================================================

show_cost_savings() {
    info "Estimated cost savings after cleanup:"
    echo
    echo "  Daily savings (dev environment):   ~$7-10"
    echo "  Daily savings (prod environment):  ~$15-25"
    echo "  Monthly savings (dev):             ~$200-300"
    echo "  Monthly savings (prod):            ~$400-750"
    echo
    info "Costs will stop accruing once all resources are deleted"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    info "Starting AKS infrastructure cleanup"

    # Parse arguments
    parse_arguments "$@"

    # Display configuration
    info "Cleanup Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Subscription: $SUBSCRIPTION_ID"
    info "  Force Mode: $FORCE"

    # Validate everything
    validate_parameters
    validate_azure_access

    # Safety checks and confirmations
    confirm_deletion

    # Perform cleanup steps
    stop_aks_cluster
    cleanup_deployments
    delete_resource_group

    # Monitor deletion (optional)
    if [[ "$FORCE" == "false" ]]; then
        read -p "Monitor deletion progress? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            monitor_deletion
        fi
    fi

    # Show cost savings
    show_cost_savings

    success "Cleanup completed successfully!"
    info "Resources are being deleted in the background"
    info "Check Azure Portal to confirm all resources are removed"
}

# Execute main function with all arguments
main "$@"