#!/bin/bash

# Spoke Infrastructure Deployment Script
# This script deploys the spoke infrastructure including VM, storage, and private endpoints

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

# Check if required files exist
if [ ! -f "terraform.tfvars" ]; then
    print_error "terraform.tfvars file not found!"
    print_status "Please copy terraform.tfvars.example to terraform.tfvars and configure your values."
    exit 1
fi

# Check if Azure CLI is installed and user is logged in
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    print_error "You are not logged in to Azure. Please run 'az login' first."
    exit 1
fi

print_status "Starting spoke infrastructure deployment..."

# Initialize Terraform
print_status "Initializing Terraform..."
terraform init

# Validate Terraform configuration
print_status "Validating Terraform configuration..."
terraform validate

if [ $? -ne 0 ]; then
    print_error "Terraform validation failed!"
    exit 1
fi

# Plan the deployment
print_status "Creating Terraform plan..."
terraform plan -out=spoke.tfplan

if [ $? -ne 0 ]; then
    print_error "Terraform planning failed!"
    exit 1
fi

# Ask for confirmation before applying
echo
print_warning "About to deploy the spoke infrastructure. This will create resources in Azure."
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled."
    exit 0
fi

# Apply the configuration
print_status "Applying Terraform configuration..."
terraform apply spoke.tfplan

if [ $? -eq 0 ]; then
    print_success "Spoke infrastructure deployed successfully!"
    
    # Clean up plan file
    rm -f spoke.tfplan
    
    echo
    print_status "Spoke deployment completed. Key outputs:"
    terraform output
    
    echo
    print_status "Next steps:"
    echo "1. Update the hub terraform.tfvars with the spoke VNet ID from the outputs above"
    echo "2. Set enable_spoke_peering=true and enable_spoke_dns_link=true in hub terraform.tfvars"
    echo "3. Re-run the hub deployment script to establish cross-subscription peering"
    echo "4. Test VM access to storage using the helper scripts"
    
    # Display SSH connection info
    echo
    VM_PUBLIC_IP=$(terraform output -raw vm_public_ip 2>/dev/null || echo "")
    VM_PRIVATE_IP=$(terraform output -raw vm_private_ip 2>/dev/null || echo "")
    ADMIN_USERNAME=$(grep 'admin_username' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "azureuser")
    
    if [ ! -z "$VM_PUBLIC_IP" ] && [ "$VM_PUBLIC_IP" != "null" ]; then
        print_status "SSH connection command:"
        echo "ssh $ADMIN_USERNAME@$VM_PUBLIC_IP"
    elif [ ! -z "$VM_PRIVATE_IP" ]; then
        print_status "VM Private IP (requires VPN or bastion):"
        echo "$VM_PRIVATE_IP"
    fi
    
else
    print_error "Spoke infrastructure deployment failed!"
    rm -f spoke.tfplan
    exit 1
fi