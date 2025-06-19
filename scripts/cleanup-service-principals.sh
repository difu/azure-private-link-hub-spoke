#!/bin/bash

# Azure Hub-Spoke Service Principal Cleanup Script
# Removes service principals and their role assignments
# Requires Owner permissions on both subscriptions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if required parameters are provided
if [ $# -lt 1 ]; then
    error "Usage: $0 <environment_name> [--force]"
    error "Example: $0 dev"
    error "         $0 prod --force"
    exit 1
fi

ENVIRONMENT_NAME="$1"
FORCE_DELETE="${2:-}"

# Service principal names
HUB_SP_NAME="sp-hub-terraform-${ENVIRONMENT_NAME}"
SPOKE_SP_NAME="sp-spoke-terraform-${ENVIRONMENT_NAME}"

# Credentials file
CREDENTIALS_FILE="./service-principal-credentials-${ENVIRONMENT_NAME}.json"

log "Starting service principal cleanup for environment: ${ENVIRONMENT_NAME}"

# Check if user is logged in to Azure CLI
if ! az account show >/dev/null 2>&1; then
    error "Please login to Azure CLI first: az login"
    exit 1
fi

# Check if credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
    warn "Credentials file not found: ${CREDENTIALS_FILE}"
    warn "Will attempt to find service principals by name"
else
    # Load subscription IDs from credentials file
    HUB_SUBSCRIPTION_ID=$(jq -r '.hub.subscription_id' "$CREDENTIALS_FILE" 2>/dev/null || echo "")
    SPOKE_SUBSCRIPTION_ID=$(jq -r '.spoke.subscription_id' "$CREDENTIALS_FILE" 2>/dev/null || echo "")
    
    if [ -n "$HUB_SUBSCRIPTION_ID" ] && [ -n "$SPOKE_SUBSCRIPTION_ID" ]; then
        log "Found subscription IDs from credentials file"
        log "Hub Subscription: ${HUB_SUBSCRIPTION_ID}"
        log "Spoke Subscription: ${SPOKE_SUBSCRIPTION_ID}"
    fi
fi

# Function to find service principal by name
find_service_principal() {
    local sp_name="$1"
    local app_id
    
    app_id=$(az ad sp list --display-name "${sp_name}" --query "[0].appId" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$app_id" ] && [ "$app_id" != "null" ]; then
        echo "$app_id"
    else
        echo ""
    fi
}

# Function to remove all role assignments for a service principal
remove_role_assignments() {
    local app_id="$1"
    local sp_name="$2"
    
    log "Removing role assignments for ${sp_name} (${app_id})"
    
    # Get all role assignments for this service principal
    local assignments
    assignments=$(az role assignment list --assignee "${app_id}" --query "[].{id:id,scope:scope,role:roleDefinitionName}" -o json 2>/dev/null || echo "[]")
    
    if [ "$assignments" = "[]" ]; then
        log "No role assignments found for ${sp_name}"
        return 0
    fi
    
    # Remove each role assignment
    local assignment_count
    assignment_count=$(echo "$assignments" | jq length)
    
    log "Found ${assignment_count} role assignment(s) for ${sp_name}"
    
    for ((i=0; i<assignment_count; i++)); do
        local assignment_id
        local scope
        local role
        
        assignment_id=$(echo "$assignments" | jq -r ".[$i].id")
        scope=$(echo "$assignments" | jq -r ".[$i].scope")
        role=$(echo "$assignments" | jq -r ".[$i].role")
        
        log "Removing role assignment: ${role} at scope ${scope}"
        
        if az role assignment delete --ids "$assignment_id" >/dev/null 2>&1; then
            success "Removed role assignment: ${role}"
        else
            error "Failed to remove role assignment: ${role} at scope ${scope}"
        fi
    done
}

# Function to delete service principal
delete_service_principal() {
    local app_id="$1"
    local sp_name="$2"
    
    log "Deleting service principal: ${sp_name} (${app_id})"
    
    if az ad sp delete --id "${app_id}" >/dev/null 2>&1; then
        success "Deleted service principal: ${sp_name}"
    else
        error "Failed to delete service principal: ${sp_name}"
        return 1
    fi
}

# Confirmation prompt
if [ "$FORCE_DELETE" != "--force" ]; then
    echo ""
    warn "This will permanently delete the following service principals and their role assignments:"
    echo "  - ${HUB_SP_NAME}"
    echo "  - ${SPOKE_SP_NAME}"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# Find service principals
log "Looking for service principals..."

HUB_SP_APP_ID=$(find_service_principal "$HUB_SP_NAME")
SPOKE_SP_APP_ID=$(find_service_principal "$SPOKE_SP_NAME")

if [ -z "$HUB_SP_APP_ID" ] && [ -z "$SPOKE_SP_APP_ID" ]; then
    warn "No service principals found for environment: ${ENVIRONMENT_NAME}"
    echo "Service principals may have already been deleted or were created with different names."
    exit 0
fi

# Clean up hub service principal
if [ -n "$HUB_SP_APP_ID" ]; then
    log "Found hub service principal: ${HUB_SP_NAME} (${HUB_SP_APP_ID})"
    remove_role_assignments "$HUB_SP_APP_ID" "$HUB_SP_NAME"
    delete_service_principal "$HUB_SP_APP_ID" "$HUB_SP_NAME"
else
    warn "Hub service principal not found: ${HUB_SP_NAME}"
fi

# Clean up spoke service principal
if [ -n "$SPOKE_SP_APP_ID" ]; then
    log "Found spoke service principal: ${SPOKE_SP_NAME} (${SPOKE_SP_APP_ID})"
    remove_role_assignments "$SPOKE_SP_APP_ID" "$SPOKE_SP_NAME"
    delete_service_principal "$SPOKE_SP_APP_ID" "$SPOKE_SP_NAME"
else
    warn "Spoke service principal not found: ${SPOKE_SP_NAME}"
fi

# Clean up credentials file
if [ -f "$CREDENTIALS_FILE" ]; then
    log "Removing credentials file: ${CREDENTIALS_FILE}"
    if rm "$CREDENTIALS_FILE"; then
        success "Credentials file removed"
    else
        warn "Failed to remove credentials file"
    fi
else
    log "Credentials file not found (may have been already removed)"
fi

# Clean up environment files
ENV_FILES=(
    "environments/hub/.env.${ENVIRONMENT_NAME}"
    "environments/spoke-1/.env.${ENVIRONMENT_NAME}"
    ".env.${ENVIRONMENT_NAME}"
)

log "Cleaning up environment configuration files..."
for env_file in "${ENV_FILES[@]}"; do
    if [ -f "$env_file" ]; then
        log "Removing environment file: ${env_file}"
        if rm "$env_file"; then
            success "Removed: ${env_file}"
        else
            warn "Failed to remove: ${env_file}"
        fi
    fi
done

success "Service principal cleanup completed for environment: ${ENVIRONMENT_NAME}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cleanup Summary:"
echo ""
if [ -n "$HUB_SP_APP_ID" ]; then
    echo "✅ Hub service principal removed: ${HUB_SP_NAME}"
else
    echo "ℹ️  Hub service principal not found (may have been already removed)"
fi

if [ -n "$SPOKE_SP_APP_ID" ]; then
    echo "✅ Spoke service principal removed: ${SPOKE_SP_NAME}"
else
    echo "ℹ️  Spoke service principal not found (may have been already removed)"
fi

echo "✅ Role assignments removed"
echo "✅ Configuration files cleaned up"
echo ""
echo "Environment '${ENVIRONMENT_NAME}' has been completely cleaned up."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"