# DNS Zone Governance - Quick Reference

## 🎯 Purpose
Prevent DNS conflicts in hub-spoke architecture by centralizing privatelink DNS zone management in the hub subscription.

## 🚫 What It Prevents
- Spoke subscriptions creating conflicting `privatelink.*` DNS zones
- DNS resolution conflicts across subscriptions  
- Decentralized DNS management complexity

## ✅ What It Enables
- Centralized DNS management in hub subscription
- Automatic DNS record creation for spoke private endpoints
- Consistent private endpoint resolution across all spokes
- Enterprise-scale DNS governance

## 🔧 Implementation

### Deny Policy (Spoke Subscriptions)
```hcl
# Blocks creation of any DNS zone containing "privatelink"
effect = "deny"
scope = "spoke-subscriptions"
target = "Microsoft.Network/privateDnsZones"
condition = "name contains 'privatelink'"
```

### Auto-DNS Policy (Cross-Subscription)
```hcl
# Automatically creates DNS A records in hub zones
effect = "deployIfNotExists"
scope = "spoke-subscriptions" 
trigger = "private-endpoint-creation"
action = "create-dns-record-in-hub"
```

## 📋 Quick Validation

### Test Deny Policy
```bash
# This should FAIL with policy violation
az network private-dns zone create \
  --resource-group rg-spoke-1 \
  --name privatelink.test.azure.com
```

### Test Auto-DNS Creation
```bash
# Deploy private endpoint, then check hub DNS zone
az network private-dns record-set a list \
  --resource-group rg-hub-network \
  --zone-name privatelink.blob.core.windows.net
```

## 🚨 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Policy assignment fails | Missing permissions | Grant `Resource Policy Contributor` role |
| DNS records not created | Missing DNS permissions | Verify `Private DNS Zone Contributor` role |
| Cross-subscription errors | Policy scope issues | Ensure policies deployed in correct scope |

## 📖 Full Documentation
See [DNS_ZONE_GOVERNANCE.md](DNS_ZONE_GOVERNANCE.md) for complete implementation details, troubleshooting procedures, and operational guidance.

## ✨ Benefits
- ✅ **Prevents DNS sprawl** across subscriptions
- ✅ **Automates DNS management** for private endpoints  
- ✅ **Enforces enterprise governance** through Azure Policy
- ✅ **Aligns with CAF best practices** for private networking
- ✅ **Reduces operational overhead** through automation