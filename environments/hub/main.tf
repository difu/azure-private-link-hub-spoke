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
  # }
}

provider "azurerm" {
  features {}
  subscription_id = var.hub_subscription_id
}

# Provider for spoke subscriptions (for cross-subscription peering)
provider "azurerm" {
  alias           = "spoke"
  features {}
  subscription_id = var.spoke_subscription_id
}

module "hub" {
  source = "../../modules/hub"

  resource_group_name            = var.hub_resource_group_name
  location                      = var.location
  vnet_name                     = var.hub_vnet_name
  vnet_address_space            = var.hub_vnet_address_space
  gateway_subnet_address_prefix = var.gateway_subnet_address_prefix
  dns_subnet_address_prefix     = var.dns_subnet_address_prefix
  enable_all_privatelink_zones  = var.enable_all_privatelink_zones

  tags = var.tags
}

# Hub to Spoke VNet Peering
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count = var.enable_spoke_peering ? 1 : 0

  name                      = "hub-to-spoke"
  resource_group_name       = module.hub.resource_group_name
  virtual_network_name      = module.hub.vnet_name
  remote_virtual_network_id = var.spoke_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false

  depends_on = [module.hub]
}

# Link Private DNS Zone to Spoke VNets
resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob_spoke" {
  count = var.enable_spoke_dns_link ? 1 : 0

  name                  = "spoke-link"
  resource_group_name   = module.hub.resource_group_name
  private_dns_zone_name = module.hub.private_dns_zone_name
  virtual_network_id    = var.spoke_vnet_id
  registration_enabled  = false

  tags = var.tags

  depends_on = [module.hub]
}

# Azure Policies for DNS zone governance and automation
module "policies" {
  source = "../../modules/policies"

  spoke_subscription_ids      = var.spoke_subscription_ids
  hub_subscription_id         = var.hub_subscription_id
  hub_resource_group_name     = var.hub_resource_group_name
  enable_tagging_policy       = var.enable_tagging_policy
  policy_assignment_location  = var.location
}