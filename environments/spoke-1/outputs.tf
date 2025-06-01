output "spoke_resource_group_name" {
  description = "Name of the spoke resource group"
  value       = module.spoke.resource_group_name
}

output "spoke_vnet_id" {
  description = "ID of the spoke virtual network"
  value       = module.spoke.vnet_id
}

output "spoke_vnet_name" {
  description = "Name of the spoke virtual network"
  value       = module.spoke.vnet_name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = module.spoke.storage_account_name
}

output "container_name" {
  description = "Name of the blob container"
  value       = module.spoke.container_name
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = module.spoke.vm_name
}

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = module.spoke.vm_public_ip
}

output "vm_private_ip" {
  description = "Private IP address of the VM"
  value       = module.spoke.vm_private_ip
}

output "vm_identity_principal_id" {
  description = "Principal ID of the VM managed identity"
  value       = module.spoke.vm_identity_principal_id
}

output "private_endpoint_ip" {
  description = "Private IP address of the storage private endpoint"
  value       = module.spoke.private_endpoint_ip
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = var.enable_public_ip ? "ssh ${var.admin_username}@${module.spoke.vm_public_ip}" : "ssh ${var.admin_username}@${module.spoke.vm_private_ip}"
}