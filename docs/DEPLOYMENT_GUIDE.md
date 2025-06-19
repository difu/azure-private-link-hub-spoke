# Hub-Spoke Infrastructure Deployment Guide

This guide provides step-by-step instructions for deploying the hub-and-spoke infrastructure across multiple Azure subscriptions.

## Subscription Structure

![Subscription Structure](images/subscriptions.png)

The architecture spans multiple subscriptions as shown above:
- **Work_Subscription_A**: Contains the hub infrastructure
- **Spoke_1**: Contains the first spoke with VM and storage
- Additional spokes can be added following the same pattern

## Prerequisites

### Required Tools
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (version 2.30+)
- [Terraform](https://www.terraform.io/downloads.html) (version 1.0+)
- SSH client
- jq (for JSON processing)

### Azure Requirements
- Two Azure subscriptions (hub and spoke)
- User account with `Owner` or `User Access Administrator` role in both subscriptions
- Permission to create service principals and policy assignments
- jq installed for JSON processing (`brew install jq` on macOS)

### Network Planning
- **Hub VNet**: `10.0.0.0/16`
  - Gateway Subnet: `10.0.1.0/24`
  - DNS Subnet: `10.0.2.0/24`
- **Spoke VNet**: `10.1.0.0/16`
  - VM Subnet: `10.1.1.0/24`
  - Storage Subnet: `10.1.2.0/24`

## Step 1: Initial Setup

### 1.1 Clone and Prepare Project
```bash
git clone <repository-url>
cd azure-private-link-hub-spoke

# Generate SSH key for VM access
./scripts/generate-ssh-key.sh
```

### 1.2 Configure Authentication

#### Option A: Automated Service Principal Setup (Recommended)
```bash
# Login with your user account (requires Owner permissions)
az login

# List available subscriptions
az account list --output table

# Create service principals with proper cross-subscription permissions
./scripts/setup-service-principals.sh <hub_subscription_id> <spoke_subscription_id> [environment_name]

# Example:
./scripts/setup-service-principals.sh \
  "12345678-1234-1234-1234-123456789012" \
  "87654321-4321-4321-4321-210987654321" \
  "prod"
```

This script automatically:
- Creates dedicated service principals for hub and spoke
- Assigns proper cross-subscription roles for VNet peering
- Configures DNS Zone Contributor permissions for policy automation
- Generates secure credentials file
- Validates all permissions

#### Option B: Manual Service Principal Setup
```bash
# Login to Azure
az login

# Create service principal with contributor access to both subscriptions
az ad sp create-for-rbac --name "hub-spoke-terraform" \
  --role "Contributor" \
  --scopes "/subscriptions/HUB_SUBSCRIPTION_ID" \
           "/subscriptions/SPOKE_SUBSCRIPTION_ID"

# Note down the output for later use
```

### 1.3 Configure Environment Variables
```bash
# After service principal creation, configure environment
./scripts/configure-environment.sh <environment_name>

# Activate the environment
source ./activate-<environment_name>.sh

# Verify authentication
az account show
```

This creates:
- **Environment files**: `.env.<environment_name>` in each directory
- **Activation script**: `activate-<environment_name>.sh` for easy environment loading
- **Usage guide**: `USAGE-<environment_name>.md` with complete instructions
- **Updated .gitignore**: Excludes all sensitive files from version control

### 1.4 Multiple Environment Support

You can create multiple isolated environments (dev, staging, prod):

```bash
# Development environment
./scripts/setup-service-principals.sh <hub_dev_sub> <spoke_dev_sub> "dev"
./scripts/configure-environment.sh "dev"

# Production environment  
./scripts/setup-service-principals.sh <hub_prod_sub> <spoke_prod_sub> "prod"
./scripts/configure-environment.sh "prod"

# Switch between environments
source ./activate-dev.sh     # For development
source ./activate-prod.sh    # For production
```

## Step 2: Deploy Hub Infrastructure

![Hub Infrastructure](images/Work_Subscription_A.png)

The hub infrastructure creates the core networking components shown above, including the Network Watcher, private DNS zone, virtual network, and network security group that form the foundation of the hub-and-spoke architecture.

### 2.1 Configure Hub Variables
```bash
cd environments/hub
cp terraform.tfvars.example terraform.tfvars

# Environment should already be activated from Step 1.3
# If not: source ../../activate-<environment_name>.sh
```

Edit `terraform.tfvars` with your values:
```hcl
# Subscription Configuration
hub_subscription_id = "your-hub-subscription-id"

# Spoke Subscription Configuration (for policies)
spoke_subscription_ids = {
  spoke-1 = "your-spoke-1-subscription-id"
}

# Network Configuration
location                        = "West Europe"
hub_resource_group_name        = "rg-hub-network"
hub_vnet_name                  = "vnet-hub"
hub_vnet_address_space         = ["10.0.0.0/16"]
gateway_subnet_address_prefix  = ["10.0.1.0/24"]
dns_subnet_address_prefix      = ["10.0.2.0/24"]

# DNS Configuration
enable_all_privatelink_zones = true  # Enterprise: all 25+ zones, Dev: false for blob only

# Initially disable peering (enable after spoke deployment)
enable_spoke_peering   = false
enable_spoke_dns_link  = false

# Policy Configuration
enable_tagging_policy = false  # Set to true to enforce resource tagging

# Tags
tags = {
  Environment = "production"
  Project     = "hub-spoke-infrastructure"
  ManagedBy   = "terraform"
  Owner       = "platform-team"
}
```

### 2.2 Deploy Hub
```bash
# Initialize and deploy hub infrastructure
./deploy.sh
```

### 2.3 Note Hub Outputs
Save the following outputs for spoke configuration:
- `hub_vnet_id`
- `private_dns_zone_id` (backward compatibility)
- `private_dns_zones` (all zones if comprehensive coverage enabled)
- `hub_resource_group_name`

```bash
# View all outputs
terraform output

# View specific DNS zones created
terraform output private_dns_zones
```

## Step 3: Deploy Spoke Infrastructure

![Spoke Infrastructure](images/Spoke_1.png)

The spoke infrastructure diagram above shows the complete resource topology, including the VM, network interfaces, public IP, VNet, network security group, private endpoint, and storage account that work together to provide secure, private access to storage services.

### 3.1 Configure Spoke Variables
```bash
cd ../spoke-1
cp terraform.tfvars.example terraform.tfvars

# Ensure spoke environment is activated
source .env.<environment_name>
```

Edit `terraform.tfvars` with your values:
```hcl
# Subscription Configuration
spoke_subscription_id   = "your-spoke-1-subscription-id"
hub_subscription_id     = "your-hub-subscription-id"

# Hub References (from hub outputs)
hub_resource_group_name = "rg-hub-network"
hub_vnet_name          = "vnet-hub"

# Network Configuration
location                 = "West Europe"
spoke_vnet_address_space = ["10.1.0.0/16"]
vm_subnet_address_prefix      = ["10.1.1.0/24"]
storage_subnet_address_prefix = ["10.1.2.0/24"]

# Security
admin_source_address_prefix = "YOUR_PUBLIC_IP/32"  # Replace with your IP

# VM Configuration
vm_name               = "vm-spoke-1"
admin_username        = "azureuser"
admin_ssh_public_key  = "ssh-rsa AAAAB3..."  # From generate-ssh-key.sh output
enable_public_ip      = true

# Storage
storage_account_prefix = "stspoke1"
container_name        = "data"
```

### 3.2 Deploy Spoke
```bash
# Deploy spoke infrastructure
./deploy.sh
```

### 3.3 Note Spoke Outputs
Save the `spoke_vnet_id` for hub peering configuration.

## Step 4: Establish Cross-Subscription Peering

### 4.1 Automated Peering Setup
```bash
# Run automated peering setup script
cd ../../scripts
./setup-peering.sh
```

### 4.2 Manual Peering Setup (Alternative)
If the automated script fails, configure manually:

```bash
cd ../environments/hub

# Update terraform.tfvars
spoke_vnet_id = "/subscriptions/SPOKE_SUB_ID/resourceGroups/rg-spoke-1/providers/Microsoft.Network/virtualNetworks/vnet-spoke-1"
enable_spoke_peering = true
enable_spoke_dns_link = true

# Re-apply hub configuration
terraform plan
terraform apply
```

## Step 5: Verify Deployment

### 5.1 Test Storage Connectivity
```bash
cd scripts
./test-storage-access.sh
```

This script will:
- Connect to the VM via SSH
- Test managed identity authentication
- Verify private DNS resolution
- Test blob storage operations

### 5.2 Manual Verification
Connect to the VM and test manually:
```bash
# Get VM IP from spoke outputs
ssh azureuser@<vm-public-ip>

# Test storage helper script
./storage-helper.sh upload /tmp/test.txt test.txt
./storage-helper.sh list
./storage-helper.sh download test.txt /tmp/downloaded.txt
./storage-helper.sh delete test.txt

# Test DNS resolution
nslookup stspoke1xxxxx.blob.core.windows.net
# Should resolve to private IP (10.1.2.x)

# Test Azure CLI with managed identity
az login --identity
az storage blob list --account-name stspoke1xxxxx --container-name data --auth-mode login
```

## Step 6: Policy Verification

### 6.1 Test Policy Enforcement
Try creating a privatelink DNS zone in the spoke subscription:
```bash
# Switch to spoke subscription
az account set --subscription "your-spoke-1-subscription-id"

# This should be denied by policy
az network private-dns zone create \
  --resource-group rg-spoke-1 \
  --name privatelink.database.windows.net
```

### 6.2 Test Allowed DNS Zone Creation
```bash
# This should be allowed
az network private-dns zone create \
  --resource-group rg-spoke-1 \
  --name internal.difu.com
```

### 6.3 Test Automated DNS Record Creation
Create a private endpoint and verify automatic DNS record creation:
```bash
# Create a test Key Vault with private endpoint
az keyvault create --name kv-test-spoke1 --resource-group rg-spoke-1 --location "West Europe"

# Create private endpoint (triggers policy)
az network private-endpoint create \
  --name pe-keyvault-test \
  --resource-group rg-spoke-1 \
  --vnet-name vnet-spoke-1 \
  --subnet storage-subnet \
  --private-connection-resource-id "/subscriptions/.../vaults/kv-test-spoke1" \
  --group-ids vault \
  --connection-name keyvault-connection

# Check if DNS record was automatically created in hub
az account set --subscription "your-hub-subscription-id"
az network private-dns record-set a list \
  --zone-name privatelink.vaultcore.azure.net \
  --resource-group rg-hub-network
```

## Architecture Validation

After successful deployment, verify:

✅ **Network Connectivity**
- Hub and spoke VNets are peered
- Cross-subscription communication works
- No internet routing for private traffic

✅ **DNS Resolution**
- Storage account resolves to private IP
- Private DNS zone linked to spoke VNet
- Centralized DNS management in hub

✅ **Security**
- VM uses managed identity for storage access
- Storage account blocks public access
- Private endpoint provides secure connectivity

✅ **Policy Governance**
- Spoke cannot create privatelink DNS zones
- Spoke can create other private DNS zones
- Centralized policy management
- Automatic DNS record creation for private endpoints
- Policy-driven DNS lifecycle management

## Troubleshooting

### Common Issues

1. **Service Principal Setup Issues**
   ```bash
   # Check if you have sufficient permissions
   az ad user show --id $(az account show --query user.name -o tsv)
   
   # Verify Owner role in both subscriptions
   az role assignment list --assignee $(az account show --query user.name -o tsv) --all
   
   # If setup fails, check existing service principals
   az ad sp list --display-name "sp-hub-terraform-*"
   ```

2. **Environment Activation Issues**
   ```bash
   # Check if environment file exists
   ls -la .env.*
   
   # Check activation script
   ls -la activate-*.sh
   
   # Manually source environment
   export $(cat .env.<environment_name> | grep -v '^#' | xargs)
   ```

3. **Cross-subscription permissions**
   ```bash
   # Verify service principal permissions
   az role assignment list --assignee <service-principal-id>
   
   # Check hub service principal has spoke access
   az role assignment list --assignee <hub-sp-id> --scope /subscriptions/<spoke-subscription-id>
   ```

4. **DNS resolution issues**
   ```bash
   # Check private DNS zone links
   az network private-dns link vnet list --zone-name privatelink.blob.core.windows.net --resource-group rg-hub-network
   ```

5. **Storage access denied**
   ```bash
   # Verify managed identity role assignment
   az role assignment list --scope /subscriptions/.../resourceGroups/rg-spoke-1/providers/Microsoft.Storage/storageAccounts/...
   ```

### Logs and Diagnostics
- Check VM boot diagnostics in Azure portal
- Review cloud-init logs: `/var/log/cloud-init-output.log`
- Test network connectivity: `telnet storage-account.blob.core.windows.net 443`

## Cleanup

### Complete Infrastructure and Service Principal Cleanup

#### Option A: Automated Cleanup (Recommended)
```bash
# Destroy infrastructure (spoke first, then hub)
cd environments/spoke-1
terraform destroy

cd ../hub
terraform destroy

# Remove service principals and cleanup all configuration
../../scripts/cleanup-service-principals.sh <environment_name>
```

#### Option B: Manual Cleanup
```bash
# Destroy spoke first
cd environments/spoke-1
terraform destroy

# Then destroy hub
cd ../hub
terraform destroy

# Manually remove service principals
az ad sp delete --id <hub-service-principal-id>
az ad sp delete --id <spoke-service-principal-id>

# Remove configuration files
rm -f .env.*
rm -f ../../activate-*.sh
rm -f ../../service-principal-credentials-*.json
rm -f ../../USAGE-*.md
```

### Verification
After cleanup, verify all resources are removed:
```bash
# Check no remaining role assignments
az role assignment list --assignee <service-principal-id>

# Verify resource groups are deleted
az group list --output table
```

## Quick Reference

### Service Principal Management Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `setup-service-principals.sh` | Create service principals with cross-subscription permissions | `./setup-service-principals.sh <hub_sub_id> <spoke_sub_id> [env_name]` |
| `configure-environment.sh` | Set up environment variables and activation scripts | `./configure-environment.sh <env_name>` |
| `cleanup-service-principals.sh` | Remove service principals and clean up configuration | `./cleanup-service-principals.sh <env_name>` |

### Environment Files Structure
```
├── environments/
│   ├── hub/.env.<env_name>          # Hub authentication
│   └── spoke-1/.env.<env_name>      # Spoke authentication
├── .env.<env_name>                  # Root environment file
├── activate-<env_name>.sh           # Environment activation script
├── service-principal-credentials-<env_name>.json  # Secure credentials
└── USAGE-<env_name>.md             # Environment-specific usage guide
```

### Common Commands
```bash
# Quick setup for new environment
./scripts/setup-service-principals.sh <hub_sub> <spoke_sub> "prod"
./scripts/configure-environment.sh "prod"
source ./activate-prod.sh

# Deploy infrastructure
cd environments/hub && terraform apply
cd environments/spoke-1 && terraform apply

# Complete cleanup
./scripts/cleanup-service-principals.sh "prod"
```

## Next Steps

- Add more spokes using the same pattern
- Implement Azure Firewall in hub for centralized security
- Add VPN Gateway for on-premises connectivity
- Configure monitoring and alerting
- Implement backup and disaster recovery