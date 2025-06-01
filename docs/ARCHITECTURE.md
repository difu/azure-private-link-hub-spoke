# Hub-Spoke Architecture Documentation

## Overview

This document describes the hub-and-spoke network architecture implemented across multiple Azure subscriptions, providing centralized DNS management and secure private connectivity.

## Subscription Layout

![Subscription Structure](images/subscriptions.png)

The infrastructure is deployed across the subscription structure shown above, with the hub in Work_Subscription_A and spokes distributed across dedicated subscriptions.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Work_Subscription_A (Hub)                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Hub VNet (10.0.0.0/16)                  │ │
│  │                                                            │ │
│  │  ┌─────────────────┐    ┌────────────────────────────────┐ │ │
│  │  │  Gateway Subnet │    │         DNS Subnet             │ │ │
│  │  │   10.0.1.0/24   │    │        10.0.2.0/24             │ │ │
│  │  └─────────────────┘    └────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  ┌───────────────────────────────────────────────────────┐ │ │
│  │  │           Private DNS Zone                            │ │ │
│  │  │       privatelink.blob.core.windows.net               │ │ │
│  │  └───────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                    │
                               VNet Peering
                                    │
┌─────────────────────────────────────────────────────────────────┐
│                      Spoke_1 Subscription                       │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  Spoke VNet (10.1.0.0/16)                  │ │
│  │                                                            │ │
│  │  ┌─────────────────┐    ┌────────────────────────────────┐ │ │
│  │  │   VM Subnet     │    │      Storage Subnet            │ │ │
│  │  │  10.1.1.0/24    │    │       10.1.2.0/24              │ │ │
│  │  │                 │    │                                │ │ │
│  │  │ ┌─────────────┐ │    │ ┌─────────────┐                │ │ │
│  │  │ │     VM      │ │    │ │   Private   │                │ │ │
│  │  │ │             │ │    │ │  Endpoint   │                │ │ │
│  │  │ │ Managed ID  │ │    │ │             │                │ │ │
│  │  │ └─────────────┘ │    │ └─────────────┘                │ │ │
│  │  └─────────────────┘    └────────────────────────────────┘ │ │
│  │                                        │                   │ │
│  │                          ┌───────────────────────────────┐ │ │
│  │                          │       Storage Account         │ │ │
│  │                          │     (Private Access Only)     │ │ │
│  │                          │                               │ │ │
│  │                          │ ┌───────────────────────────┐ │ │ │
│  │                          │ │      Blob Container       │ │ │ │
│  │                          │ │         "data"            │ │ │ │
│  │                          │ └───────────────────────────┘ │ │ │
│  │                          └───────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Key Components

### Hub Infrastructure (Work_Subscription_A)

#### Virtual Network
- **Address Space**: `10.0.0.0/16`
- **Gateway Subnet**: `10.0.1.0/24` - Reserved for future VPN/ExpressRoute gateway
- **DNS Subnet**: `10.0.2.0/24` - For DNS servers and management

#### Private DNS Zone
- **Zone**: `privatelink.blob.core.windows.net`
- **Purpose**: Centralized DNS resolution for Azure Storage private endpoints
- **Links**: Connected to hub VNet and all spoke VNets

#### Azure Policies
- **Scope**: All spoke subscriptions
- **Rule**: Deny creation of private DNS zones containing "privatelink"
- **Effect**: Ensures centralized DNS management

### Spoke Infrastructure (Spoke_1)

#### Virtual Network
- **Address Space**: `10.1.0.0/16`
- **VM Subnet**: `10.1.1.0/24` - For virtual machines
- **Storage Subnet**: `10.1.2.0/24` - For private endpoints

#### Virtual Machine
- **Size**: Standard_B2s (customizable)
- **OS**: Ubuntu 22.04 LTS
- **Identity**: System-assigned managed identity
- **Access**: SSH key authentication
- **Storage Role**: Storage Blob Data Contributor

#### Storage Account
- **Type**: StorageV2, Standard LRS
- **Access**: Private endpoints only
- **Container**: "data" container for blob storage
- **Security**: No public access, private endpoint required

#### Private Endpoint
- **Service**: Storage account blob service
- **Subnet**: Storage subnet (10.1.2.0/24)
- **DNS**: Integrated with hub private DNS zone

## Network Flow

### Data Path for Storage Access
1. **VM initiates connection** to storage account FQDN
2. **DNS resolution** via hub private DNS zone returns private IP
3. **Traffic routes** through VNet peering to storage subnet
4. **Private endpoint** provides secure access to storage service
5. **Authentication** via managed identity (no keys required)

### Cross-Subscription Connectivity
```
VM (Spoke) → VNet Peering → Hub VNet → VNet Peering → Storage PE (Spoke)
    ↓
DNS Query → Hub Private DNS Zone → Private IP Resolution
```

## Security Model

### Network Security
- **No public internet access** for storage operations
- **Private endpoint** ensures traffic stays within Azure backbone
- **Network security groups** control inbound/outbound traffic
- **VNet peering** provides secure cross-subscription connectivity

### Identity and Access Management
- **Managed identity** eliminates need for storage keys
- **RBAC assignments** provide least-privilege access
- **Azure policies** enforce governance at scale

### DNS Security
- **Centralized DNS zones** prevent DNS sprawl
- **Policy enforcement** blocks unauthorized private DNS zones
- **Private resolution** for Azure services

## Scalability Patterns

### Adding New Spokes
1. Deploy spoke infrastructure using the same module
2. Establish VNet peering to hub
3. Link spoke VNet to hub private DNS zones
4. Configure appropriate RBAC assignments

### Multi-Region Support
```
Hub Region 1 ←→ Hub Region 2
    ↓               ↓
Spoke 1-A       Spoke 2-A
Spoke 1-B       Spoke 2-B
```

### Service-Specific DNS Zones
- `privatelink.database.windows.net` - Azure SQL Database
- `privatelink.vault.azure.net` - Azure Key Vault
- `privatelink.azurecr.io` - Azure Container Registry

## Compliance and Governance

### Policy Framework
```hcl
# Example policy rule (simplified)
{
  "if": {
    "allOf": [
      {
        "field": "type",
        "equals": "Microsoft.Network/privateDnsZones"
      },
      {
        "field": "name",
        "contains": "privatelink"
      }
    ]
  },
  "then": {
    "effect": "deny"
  }
}
```

### Tagging Strategy
- **Environment**: production, staging, development
- **Project**: hub-spoke-infrastructure
- **ManagedBy**: terraform
- **Owner**: platform-team
- **Spoke**: spoke-1, spoke-2, etc.

## Monitoring and Observability

### Key Metrics
- VNet peering connection status
- Private endpoint health
- DNS resolution success rate
- Storage access patterns
- Policy compliance status

### Diagnostic Settings
- Network Security Group flow logs
- Private endpoint network logs
- DNS query logs (via DNS Analytics)

## Cost Optimization

### Resource Costs
- **VNet Peering**: Per GB data transfer
- **Private Endpoints**: Fixed monthly cost per endpoint
- **Storage**: Based on data volume and transactions
- **Virtual Machines**: Compute costs based on size/usage

### Cost Savings
- Centralized DNS zones reduce management overhead
- Private endpoints eliminate egress charges for storage access
- Shared hub infrastructure across multiple spokes

## Disaster Recovery

### RTO/RPO Considerations
- **VNet peering**: Auto-healing, typically < 1 minute
- **Private endpoints**: Recreated via Terraform if needed
- **DNS zones**: Backed up via policy and configuration

### Backup Strategy
- Terraform state files in secure storage
- Configuration as code in version control
- Regular infrastructure snapshots

## Future Enhancements

### Phase 2 Additions
- Azure Firewall for centralized security filtering
- VPN Gateway for on-premises connectivity
- Azure Monitor for comprehensive logging

### Phase 3 Additions
- Multiple hub regions for global connectivity
- Azure Virtual WAN for simplified management
- Integration with Azure Security Center