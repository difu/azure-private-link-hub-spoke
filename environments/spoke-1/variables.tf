variable "spoke_subscription_id" {
  description = "Azure subscription ID for the spoke"
  type        = string
}

variable "hub_subscription_id" {
  description = "Azure subscription ID for the hub"
  type        = string
}

variable "hub_resource_group_name" {
  description = "Name of the hub resource group"
  type        = string
  default     = "rg-hub-network"
}

variable "hub_vnet_name" {
  description = "Name of the hub virtual network"
  type        = string
  default     = "vnet-hub"
}

variable "spoke_resource_group_name" {
  description = "Name of the spoke resource group"
  type        = string
  default     = "rg-spoke-1"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "West Europe"
}

variable "spoke_vnet_name" {
  description = "Name of the spoke virtual network"
  type        = string
  default     = "vnet-spoke-1"
}

variable "spoke_vnet_address_space" {
  description = "Address space for the spoke virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "vm_subnet_address_prefix" {
  description = "Address prefix for the VM subnet"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}

variable "storage_subnet_address_prefix" {
  description = "Address prefix for the storage subnet"
  type        = list(string)
  default     = ["10.1.2.0/24"]
}

variable "admin_source_address_prefix" {
  description = "Source address prefix for SSH access"
  type        = string
  default     = "*"
}

variable "storage_account_prefix" {
  description = "Prefix for the storage account name"
  type        = string
  default     = "stspoke1"
}

variable "container_name" {
  description = "Name of the blob container"
  type        = string
  default     = "data"
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "vm-spoke-1"
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
  default = {
    Environment = "production"
    Project     = "hub-spoke-infrastructure"
    ManagedBy   = "terraform"
    Spoke       = "spoke-1"
  }
}