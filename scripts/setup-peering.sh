#!/bin/bash

# Cross-Subscription VNet Peering Setup Script
# This script establishes VNet peering between hub and spoke across subscriptions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default values
HUB_DIR="../environments/hub"
SPOKE_DIR="../environments/spoke-1"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --hub-dir DIR     Path to hub terraform directory (default: $HUB_DIR)"
    echo "  -s, --spoke-dir DIR   Path to spoke terraform directory (default: $SPOKE_DIR)"
    echo "  --help               Show this help message"
    echo ""
    echo "This script:"
    echo "1. Gets spoke VNet ID from spoke Terraform outputs"
    echo "2. Updates hub terraform.tfvars with spoke information"
    echo "3. Re-applies hub configuration to establish peering"
    echo "4. Links spoke VNet to hub private DNS zone"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--hub-dir)
            HUB_DIR="$2"
            shift 2
            ;;
        -s|--spoke-dir)
            SPOKE_DIR="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if directories exist
if [ ! -d "$HUB_DIR" ]; then
    print_error "Hub directory not found: $HUB_DIR"
    exit 1
fi

if [ ! -d "$SPOKE_DIR" ]; then
    print_error "Spoke directory not found: $SPOKE_DIR"
    exit 1
fi

# Check if spoke is deployed
if [ ! -f "$SPOKE_DIR/terraform.tfstate" ]; then
    print_error "Spoke Terraform state not found. Please deploy the spoke first."
    exit 1
fi

print_status "Setting up cross-subscription VNet peering..."

# Get spoke VNet ID
cd "$SPOKE_DIR"
SPOKE_VNET_ID=$(terraform output -raw spoke_vnet_id 2>/dev/null)
SPOKE_SUBSCRIPTION_ID=$(terraform output -json | jq -r '.spoke_vnet_id.value' | cut -d'/' -f3)

if [ -z "$SPOKE_VNET_ID" ] || [ "$SPOKE_VNET_ID" = "null" ]; then
    print_error "Could not retrieve spoke VNet ID from Terraform outputs"
    exit 1
fi

print_status "Retrieved spoke VNet ID: $SPOKE_VNET_ID"

# Switch to hub directory
cd "$HUB_DIR"

# Check if hub terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    print_error "Hub terraform.tfvars not found!"
    print_status "Please ensure the hub is properly configured."
    exit 1
fi

# Create backup of current terraform.tfvars
cp terraform.tfvars terraform.tfvars.backup.$(date +%Y%m%d_%H%M%S)
print_status "Created backup of terraform.tfvars"

# Update terraform.tfvars with spoke information
print_status "Updating hub terraform.tfvars with spoke information..."

# Function to update or add a variable in terraform.tfvars
update_tfvars() {
    local var_name="$1"
    local var_value="$2"
    local file="terraform.tfvars"
    
    if grep -q "^${var_name}[[:space:]]*=" "$file"; then
        # Variable exists, update it
        sed -i.tmp "s|^${var_name}[[:space:]]*=.*|${var_name} = ${var_value}|" "$file"
        rm -f "${file}.tmp"
    else
        # Variable doesn't exist, add it
        echo "${var_name} = ${var_value}" >> "$file"
    fi
}

# Update the necessary variables
update_tfvars "spoke_vnet_id" "\"$SPOKE_VNET_ID\""
update_tfvars "enable_spoke_peering" "true"
update_tfvars "enable_spoke_dns_link" "true"

if [ ! -z "$SPOKE_SUBSCRIPTION_ID" ]; then
    update_tfvars "spoke_subscription_id" "\"$SPOKE_SUBSCRIPTION_ID\""
fi

print_status "Updated terraform.tfvars with peering configuration"

# Plan and apply the changes
print_status "Planning hub configuration changes..."
terraform plan -out=peering.tfplan

if [ $? -ne 0 ]; then
    print_error "Terraform planning failed!"
    print_status "Restoring backup terraform.tfvars..."
    mv terraform.tfvars.backup.* terraform.tfvars
    exit 1
fi

# Ask for confirmation
echo
print_warning "About to establish cross-subscription VNet peering and DNS linking."
print_status "This will:"
echo "  - Create VNet peering from hub to spoke"
echo "  - Link spoke VNet to hub private DNS zone"
echo "  - Enable cross-subscription network connectivity"
echo
read -p "Do you want to continue? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Peering setup cancelled."
    rm -f peering.tfplan
    exit 0
fi

# Apply the changes
print_status "Applying peering configuration..."
terraform apply peering.tfplan

if [ $? -eq 0 ]; then
    print_success "Cross-subscription VNet peering established successfully!"
    
    # Clean up
    rm -f peering.tfplan
    
    echo
    print_status "Peering setup completed. Outputs:"
    terraform output
    
    echo
    print_success "Network connectivity established between hub and spoke!"
    print_status "You can now:"
    echo "  ✓ Access spoke resources from hub network"
    echo "  ✓ Resolve Azure service private endpoints from spoke"
    echo "  ✓ Use centralized DNS resolution for privatelink zones"
    
    echo
    print_status "Test the connectivity using:"
    echo "  cd ../../scripts && ./test-storage-access.sh"
    
else
    print_error "Peering setup failed!"
    print_status "Restoring backup terraform.tfvars..."
    mv terraform.tfvars.backup.* terraform.tfvars
    rm -f peering.tfplan
    exit 1
fi