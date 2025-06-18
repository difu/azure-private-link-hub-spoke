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

# Policy Definition: Auto-create DNS records for private endpoints
resource "azurerm_policy_definition" "auto_create_private_endpoint_dns" {
  name         = "auto-create-private-endpoint-dns"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Auto-create DNS records for private endpoints"
  description  = "Automatically creates DNS A records in the hub private DNS zones when private endpoints are created"

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field = "type"
          equals = "Microsoft.Network/privateEndpoints"
        },
        {
          field = "Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]"
          in = ["blob", "table", "queue", "file", "dfs", "sqlServer", "vault"]
        }
      ]
    }
    then = {
      effect = "deployIfNotExists"
      details = {
        type = "Microsoft.Network/privateDnsZones/A"
        existenceCondition = {
          allOf = [
            {
              field = "Microsoft.Network/privateDnsZones/A/aRecords[*].ipv4Address"
              exists = "true"
            }
          ]
        }
        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7" # DNS Zone Contributor
        ]
        deployment = {
          properties = {
            mode = "incremental"
            template = {
              "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
              contentVersion = "1.0.0.0"
              parameters = {
                privateEndpointName = {
                  type = "string"
                }
                privateDnsZoneName = {
                  type = "string"
                }
                privateEndpointIP = {
                  type = "string"
                }
                hubResourceGroupName = {
                  type = "string"
                }
              }
              resources = [
                {
                  type = "Microsoft.Network/privateDnsZones/A"
                  apiVersion = "2020-06-01"
                  name = "[concat(parameters('privateDnsZoneName'), '/', parameters('privateEndpointName'))]"
                  properties = {
                    TTL = 3600
                    ARecords = [
                      {
                        ipv4Address = "[parameters('privateEndpointIP')]"
                      }
                    ]
                  }
                  dependsOn = []
                }
              ]
            }
            parameters = {
              privateEndpointName = {
                value = "[field('name')]"
              }
              privateDnsZoneName = {
                value = "[if(contains(field('Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]'), 'blob'), 'privatelink.blob.core.windows.net', if(contains(field('Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]'), 'table'), 'privatelink.table.core.windows.net', if(contains(field('Microsoft.Network/privateEndpoints/privateLinkServiceConnections[*].groupIds[*]'), 'sqlServer'), 'privatelink.database.windows.net', 'privatelink.vault.azure.net')))]"
              }
              privateEndpointIP = {
                value = "[reference(field('id'), '2020-06-01').networkInterfaces[0].ipConfigurations[0].privateIPAddress]"
              }
              hubResourceGroupName = {
                value = "[parameters('hubResourceGroupName')]"
              }
            }
          }
        }
      }
    }
  })

  metadata = jsonencode({
    category = "Network"
  })
}

# Policy Assignment for Auto DNS Record Creation
resource "azurerm_subscription_policy_assignment" "auto_create_private_endpoint_dns" {
  for_each = var.spoke_subscription_ids
  
  name                 = "auto-dns-records-${each.key}"
  description          = "Automatically creates DNS records for private endpoints in spoke subscription ${each.key}"
  policy_definition_id = azurerm_policy_definition.auto_create_private_endpoint_dns.id
  subscription_id      = each.value

  identity {
    type = "SystemAssigned"
  }

  location = var.policy_assignment_location

  parameters = jsonencode({
    hubResourceGroupName = {
      value = var.hub_resource_group_name
    }
  })

  metadata = jsonencode({
    assignedBy = "Terraform Hub-Spoke Infrastructure"
  })
}

# Role assignment for policy managed identity
resource "azurerm_role_assignment" "policy_dns_contributor" {
  for_each = var.spoke_subscription_ids

  scope                = "/subscriptions/${var.hub_subscription_id}/resourceGroups/${var.hub_resource_group_name}"
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_subscription_policy_assignment.auto_create_private_endpoint_dns[each.key].identity[0].principal_id
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