terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }

  # backend "azurerm" {
  #   # Configure your backend here
  #   # storage_account_name = "your-tf-state-storage"
  #   # container_name       = "tfstate"
  #   # key                  = "spoke-1.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}
  subscription_id = var.spoke_subscription_id
}

# Provider for hub subscription (for cross-subscription resources)
provider "azurerm" {
  alias           = "hub"
  features {}
  subscription_id = var.hub_subscription_id
}

# Data source to get hub virtual network info
data "azurerm_virtual_network" "hub" {
  provider            = azurerm.hub
  name                = var.hub_vnet_name
  resource_group_name = var.hub_resource_group_name
}

# Data source to get hub private DNS zone
data "azurerm_private_dns_zone" "storage_blob" {
  provider            = azurerm.hub
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.hub_resource_group_name
}

module "spoke" {
  source = "../../modules/spoke"

  resource_group_name            = var.spoke_resource_group_name
  location                      = var.location
  vnet_name                     = var.spoke_vnet_name
  vnet_address_space            = var.spoke_vnet_address_space
  vm_subnet_address_prefix      = var.vm_subnet_address_prefix
  storage_subnet_address_prefix = var.storage_subnet_address_prefix
  
  admin_source_address_prefix = var.admin_source_address_prefix
  storage_account_prefix      = var.storage_account_prefix
  container_name              = var.container_name
  
  hub_vnet_id               = data.azurerm_virtual_network.hub.id
  hub_private_dns_zone_id   = data.azurerm_private_dns_zone.storage_blob.id
  
  vm_name                = var.vm_name
  vm_size                = var.vm_size
  admin_username         = var.admin_username
  admin_ssh_public_key   = var.admin_ssh_public_key
  enable_public_ip       = var.enable_public_ip

  tags = var.tags
}