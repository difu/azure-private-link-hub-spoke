output "resource_group_id" {
  description = "ID of the spoke resource group"
  value       = azurerm_resource_group.spoke.id
}

output "resource_group_name" {
  description = "Name of the spoke resource group"
  value       = azurerm_resource_group.spoke.name
}

output "vnet_id" {
  description = "ID of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.id
}

output "vnet_name" {
  description = "Name of the spoke virtual network"
  value       = azurerm_virtual_network.spoke.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.spoke.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.spoke.id
}

output "container_name" {
  description = "Name of the blob container"
  value       = azurerm_storage_container.data.name
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = var.enable_public_ip ? azurerm_public_ip.vm[0].ip_address : null
}

output "vm_private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "vm_identity_principal_id" {
  description = "Principal ID of the VM system-assigned managed identity"
  value       = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}

output "private_endpoint_ip" {
  description = "Private IP address of the storage private endpoint"
  value       = azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address
}