output "hub_resource_group_name" {
  description = "Name of the hub resource group"
  value       = module.hub.resource_group_name
}

output "hub_vnet_id" {
  description = "ID of the hub virtual network"
  value       = module.hub.vnet_id
}

output "hub_vnet_name" {
  description = "Name of the hub virtual network"
  value       = module.hub.vnet_name
}

output "private_dns_zone_id" {
  description = "ID of the private DNS zone for storage"
  value       = module.hub.private_dns_zone_id
}

output "private_dns_zone_name" {
  description = "Name of the private DNS zone for storage"
  value       = module.hub.private_dns_zone_name
}

output "location" {
  description = "Azure region"
  value       = module.hub.location
}

# output "policy_definition_id" {
#   description = "ID of the policy definition for denying privatelink DNS zones"
#   value       = module.policies.policy_definition_id
# }
#
# output "policy_assignment_ids" {
#   description = "IDs of the policy assignments"
#   value       = module.policies.policy_assignment_ids
# }