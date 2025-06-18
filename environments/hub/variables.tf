variable "hub_subscription_id" {
  description = "Azure subscription ID for the hub"
  type        = string
}

variable "spoke_subscription_id" {
  description = "Azure subscription ID for the spoke (for cross-subscription peering)"
  type        = string
  default     = null
}

variable "hub_resource_group_name" {
  description = "Name of the hub resource group"
  type        = string
  default     = "rg-hub-network"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "West Europe"
}

variable "hub_vnet_name" {
  description = "Name of the hub virtual network"
  type        = string
  default     = "vnet-hub"
}

variable "hub_vnet_address_space" {
  description = "Address space for the hub virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "gateway_subnet_address_prefix" {
  description = "Address prefix for the gateway subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "dns_subnet_address_prefix" {
  description = "Address prefix for the DNS subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "spoke_vnet_id" {
  description = "ID of the spoke virtual network for peering"
  type        = string
  default     = null
}

variable "enable_spoke_peering" {
  description = "Whether to enable peering to spoke VNet"
  type        = bool
  default     = false
}

variable "enable_spoke_dns_link" {
  description = "Whether to link spoke VNet to private DNS zone"
  type        = bool
  default     = false
}

variable "spoke_subscription_ids" {
  description = "Map of spoke subscription IDs for policy assignment"
  type        = map(string)
  default = {
    spoke-1 = "subscription-id-placeholder"
  }
}

variable "management_group_id" {
  description = "Management group ID for policy assignment scope"
  type        = string
  default     = null
}

variable "enable_tagging_policy" {
  description = "Whether to enable the tagging policy"
  type        = bool
  default     = false
}

variable "enable_all_privatelink_zones" {
  description = "Whether to create all privatelink DNS zones or just essential ones"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "hub-spoke-infrastructure"
    ManagedBy   = "terraform"
  }
}