output "resource_group_id" {
  description = "ID of the hub resource group"
  value       = azurerm_resource_group.hub.id
}

output "resource_group_name" {
  description = "Name of the hub resource group"
  value       = azurerm_resource_group.hub.name
}

output "vnet_id" {
  description = "ID of the hub virtual network"
  value       = azurerm_virtual_network.hub.id
}

output "vnet_name" {
  description = "Name of the hub virtual network"
  value       = azurerm_virtual_network.hub.name
}

output "private_dns_zone_id" {
  description = "ID of the storage blob private DNS zone"
  value       = azurerm_private_dns_zone.storage_blob.id
}

output "private_dns_zone_name" {
  description = "Name of the storage blob private DNS zone"
  value       = azurerm_private_dns_zone.storage_blob.name
}

output "location" {
  description = "Azure region"
  value       = azurerm_resource_group.hub.location
}