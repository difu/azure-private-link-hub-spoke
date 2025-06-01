# Storage Operations Guide

This guide explains how to work with Azure Blob Storage from the VM using managed identity authentication and private endpoints.

## Overview

The VM in the spoke subscription has:
- **System-assigned managed identity** with `Storage Blob Data Contributor` role
- **Private network access** to storage via private endpoint
- **Helper scripts** for common storage operations
- **Azure CLI** pre-installed and configured

## Storage Helper Script

The VM includes a custom storage helper script at `/home/azureuser/storage-helper.sh` that simplifies blob operations.

### Basic Usage

```bash
# Show help
./storage-helper.sh

# Upload a file
./storage-helper.sh upload <local_file> <blob_name>

# Download a file
./storage-helper.sh download <blob_name> <local_file>

# List all blobs
./storage-helper.sh list

# Delete a blob
./storage-helper.sh delete <blob_name>
```

### Examples

```bash
# Create a test file
echo "Hello from VM $(hostname)" > /tmp/hello.txt

# Upload the file to blob storage
./storage-helper.sh upload /tmp/hello.txt hello.txt

# List all files in the container
./storage-helper.sh list

# Download the file to a new location
./storage-helper.sh download hello.txt /tmp/downloaded.txt

# Verify the content
cat /tmp/downloaded.txt

# Delete the blob
./storage-helper.sh delete hello.txt
```

## Azure CLI Operations

The VM has Azure CLI installed and can authenticate using the managed identity.

### Authentication

```bash
# Login using managed identity
az login --identity

# Verify the login
az account show
```

### Blob Operations

```bash
# Set variables (replace with your actual values)
STORAGE_ACCOUNT="stspoke1xxxxxxxx"
CONTAINER_NAME="data"

# Upload a file
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name $CONTAINER_NAME \
    --name myfile.txt \
    --file /path/to/local/file.txt \
    --auth-mode login

# Download a file
az storage blob download \
    --account-name $STORAGE_ACCOUNT \
    --container-name $CONTAINER_NAME \
    --name myfile.txt \
    --file /path/to/download/file.txt \
    --auth-mode login

# List blobs
az storage blob list \
    --account-name $STORAGE_ACCOUNT \
    --container-name $CONTAINER_NAME \
    --auth-mode login \
    --output table

# Delete a blob
az storage blob delete \
    --account-name $STORAGE_ACCOUNT \
    --container-name $CONTAINER_NAME \
    --name myfile.txt \
    --auth-mode login

# Get blob properties
az storage blob show \
    --account-name $STORAGE_ACCOUNT \
    --container-name $CONTAINER_NAME \
    --name myfile.txt \
    --auth-mode login
```

### Container Operations

```bash
# List containers (requires Storage Blob Data Reader or higher)
az storage container list \
    --account-name $STORAGE_ACCOUNT \
    --auth-mode login

# Create a new container (requires Storage Blob Data Contributor)
az storage container create \
    --account-name $STORAGE_ACCOUNT \
    --name "newcontainer" \
    --auth-mode login

# Set container permissions
az storage container set-permission \
    --account-name $STORAGE_ACCOUNT \
    --name "newcontainer" \
    --public-access off \
    --auth-mode login
```

## REST API Operations

For advanced scenarios, you can use the REST API directly with managed identity tokens.

### Get Access Token

```bash
# Get access token for Azure Storage
TOKEN=$(curl -s -H "Metadata: true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" \
    | jq -r '.access_token')

echo "Access token obtained: ${TOKEN:0:20}..."
```

### REST API Examples

```bash
STORAGE_ACCOUNT="stspoke1xxxxxxxx"
CONTAINER_NAME="data"
BLOB_NAME="test.txt"

# Upload a blob
curl -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-ms-blob-type: BlockBlob" \
    -H "Content-Type: text/plain" \
    --data "Hello from REST API" \
    "https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER_NAME/$BLOB_NAME"

# Download a blob
curl -H "Authorization: Bearer $TOKEN" \
    "https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER_NAME/$BLOB_NAME"

# List blobs in container
curl -H "Authorization: Bearer $TOKEN" \
    "https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER_NAME?restype=container&comp=list"

# Delete a blob
curl -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    "https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER_NAME/$BLOB_NAME"
```

## Programming Language Examples

### Python

```python
#!/usr/bin/env python3
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
import os

# Use default credential (managed identity)
credential = DefaultAzureCredential()

# Initialize the BlobServiceClient
storage_account = "stspoke1xxxxxxxx"
blob_service_client = BlobServiceClient(
    account_url=f"https://{storage_account}.blob.core.windows.net",
    credential=credential
)

# Upload a file
def upload_blob(container_name, blob_name, data):
    blob_client = blob_service_client.get_blob_client(
        container=container_name, 
        blob=blob_name
    )
    blob_client.upload_blob(data, overwrite=True)
    print(f"Uploaded {blob_name}")

# Download a file
def download_blob(container_name, blob_name):
    blob_client = blob_service_client.get_blob_client(
        container=container_name, 
        blob=blob_name
    )
    return blob_client.download_blob().readall()

# List blobs
def list_blobs(container_name):
    container_client = blob_service_client.get_container_client(container_name)
    return [blob.name for blob in container_client.list_blobs()]

# Example usage
if __name__ == "__main__":
    container_name = "data"
    
    # Upload
    upload_blob(container_name, "python-test.txt", "Hello from Python!")
    
    # List
    blobs = list_blobs(container_name)
    print(f"Blobs: {blobs}")
    
    # Download
    content = download_blob(container_name, "python-test.txt")
    print(f"Downloaded: {content.decode()}")
```


## Monitoring and Troubleshooting

### Check Connectivity

```bash
# Test DNS resolution
nslookup stspoke1xxxxxxxx.blob.core.windows.net

# Expected output should show private IP (10.1.2.x)
# If you see public IP, DNS resolution is not working correctly

# Test network connectivity
telnet stspoke1xxxxxxxx.blob.core.windows.net 443
```

### Verify Managed Identity

```bash
# Check if managed identity is working
curl -H "Metadata: true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/"

# Should return a JSON response with access_token
```

### Check Role Assignments

```bash
# Login with managed identity
az login --identity

# Check current user/identity
az account show

# List role assignments (if you have permissions)
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

### Common Issues and Solutions

#### Issue: DNS Resolution to Public IP
```bash
# Check private DNS zone configuration
az network private-dns zone list --resource-group rg-hub-network

# Check VNet links
az network private-dns link vnet list \
    --zone-name privatelink.blob.core.windows.net \
    --resource-group rg-hub-network
```

#### Issue: Access Denied
```bash
# Verify role assignment exists
az role assignment list \
    --scope "/subscriptions/.../resourceGroups/rg-spoke-1/providers/Microsoft.Storage/storageAccounts/stspoke1xxxxxxxx"

# Check if managed identity is enabled
az vm identity show --resource-group rg-spoke-1 --name vm-spoke-1
```

#### Issue: Network Connectivity
```bash
# Check VNet peering status
az network vnet peering list \
    --resource-group rg-spoke-1 \
    --vnet-name vnet-spoke-1

# Check private endpoint status
az network private-endpoint list \
    --resource-group rg-spoke-1
```

## Best Practices

### Security
- Always use managed identity instead of storage keys
- Regularly rotate access keys (even though not used)
- Monitor access patterns and unusual activity
- Use least-privilege access (Reader vs Contributor)

### Performance
- Use appropriate blob access tiers (Hot, Cool, Archive)
- Consider using Azure CDN for frequently accessed content
- Implement retry logic in applications
- Use async operations for large transfers

### Cost Optimization
- Monitor storage usage and clean up unused blobs
- Use lifecycle management policies
- Consider compression for text/log files
- Review access patterns and optimize tiers

### Operational
- Implement proper logging and monitoring
- Use infrastructure as code for consistency
- Document blob naming conventions
- Implement backup strategies for critical data