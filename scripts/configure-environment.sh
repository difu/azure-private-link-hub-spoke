#!/bin/bash

# Azure Hub-Spoke Environment Configuration Script
# Sets up environment variables for Terraform deployments
# Creates .env files for each environment directory
# Compatible with both bash and zsh environments

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
    error "Usage: $0 <environment_name>"
    error "Example: $0 dev"
    error "         $0 prod"
    exit 1
fi

ENVIRONMENT_NAME="$1"

# Credentials file
CREDENTIALS_FILE="./service-principal-credentials-${ENVIRONMENT_NAME}.json"

log "Configuring environment: ${ENVIRONMENT_NAME}"

# Check if credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
    error "Credentials file not found: ${CREDENTIALS_FILE}"
    error "Please run setup-service-principals.sh first"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed. Please install jq first."
    error "On macOS: brew install jq"
    error "On Ubuntu: sudo apt-get install jq"
    exit 1
fi

# Load credentials from JSON file
log "Loading service principal credentials..."

HUB_SUBSCRIPTION_ID=$(jq -r '.hub.subscription_id' "$CREDENTIALS_FILE")
HUB_TENANT_ID=$(jq -r '.hub.tenant_id' "$CREDENTIALS_FILE")
HUB_CLIENT_ID=$(jq -r '.hub.client_id' "$CREDENTIALS_FILE")
HUB_CLIENT_SECRET=$(jq -r '.hub.client_secret' "$CREDENTIALS_FILE")

SPOKE_SUBSCRIPTION_ID=$(jq -r '.spoke.subscription_id' "$CREDENTIALS_FILE")
SPOKE_TENANT_ID=$(jq -r '.spoke.tenant_id' "$CREDENTIALS_FILE")
SPOKE_CLIENT_ID=$(jq -r '.spoke.client_id' "$CREDENTIALS_FILE")
SPOKE_CLIENT_SECRET=$(jq -r '.spoke.client_secret' "$CREDENTIALS_FILE")

# Validate loaded data
if [ "$HUB_SUBSCRIPTION_ID" = "null" ] || [ "$SPOKE_SUBSCRIPTION_ID" = "null" ]; then
    error "Invalid credentials file format"
    exit 1
fi

log "Credentials loaded successfully"
log "Hub Subscription: ${HUB_SUBSCRIPTION_ID}"
log "Spoke Subscription: ${SPOKE_SUBSCRIPTION_ID}"

# Function to create environment file
create_env_file() {
    local env_file="$1"
    local subscription_id="$2"
    local tenant_id="$3"
    local client_id="$4"
    local client_secret="$5"
    local description="$6"
    
    log "Creating ${description} environment file: ${env_file}"
    
    # Create directory if it doesn't exist
    local env_dir
    env_dir=$(dirname "$env_file")
    if [ ! -d "$env_dir" ]; then
        mkdir -p "$env_dir"
    fi
    
    # Create .env file
    cat > "$env_file" << EOF
# Azure Authentication for ${description} (Environment: ${ENVIRONMENT_NAME})
# Generated on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# DO NOT COMMIT TO VERSION CONTROL

# Azure Service Principal Configuration
ARM_SUBSCRIPTION_ID="${subscription_id}"
ARM_TENANT_ID="${tenant_id}"
ARM_CLIENT_ID="${client_id}"
ARM_CLIENT_SECRET="${client_secret}"

# Additional Azure CLI Configuration
AZURE_SUBSCRIPTION_ID="${subscription_id}"
AZURE_TENANT_ID="${tenant_id}"
AZURE_CLIENT_ID="${client_id}"
AZURE_CLIENT_SECRET="${client_secret}"

# Environment Metadata
ENVIRONMENT_NAME="${ENVIRONMENT_NAME}"
EOF

    chmod 600 "$env_file"
    success "Created: ${env_file}"
}

# Create environment files for each directory
create_env_file "environments/hub/.env.${ENVIRONMENT_NAME}" "$HUB_SUBSCRIPTION_ID" "$HUB_TENANT_ID" "$HUB_CLIENT_ID" "$HUB_CLIENT_SECRET" "hub"
create_env_file "environments/spoke-1/.env.${ENVIRONMENT_NAME}" "$SPOKE_SUBSCRIPTION_ID" "$SPOKE_TENANT_ID" "$SPOKE_CLIENT_ID" "$SPOKE_CLIENT_SECRET" "spoke"

# Create root-level environment file for convenience
create_env_file ".env.${ENVIRONMENT_NAME}" "$HUB_SUBSCRIPTION_ID" "$HUB_TENANT_ID" "$HUB_CLIENT_ID" "$HUB_CLIENT_SECRET" "root (hub credentials)"

# Create helper script for easy environment loading
ACTIVATE_SCRIPT="./activate-${ENVIRONMENT_NAME}.sh"
log "Creating environment activation script: ${ACTIVATE_SCRIPT}"

cat > "$ACTIVATE_SCRIPT" << 'EOF'
#!/bin/bash

# Environment Activation Script for {{ENVIRONMENT_NAME}}
# Source this script to load environment variables
# Compatible with both bash and zsh

# Check if running in a shell that supports sourcing
# Compatible with both bash and zsh
if [ -n "${BASH_SOURCE:-}" ]; then
    # In bash
    if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
        echo "❌ This script should be sourced, not executed directly"
        echo "Usage: source {{ACTIVATE_SCRIPT_NAME}}"
        echo "   or: . {{ACTIVATE_SCRIPT_NAME}}"
        exit 1
    fi
elif [ -n "${ZSH_VERSION:-}" ]; then
    # In zsh
    if [ "${(%):-%x}" == "${0}" ]; then
        echo "❌ This script should be sourced, not executed directly"
        echo "Usage: source {{ACTIVATE_SCRIPT_NAME}}"
        echo "   or: . {{ACTIVATE_SCRIPT_NAME}}"
        return 1
    fi
fi

# Load environment variables
if [ -f ".env.{{ENVIRONMENT_NAME}}" ]; then
    # Use a method compatible with both bash and zsh
    set -a  # automatically export all variables
    . ".env.{{ENVIRONMENT_NAME}}"
    set +a  # turn off automatic export
    
    echo "✅ Environment '{{ENVIRONMENT_NAME}}' activated"
    echo "🏢 Hub Subscription: ${ARM_SUBSCRIPTION_ID}"
    echo "🌐 Active Tenant: ${ARM_TENANT_ID}"
    
    # Verify Azure CLI authentication
    if az account show --subscription "${ARM_SUBSCRIPTION_ID}" >/dev/null 2>&1; then
        echo "✅ Azure CLI authentication verified"
    else
        echo "⚠️  Azure CLI not authenticated or subscription access issue"
        echo "   You may need to run: az login --service-principal -u ${ARM_CLIENT_ID} -p ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID}"
    fi
else
    echo "❌ Environment file not found: .env.{{ENVIRONMENT_NAME}}"
    echo "   Run: ./configure-environment.sh {{ENVIRONMENT_NAME}}"
fi
EOF

# Replace placeholders in the generated script
# Use portable sed syntax that works on both macOS and Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/{{ENVIRONMENT_NAME}}/${ENVIRONMENT_NAME}/g" "$ACTIVATE_SCRIPT"
    sed -i '' "s/{{ACTIVATE_SCRIPT_NAME}}/$(basename "$ACTIVATE_SCRIPT")/g" "$ACTIVATE_SCRIPT"
else
    # Linux
    sed -i "s/{{ENVIRONMENT_NAME}}/${ENVIRONMENT_NAME}/g" "$ACTIVATE_SCRIPT"
    sed -i "s/{{ACTIVATE_SCRIPT_NAME}}/$(basename "$ACTIVATE_SCRIPT")/g" "$ACTIVATE_SCRIPT"
fi

chmod +x "$ACTIVATE_SCRIPT"
success "Created: ${ACTIVATE_SCRIPT}"

# Update .gitignore to exclude sensitive files
GITIGNORE_FILE=".gitignore"
log "Updating .gitignore to exclude sensitive files..."

# Create .gitignore if it doesn't exist
if [ ! -f "$GITIGNORE_FILE" ]; then
    touch "$GITIGNORE_FILE"
fi

# Add entries to .gitignore if they don't already exist
GITIGNORE_ENTRIES=(
    "# Service Principal Credentials"
    "service-principal-credentials-*.json"
    ".env.*"
    "activate-*.sh"
    "*.tfvars.backup"
    "# Terraform"
    "*.tfstate"
    "*.tfstate.*"
    ".terraform/"
    ".terraform.lock.hcl"
    "terraform.tfplan"
    "plan.tfplan"
)

for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if ! grep -Fxq "$entry" "$GITIGNORE_FILE"; then
        echo "$entry" >> "$GITIGNORE_FILE"
    fi
done

success "Updated .gitignore"

# Create usage instructions
USAGE_FILE="USAGE-${ENVIRONMENT_NAME}.md"
log "Creating usage instructions: ${USAGE_FILE}"

cat > "$USAGE_FILE" << EOF
# Azure Hub-Spoke Infrastructure Usage Guide

Environment: **${ENVIRONMENT_NAME}**
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Quick Start

### 1. Activate Environment
\`\`\`bash
# Load environment variables
source ./activate-${ENVIRONMENT_NAME}.sh

# Or manually load for specific directory
cd environments/hub
source .env.${ENVIRONMENT_NAME}
\`\`\`

### 2. Deploy Hub Infrastructure
\`\`\`bash
cd environments/hub
terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
\`\`\`

### 3. Deploy Spoke Infrastructure
\`\`\`bash
cd environments/spoke-1
terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
\`\`\`

### 4. Setup VNet Peering
\`\`\`bash
cd scripts
./setup-peering.sh
\`\`\`

## Environment Details

### Hub Subscription
- **Subscription ID**: \`${HUB_SUBSCRIPTION_ID}\`
- **Service Principal**: \`$(jq -r '.hub.service_principal_name' "$CREDENTIALS_FILE")\`
- **Environment File**: \`environments/hub/.env.${ENVIRONMENT_NAME}\`

### Spoke Subscription  
- **Subscription ID**: \`${SPOKE_SUBSCRIPTION_ID}\`
- **Service Principal**: \`$(jq -r '.spoke.service_principal_name' "$CREDENTIALS_FILE")\`
- **Environment File**: \`environments/spoke-1/.env.${ENVIRONMENT_NAME}\`

## Environment Files

Each environment directory contains a \`.env.${ENVIRONMENT_NAME}\` file with:
- \`ARM_SUBSCRIPTION_ID\` - Azure subscription ID
- \`ARM_TENANT_ID\` - Azure tenant ID
- \`ARM_CLIENT_ID\` - Service principal application ID
- \`ARM_CLIENT_SECRET\` - Service principal secret

## Authentication Methods

### Option 1: Environment Variables (Recommended)
\`\`\`bash
# Load environment variables
source ./activate-${ENVIRONMENT_NAME}.sh

# Run terraform commands
terraform plan
\`\`\`

### Option 2: Azure CLI Service Principal Login
\`\`\`bash
# Hub subscription
az login --service-principal \\
  -u ${HUB_CLIENT_ID} \\
  -p "${HUB_CLIENT_SECRET}" \\
  --tenant ${HUB_TENANT_ID}

# Spoke subscription  
az login --service-principal \\
  -u ${SPOKE_CLIENT_ID} \\
  -p "${SPOKE_CLIENT_SECRET}" \\
  --tenant ${SPOKE_TENANT_ID}
\`\`\`

## Cleanup

When you're done with this environment:

\`\`\`bash
# Destroy infrastructure (spoke first, then hub)
cd environments/spoke-1 && terraform destroy
cd environments/hub && terraform destroy

# Remove service principals and configuration
./cleanup-service-principals.sh ${ENVIRONMENT_NAME}
\`\`\`

## Security Notes

- ⚠️ Never commit \`.env.*\` files to version control
- 🔒 Environment files have 600 permissions (owner read/write only)
- 🔄 Service principal secrets can be rotated using Azure CLI
- 🗑️ Use cleanup script when environment is no longer needed

## Troubleshooting

### Permission Issues
If you encounter permission errors, verify:
1. Service principals have required roles on subscriptions
2. Current user has Owner/User Access Administrator rights
3. Azure CLI is authenticated to correct tenant

### Cross-Subscription Access
The hub service principal has Network Contributor access to the spoke subscription for VNet peering.
The spoke service principal has Network Contributor access to the hub subscription for VNet peering.

### Environment Variables Not Loading
Ensure you're sourcing the activation script:
\`\`\`bash
# Correct
source ./activate-${ENVIRONMENT_NAME}.sh

# Incorrect (runs in subshell)
./activate-${ENVIRONMENT_NAME}.sh
\`\`\`
EOF

success "Created: ${USAGE_FILE}"

success "Environment configuration completed!"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration Summary:"
echo ""
echo "📁 Environment Files Created:"
echo "   ├── environments/hub/.env.${ENVIRONMENT_NAME}"
echo "   ├── environments/spoke-1/.env.${ENVIRONMENT_NAME}"
echo "   └── .env.${ENVIRONMENT_NAME}"
echo ""
echo "🚀 Activation Script:"
echo "   └── activate-${ENVIRONMENT_NAME}.sh"
echo ""
echo "📖 Usage Guide:"
echo "   └── USAGE-${ENVIRONMENT_NAME}.md"
echo ""
echo "Next Steps:"
echo "1. Activate environment: source ./activate-${ENVIRONMENT_NAME}.sh"
echo "2. Deploy hub: cd environments/hub && terraform init && terraform apply"
echo "3. Deploy spoke: cd environments/spoke-1 && terraform init && terraform apply"
echo "4. Read full guide: cat USAGE-${ENVIRONMENT_NAME}.md"
echo ""
echo "🔐 Security: All environment files have 600 permissions and are excluded from git"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"