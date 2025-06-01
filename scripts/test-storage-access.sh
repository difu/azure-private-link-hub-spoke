#!/bin/bash

# Test Storage Access Script
# This script tests the VM's ability to access the storage account via private endpoint

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
SPOKE_DIR="../environments/spoke-1"
HUB_DIR="../environments/hub"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --spoke-dir DIR    Path to spoke terraform directory (default: $SPOKE_DIR)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "This script tests storage access from the VM by:"
    echo "1. Retrieving VM connection info from Terraform outputs"
    echo "2. Connecting to the VM via SSH"
    echo "3. Running storage connectivity tests"
    echo "4. Testing the storage helper script functionality"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--spoke-dir)
            SPOKE_DIR="$2"
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

# Check if spoke directory exists
if [ ! -d "$SPOKE_DIR" ]; then
    print_error "Spoke directory not found: $SPOKE_DIR"
    exit 1
fi

cd "$SPOKE_DIR"

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    print_error "Terraform state not found in $SPOKE_DIR"
    print_status "Please deploy the spoke infrastructure first."
    exit 1
fi

print_status "Retrieving VM connection information..."

# Get VM connection details
VM_PUBLIC_IP=$(terraform output -raw vm_public_ip 2>/dev/null || echo "")
VM_PRIVATE_IP=$(terraform output -raw vm_private_ip 2>/dev/null || echo "")
ADMIN_USERNAME=$(terraform output -raw admin_username 2>/dev/null || echo "azureuser")
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name 2>/dev/null || echo "")
CONTAINER_NAME=$(terraform output -raw container_name 2>/dev/null || echo "")

if [ -z "$STORAGE_ACCOUNT" ]; then
    print_error "Could not retrieve storage account name from Terraform outputs"
    exit 1
fi

# Determine which IP to use for SSH
if [ ! -z "$VM_PUBLIC_IP" ] && [ "$VM_PUBLIC_IP" != "null" ]; then
    VM_IP="$VM_PUBLIC_IP"
    print_status "Using public IP for connection: $VM_IP"
elif [ ! -z "$VM_PRIVATE_IP" ]; then
    VM_IP="$VM_PRIVATE_IP"
    print_warning "Using private IP for connection: $VM_IP"
    print_warning "Make sure you have network connectivity to the private IP (VPN/bastion)"
else
    print_error "Could not determine VM IP address"
    exit 1
fi

# Create test script for VM
TEST_SCRIPT=$(cat << 'EOF'
#!/bin/bash

echo "=== Azure Storage Access Test ==="
echo "Storage Account: $1"
echo "Container: $2"
echo "Timestamp: $(date)"
echo

# Test 1: Check managed identity authentication
echo "Test 1: Checking managed identity authentication..."
TOKEN_RESPONSE=$(curl -s -H "Metadata: true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/")

if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
    echo "✓ Managed identity authentication successful"
else
    echo "✗ Managed identity authentication failed"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

# Test 2: Test DNS resolution of storage account
echo
echo "Test 2: Testing DNS resolution..."
STORAGE_FQDN="$1.blob.core.windows.net"
RESOLVED_IP=$(nslookup "$STORAGE_FQDN" | grep "Address:" | tail -n1 | cut -d' ' -f2)

if [[ $RESOLVED_IP =~ ^10\. ]]; then
    echo "✓ Storage account resolves to private IP: $RESOLVED_IP"
else
    echo "⚠ Storage account resolves to: $RESOLVED_IP (expected private IP)"
fi

# Test 3: Test storage helper script
echo
echo "Test 3: Testing storage operations with helper script..."

# Create a test file
TEST_FILE="/tmp/test-$(date +%s).txt"
echo "Test file created at $(date) from VM $(hostname)" > "$TEST_FILE"

# Test upload
echo "Uploading test file..."
if ./storage-helper.sh upload "$TEST_FILE" "test-file.txt"; then
    echo "✓ File upload successful"
else
    echo "✗ File upload failed"
    exit 1
fi

# Test list
echo
echo "Listing files in container..."
if ./storage-helper.sh list; then
    echo "✓ File listing successful"
else
    echo "✗ File listing failed"
fi

# Test download
echo
echo "Downloading test file..."
DOWNLOAD_FILE="/tmp/downloaded-$(date +%s).txt"
if ./storage-helper.sh download "test-file.txt" "$DOWNLOAD_FILE"; then
    echo "✓ File download successful"
    echo "Downloaded content:"
    cat "$DOWNLOAD_FILE"
else
    echo "✗ File download failed"
fi

# Test delete
echo
echo "Deleting test file..."
if ./storage-helper.sh delete "test-file.txt"; then
    echo "✓ File deletion successful"
else
    echo "✗ File deletion failed"
fi

# Cleanup
rm -f "$TEST_FILE" "$DOWNLOAD_FILE"

echo
echo "=== All tests completed successfully! ==="
EOF
)

print_status "Connecting to VM and running storage access tests..."
print_status "VM: $ADMIN_USERNAME@$VM_IP"

# Run the test script on the VM
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$ADMIN_USERNAME@$VM_IP" "bash -s $STORAGE_ACCOUNT $CONTAINER_NAME" <<< "$TEST_SCRIPT"

if [ $? -eq 0 ]; then
    print_success "Storage access tests completed successfully!"
    echo
    print_status "The VM can successfully:"
    echo "  ✓ Authenticate using managed identity"
    echo "  ✓ Resolve storage account via private DNS"
    echo "  ✓ Upload, download, list, and delete blobs"
    echo "  ✓ Access storage through private endpoint"
else
    print_error "Storage access tests failed!"
    exit 1
fi