variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "vnet_name" {
  description = "Name of the hub virtual network"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the hub virtual network"
  type        = list(string)
}

variable "gateway_subnet_address_prefix" {
  description = "Address prefix for the gateway subnet"
  type        = list(string)
}

variable "dns_subnet_address_prefix" {
  description = "Address prefix for the DNS subnet"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}