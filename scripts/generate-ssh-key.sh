#!/bin/bash

# SSH Key Generation Script
# This script generates an SSH key pair for VM access

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
KEY_NAME="hub-spoke-vm"
KEY_DIR="$HOME/.ssh"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -n, --name NAME       SSH key name (default: $KEY_NAME)"
    echo "  -d, --dir DIR         Directory to store keys (default: $KEY_DIR)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "This script generates an SSH key pair for VM access in the hub-spoke infrastructure."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            KEY_NAME="$2"
            shift 2
            ;;
        -d|--dir)
            KEY_DIR="$2"
            shift 2
            ;;
        -h|--help)
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

# Create directory if it doesn't exist
mkdir -p "$KEY_DIR"

PRIVATE_KEY="$KEY_DIR/$KEY_NAME"
PUBLIC_KEY="$KEY_DIR/$KEY_NAME.pub"

# Check if key already exists
if [ -f "$PRIVATE_KEY" ] || [ -f "$PUBLIC_KEY" ]; then
    print_warning "SSH key files already exist:"
    [ -f "$PRIVATE_KEY" ] && echo "  Private key: $PRIVATE_KEY"
    [ -f "$PUBLIC_KEY" ] && echo "  Public key: $PUBLIC_KEY"
    echo
    read -p "Do you want to overwrite the existing keys? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Key generation cancelled."
        exit 0
    fi
fi

print_status "Generating SSH key pair..."
print_status "Key name: $KEY_NAME"
print_status "Directory: $KEY_DIR"

# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f "$PRIVATE_KEY" -N "" -C "hub-spoke-vm-$(date +%Y%m%d)"

if [ $? -eq 0 ]; then
    print_success "SSH key pair generated successfully!"
    
    echo
    print_status "Files created:"
    echo "  Private key: $PRIVATE_KEY"
    echo "  Public key:  $PUBLIC_KEY"
    
    # Set proper permissions
    chmod 600 "$PRIVATE_KEY"
    chmod 644 "$PUBLIC_KEY"
    
    echo
    print_status "Public key content (copy this to terraform.tfvars):"
    echo "----------------------------------------"
    cat "$PUBLIC_KEY"
    echo "----------------------------------------"
    
    echo
    print_status "To use this key with Terraform:"
    echo "1. Copy the public key content above"
    echo "2. Update terraform.tfvars in your spoke environment:"
    echo "   admin_ssh_public_key = \"$(cat "$PUBLIC_KEY")\""
    echo "3. Deploy or update your infrastructure"
    
    echo
    print_status "To connect to your VM after deployment:"
    echo "ssh -i $PRIVATE_KEY azureuser@<vm-ip-address>"
    
else
    print_error "SSH key generation failed!"
    exit 1
fi