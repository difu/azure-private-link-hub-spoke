# output "policy_definition_id" {
#   description = "ID of the policy definition for denying privatelink DNS zones"
#   value       = azurerm_policy_definition.deny_privatelink_dns_zones.id
# }

# output "policy_assignment_ids" {
#   description = "IDs of the policy assignments"
#   value       = { for k, v in azurerm_subscription_policy_assignment.deny_privatelink_dns_zones : k => v.id }
# }

output "tagging_policy_definition_id" {
  description = "ID of the tagging policy definition"
  value       = var.enable_tagging_policy ? azurerm_policy_definition.require_tags[0].id : null
}

output "tagging_policy_assignment_id" {
  description = "ID of the tagging policy assignment"
  value       = var.enable_tagging_policy ? azurerm_subscription_policy_assignment.require_tags[0].id : null
}