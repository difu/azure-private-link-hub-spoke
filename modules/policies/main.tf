terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Policy Definition: Deny creation of private DNS zones containing "privatelink"
resource "azurerm_policy_definition" "deny_privatelink_dns_zones" {
  # count=1
  name         = "deny-privatelink-dns-zones"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Deny creation of private DNS zones containing 'privatelink'"
  management_group_id = "/providers/Microsoft.Management/managementGroups/Spokes"
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

  metadata = jsonencode({
    category = "Network"
  })
}

# Policy Assignment for Spoke Subscriptions
# resource "azurerm_policy_assignment" "deny_privatelink_dns_zones" {
#   for_each = var.spoke_subscription_ids
#
#   name                 = "deny-privatelink-dns-zones-${each.key}"
#   scope                = "/subscriptions/${each.value}"
#   policy_definition_id = azurerm_policy_definition.deny_privatelink_dns_zones.id
#   display_name         = "Deny privatelink DNS zones in ${each.key}"
#   description          = "Prevents creation of private DNS zones containing 'privatelink' in spoke subscription ${each.key}"
#
#   metadata = jsonencode({
#     assignedBy = "Terraform Hub-Spoke Infrastructure"
#   })
#
#   parameters = jsonencode({})
# }

resource "azurerm_subscription_policy_assignment" "deny_privatelink_dns_zones" {
  for_each = var.spoke_subscription_ids
  name                 = "deny-privatelink-dns-zones-${each.key}"
  description          = "Prevents creation of private DNS zones containing 'privatelink' in spoke subscription ${each.key}"
  policy_definition_id = azurerm_policy_definition.deny_privatelink_dns_zones.id
  subscription_id      = each.value

  metadata = jsonencode({
    assignedBy = "Terraform Hub-Spoke Infrastructure"
  })

  parameters = jsonencode({})
}

# Policy Definition: Require specific tags on resources
resource "azurerm_policy_definition" "require_tags" {
  count = var.enable_tagging_policy ? 1 : 0

  name         = "require-hub-spoke-tags"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Require specific tags on hub-spoke resources"
  description  = "This policy requires specific tags on resources in the hub-spoke architecture"

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field = "type"
          in = [
            "Microsoft.Network/virtualNetworks",
            "Microsoft.Network/privateDnsZones",
            "Microsoft.Compute/virtualMachines",
            "Microsoft.Storage/storageAccounts"
          ]
        },
        {
          anyOf = [
            {
              field    = "tags['Environment']"
              exists   = "false"
            },
            {
              field    = "tags['Project']"
              exists   = "false"
            }
          ]
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })

  metadata = jsonencode({
    category = "Tags"
  })
}

# Policy Assignment for Tag Requirements
# resource "azurerm_policy_assignment" "require_tags" {
#   count = var.enable_tagging_policy ? 1 : 0
#
#   name                 = "require-hub-spoke-tags"
#   scope                = var.management_group_id != null ? var.management_group_id : "/subscriptions/${var.hub_subscription_id}"
#   policy_definition_id = azurerm_policy_definition.require_tags[0].id
#   display_name         = "Require tags on hub-spoke resources"
#   description          = "Enforces required tags on hub-spoke infrastructure resources"
#
#   metadata = jsonencode({
#     assignedBy = "Terraform Hub-Spoke Infrastructure"
#   })
#
#   parameters = jsonencode({})
# }

resource "azurerm_subscription_policy_assignment" "require_tags" {
  count = var.enable_tagging_policy ? 1 : 0
  name                 = "require-hub-spoke-tags"
  display_name         = "Require tags on hub-spoke resources"
  description          = "Enforces required tags on hub-spoke infrastructure resources"
  policy_definition_id = azurerm_policy_definition.require_tags[0].id
  subscription_id      = var.management_group_id != null ? var.management_group_id : "/subscriptions/${var.hub_subscription_id}"

  metadata = jsonencode({
    assignedBy = "Terraform Hub-Spoke Infrastructure"
  })

  parameters = jsonencode({})
}