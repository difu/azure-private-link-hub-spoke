# DNS Zone Governance in Hub-Spoke Architecture

## Overview

This document describes the DNS zone governance framework implemented in the hub-spoke architecture to ensure centralized private DNS management and prevent DNS conflicts across subscriptions.

## Architecture Principles

### Centralized DNS Management
- **Hub Subscription**: Contains all privatelink DNS zones for Azure services
- **Spoke Subscriptions**: Cannot create privatelink DNS zones (enforced by policy)
- **Cross-Subscription Access**: Automated DNS record creation for spoke private endpoints

### Governance Framework
The solution implements a two-tier governance approach:

1. **Preventive Controls**: Deny policies that block creation of conflicting DNS zones
2. **Automated Management**: DeployIfNotExists policies that automatically manage DNS records

## Policy Implementation

### 1. Deny Privatelink DNS Zones Policy

**Purpose**: Prevents creation of privatelink DNS zones in spoke subscriptions

**Policy Definition**:
```hcl
resource "azurerm_policy_definition" "deny_privatelink_dns_zones" {
  name         = "deny-privatelink-dns-zones"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Deny creation of private DNS zones containing 'privatelink'"
  description  = "This policy denies the creation of private DNS zones that contain 'privatelink' in their name. These zones should be centrally managed in the hub subscription."

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Network/privateDnsZones"
        },
        {
          field    = "name"
          contains = "privatelink"
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}
```

**Scope**: Applied to all spoke subscriptions
**Effect**: Immediate denial of privatelink DNS zone creation attempts

### 2. Auto-Create DNS Records Policy

**Purpose**: Automatically creates DNS A records in hub zones when private endpoints are deployed in spoke subscriptions

**Policy Definition**:
```hcl
resource "azurerm_policy_definition" "auto_create_private_endpoint_dns" {
  name         = "auto-create-private-endpoint-dns"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Auto-create DNS records for private endpoints"
  description  = "Automatically creates DNS A records in the hub private DNS zones when private endpoints are created"

  parameters = jsonencode({
    hubResourceGroupName = {
      type = "String"
      metadata = {
        displayName = "Hub Resource Group Name"
        description = "Name of the resource group containing the hub private DNS zones"
      }
    }
  })
  # ... detailed policy rules for DNS automation
}
```

**Supported Services**:
- Storage (blob, table, queue, file, dfs)
- SQL Server (sqlServer)
- Key Vault (vault)
- Additional services can be added by extending the policy

**Automation Flow**:
1. Private endpoint created in spoke subscription
2. Policy detects deployment
3. Determines appropriate DNS zone based on service type
4. Creates DNS A record in hub subscription
5. Links private IP to service FQDN

## Permission Model

### Cross-Subscription Access
The automation requires specific permissions for policy-managed identities:

```hcl
resource "azurerm_role_assignment" "policy_dns_contributor" {
  for_each = var.spoke_subscription_ids

  scope                = "/subscriptions/${var.hub_subscription_id}/resourceGroups/${var.hub_resource_group_name}"
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_subscription_policy_assignment.auto_create_private_endpoint_dns[each.key].identity[0].principal_id
}
```

### Required Roles
- **Hub Subscription**: Resource Policy Contributor (for policy definitions)
- **Spoke Subscriptions**: Policy-managed identity with DNS Zone Contributor on hub
- **Deployment Principal**: Resource Policy Contributor on both hub and spoke

## Configuration

### Hub Subscription Configuration

```hcl
# Enable policies module in hub deployment
module "policies" {
  source = "../../modules/policies"

  spoke_subscription_ids      = var.spoke_subscription_ids
  hub_subscription_id         = var.hub_subscription_id
  hub_resource_group_name     = var.hub_resource_group_name
  enable_tagging_policy       = var.enable_tagging_policy
  policy_assignment_location  = var.location
}
```

### Terraform Variables

```hcl
# Hub subscription configuration
hub_subscription_id = "a19411fb-fd20-410a-8b76-90008149fe87"

# Spoke subscriptions for policy assignment
spoke_subscription_ids = {
  spoke-1 = "/subscriptions/b9281dfe-d28d-4fea-b6b2-f4d190221a33"
  spoke-2 = "/subscriptions/your-spoke-2-subscription-id"
}

# Hub networking
hub_resource_group_name = "rg-hub-network"
```

## DNS Zone Coverage

### Comprehensive Private DNS Zones
The hub can manage DNS zones for 25+ Azure services:

**Storage Services**:
- `privatelink.blob.core.windows.net`
- `privatelink.table.core.windows.net`
- `privatelink.queue.core.windows.net`
- `privatelink.file.core.windows.net`
- `privatelink.dfs.core.windows.net`

**Database Services**:
- `privatelink.database.windows.net`
- `privatelink.mysql.database.azure.com`
- `privatelink.postgres.database.azure.com`
- `privatelink.documents.azure.com`

**Other Services**:
- `privatelink.vault.azure.net` (Key Vault)
- `privatelink.azurecr.io` (Container Registry)
- `privatelink.azurewebsites.net` (App Services)

### Configuration Options

```yaml
# Enable comprehensive DNS zone coverage
enable_all_privatelink_zones: true  # Creates all 25+ zones

# Or minimal coverage (development)
enable_all_privatelink_zones: false  # Only essential zones
```

## Deployment Process

### 1. Hub Infrastructure Deployment
```bash
cd environments/hub
terraform init
terraform plan
terraform apply
```

### 2. Policy Verification
```bash
# Check policy definitions
az policy definition list --query "[?displayName=='Deny creation of private DNS zones containing privatelink'].{Name:name,DisplayName:displayName}"

# Check policy assignments
az policy assignment list --query "[?displayName=='Automatically creates DNS records for private endpoints'].{Name:name,Scope:scope}"
```

### 3. Spoke Deployment
```bash
cd environments/spoke-1
terraform init
terraform plan
terraform apply
```

## Operational Procedures

### Testing DNS Governance

**Test 1: Verify Deny Policy**
```bash
# Attempt to create privatelink DNS zone in spoke (should fail)
az network private-dns zone create \
  --resource-group rg-spoke-1 \
  --name privatelink.test.azure.com
```
Expected: Policy violation error

**Test 2: Verify Auto-DNS Creation**
```bash
# Deploy private endpoint in spoke
# Check automatic DNS record creation in hub
az network private-dns record-set a list \
  --resource-group rg-hub-network \
  --zone-name privatelink.blob.core.windows.net
```
Expected: Automatic A record for private endpoint

### Troubleshooting

**Common Issues**:

1. **Policy Assignment Failures**
   - Cause: Insufficient permissions
   - Solution: Grant Resource Policy Contributor role

2. **Cross-Subscription DNS Record Creation Fails**
   - Cause: Missing DNS Zone Contributor permissions
   - Solution: Verify role assignments for policy-managed identities

3. **Policy Definition Out of Scope**
   - Cause: Attempting cross-subscription policy assignment
   - Solution: Ensure policies are defined in appropriate scope

### Monitoring and Compliance

**Policy Compliance Dashboard**:
```bash
# Check policy compliance across subscriptions
az policy state list --resource-group rg-spoke-1 \
  --query "[?policyDefinitionName=='deny-privatelink-dns-zones'].{Resource:resourceId,ComplianceState:complianceState}"
```

**DNS Record Monitoring**:
```bash
# Monitor automatic DNS record creation
az monitor activity-log list \
  --resource-group rg-hub-network \
  --start-time 2025-06-19T00:00:00Z \
  --query "[?operationName.value=='Microsoft.Network/privateDnsZones/A/write'].{Time:eventTimestamp,Resource:resourceId}"
```

## Security Considerations

### Network Security
- Private DNS zones are not exposed to public internet
- DNS resolution follows private network paths
- Cross-subscription access is identity-based, not network-based

### Identity Security
- Policy-managed identities use least-privilege permissions
- No persistent service principals required
- Automatic credential rotation through Azure platform

### Audit and Compliance
- All DNS operations are logged in Azure Activity Log
- Policy compliance tracked in Azure Policy dashboard
- Resource creation audited across subscriptions

## Best Practices

### Design Principles
1. **Centralization**: All privatelink DNS zones in hub subscription
2. **Automation**: Policy-driven DNS record lifecycle management
3. **Consistency**: Standardized naming and configuration across environments
4. **Security**: Least-privilege access with managed identities

### Operational Guidelines
1. **Test in Development**: Validate policies in non-production environments
2. **Monitor Compliance**: Regular review of policy violations
3. **Document Exceptions**: Clearly document any policy exemptions
4. **Backup Strategy**: Include DNS zones in disaster recovery planning

## Migration Considerations

### Existing Environments
For environments with existing privatelink DNS zones in spoke subscriptions:

1. **Assessment Phase**:
   - Inventory existing privatelink DNS zones
   - Document current DNS resolution paths
   - Identify potential conflicts

2. **Migration Phase**:
   - Create equivalent zones in hub subscription
   - Migrate DNS records to hub zones
   - Update VNet links to point to hub zones
   - Remove spoke-based DNS zones

3. **Validation Phase**:
   - Test private endpoint resolution
   - Verify cross-subscription connectivity
   - Enable governance policies

## Future Enhancements

### Planned Improvements
1. **Extended Service Support**: Additional Azure service DNS zones
2. **Multi-Region Support**: Hub zones in multiple regions
3. **Advanced Monitoring**: Custom alerts for policy violations
4. **Automated Remediation**: Self-healing DNS configurations

### Integration Opportunities
1. **Azure Lighthouse**: Multi-tenant management capabilities
2. **Azure Blueprints**: Standardized environment deployment
3. **Azure DevOps**: Automated policy deployment pipelines
4. **Azure Monitor**: Enhanced observability and alerting

## Conclusion

The DNS zone governance framework provides robust, automated management of private DNS infrastructure across the hub-spoke architecture. By combining preventive policies with automated remediation, the solution ensures consistent, secure, and scalable private endpoint resolution while maintaining centralized control and reducing operational overhead.

This approach aligns with Microsoft Cloud Adoption Framework best practices and provides a foundation for enterprise-scale private networking in Azure.