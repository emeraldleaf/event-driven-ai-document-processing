terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.116"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {
  location = var.location
  environment = var.environment
  app_name = var.app_name

  common_tags = {
    Environment = var.environment
    Project     = var.app_name
    ManagedBy   = "terraform"
    Purpose     = "enterprise-application"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.app_name}-${local.environment}"
  location = local.location
  tags     = local.common_tags
}

# Virtual Network for ASE v3 and private endpoints
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.app_name}-${local.environment}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Subnet for ASE v3 (requires /24 or larger)
resource "azurerm_subnet" "ase" {
  name                 = "snet-ase-${local.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "Microsoft.Web.hostingEnvironments"
    service_delegation {
      name    = "Microsoft.Web/hostingEnvironments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

# Subnet for private endpoints
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-pe-${local.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Subnet for hybrid connections (for SQL Server connectivity)
resource "azurerm_subnet" "hybrid" {
  name                 = "snet-hybrid-${local.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
}

# Subnet for Azure Bastion (management access)
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"  # Must be exactly this name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.4.0/26"]      # Minimum /26 required for Bastion
}

# Subnet for management VMs (accessible via Bastion)
resource "azurerm_subnet" "management" {
  name                 = "snet-mgmt-${local.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.5.0/24"]
}