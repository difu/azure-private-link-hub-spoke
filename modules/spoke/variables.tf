variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "vnet_name" {
  description = "Name of the spoke virtual network"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the spoke virtual network"
  type        = list(string)
}

variable "vm_subnet_address_prefix" {
  description = "Address prefix for the VM subnet"
  type        = list(string)
}

variable "storage_subnet_address_prefix" {
  description = "Address prefix for the storage subnet"
  type        = list(string)
}

variable "admin_source_address_prefix" {
  description = "Source address prefix for SSH access"
  type        = string
  default     = "*"
}

variable "storage_account_prefix" {
  description = "Prefix for the storage account name"
  type        = string
}

variable "container_name" {
  description = "Name of the blob container"
  type        = string
  default     = "data"
}

variable "hub_vnet_id" {
  description = "ID of the hub virtual network"
  type        = string
}

variable "hub_private_dns_zone_id" {
  description = "ID of the hub private DNS zone for storage"
  type        = string
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "enable_public_ip" {
  description = "Whether to create a public IP for the VM"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}