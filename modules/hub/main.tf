terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

resource "azurerm_resource_group" "hub" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = var.vnet_name
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = var.vnet_address_space

  tags = var.tags
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = var.gateway_subnet_address_prefix
}

resource "azurerm_subnet" "dns" {
  name                 = "dns-subnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = var.dns_subnet_address_prefix
}

# Comprehensive Private DNS Zones for Azure Services
locals {
  # Comprehensive list of privatelink DNS zones for Azure services
  privatelink_dns_zones = {
    # Storage Services
    "storage_blob"  = "privatelink.blob.core.windows.net"
    "storage_table" = "privatelink.table.core.windows.net" 
    "storage_queue" = "privatelink.queue.core.windows.net"
    "storage_file"  = "privatelink.file.core.windows.net"
    "storage_dfs"   = "privatelink.dfs.core.windows.net"
    
    # Database Services
    "sql_database"     = "privatelink.database.windows.net"
    "mysql_database"   = "privatelink.mysql.database.azure.com"
    "postgres_database" = "privatelink.postgres.database.azure.com"
    "cosmos_sql"       = "privatelink.documents.azure.com"
    "cosmos_mongo"     = "privatelink.mongo.cosmos.azure.com"
    "cosmos_cassandra" = "privatelink.cassandra.cosmos.azure.com"
    "cosmos_gremlin"   = "privatelink.gremlin.cosmos.azure.com"
    "cosmos_table"     = "privatelink.table.cosmos.azure.com"
    
    # Key Vault and Security
    "key_vault"     = "privatelink.vaultcore.azure.net"
    "managed_hsm"   = "privatelink.managedhsm.azure.net"
    
    # Container Services
    "container_registry" = "privatelink.azurecr.io"
    "aks_management"     = "privatelink.${var.location}.azmk8s.io"
    
    # Web and API Services  
    "app_service"   = "privatelink.azurewebsites.net"
    "function_app"  = "privatelink.azurewebsites.net"
    "api_management" = "privatelink.azure-api.net"
    
    # Analytics and AI
    "synapse_dev"       = "privatelink.dev.azuresynapse.net"
    "synapse_sql"       = "privatelink.sql.azuresynapse.net"
    "cognitive_services" = "privatelink.cognitiveservices.azure.com"
    "machine_learning"  = "privatelink.api.azureml.ms"
    
    # Monitoring and Management
    "monitor"           = "privatelink.monitor.azure.com"
    "log_analytics"     = "privatelink.ods.opinsights.azure.com"
    "automation"        = "privatelink.azure-automation.net"
    
    # Event and Messaging Services
    "event_hub"         = "privatelink.servicebus.windows.net"
    "service_bus"       = "privatelink.servicebus.windows.net"
    "event_grid"        = "privatelink.eventgrid.azure.net"
    "relay"             = "privatelink.servicebus.windows.net"
    
    # IoT Services
    "iot_hub"           = "privatelink.azure-devices.net"
    "iot_provisioning"  = "privatelink.azure-devices-provisioning.net"
    
    # Backup and Recovery
    "backup_vault"      = "privatelink.${var.location}.backup.windowsazure.com"
    "site_recovery"     = "privatelink.siterecovery.windowsazure.com"
  }
}

# Create Private DNS Zones
resource "azurerm_private_dns_zone" "zones" {
  for_each = var.enable_all_privatelink_zones ? local.privatelink_dns_zones : { 
    storage_blob = "privatelink.blob.core.windows.net" 
  }
  
  name                = each.value
  resource_group_name = azurerm_resource_group.hub.name
  tags                = var.tags
}

# Link Private DNS Zones to Hub VNet
resource "azurerm_private_dns_zone_virtual_network_link" "hub_links" {
  for_each = azurerm_private_dns_zone.zones
  
  name                  = "hub-link-${each.key}"
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = var.tags
}

# Network Security Group for DNS subnet
resource "azurerm_network_security_group" "dns" {
  name                = "${var.vnet_name}-dns-nsg"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  security_rule {
    name                       = "DNS"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "dns" {
  subnet_id                 = azurerm_subnet.dns.id
  network_security_group_id = azurerm_network_security_group.dns.id
}