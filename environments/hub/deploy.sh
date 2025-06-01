#!/bin/bash

# Hub Infrastructure Deployment Script
# This script deploys the hub infrastructure including networking, DNS, and policies

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

print_status "Starting hub infrastructure deployment..."

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
terraform plan -out=hub.tfplan

if [ $? -ne 0 ]; then
    print_error "Terraform planning failed!"
    exit 1
fi

# Ask for confirmation before applying
echo
print_warning "About to deploy the hub infrastructure. This will create resources in Azure."
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled."
    exit 0
fi

# Apply the configuration
print_status "Applying Terraform configuration..."
terraform apply hub.tfplan

if [ $? -eq 0 ]; then
    print_success "Hub infrastructure deployed successfully!"
    
    # Clean up plan file
    rm -f hub.tfplan
    
    echo
    print_status "Hub deployment completed. Key outputs:"
    terraform output
    
    echo
    print_status "Next steps:"
    echo "1. Note down the hub VNet ID and private DNS zone ID from the outputs above"
    echo "2. Update the spoke terraform.tfvars with these values"
    echo "3. Deploy the spoke infrastructure using the spoke deployment script"
    echo "4. After spoke deployment, update hub terraform.tfvars to enable peering"
    echo "5. Re-run this script to establish cross-subscription peering"
    
else
    print_error "Hub infrastructure deployment failed!"
    rm -f hub.tfplan
    exit 1
fi