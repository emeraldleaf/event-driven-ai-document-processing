# App Service Environment v3
resource "azurerm_app_service_environment_v3" "main" {
  name                         = "ase-${local.app_name}-${local.environment}"
  resource_group_name          = azurerm_resource_group.main.name
  subnet_id                    = azurerm_subnet.ase.id
  internal_load_balancing_mode = "Web, Publishing"
  zone_redundant               = true # Enabled for high availability

  cluster_setting {
    name  = "DisableTls1.0"
    value = "1"
  }

  cluster_setting {
    name  = "InternalEncryption"
    value = "true"
  }

  tags = local.common_tags

  lifecycle {
    # ASE v3 creation takes 60-90 minutes
    create_before_destroy = false
  }
}

# Elastic Premium Plan in ASE v3 for Azure Functions
resource "azurerm_service_plan" "functions" {
  name                         = "asp-func-${local.app_name}-${local.environment}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  os_type                      = "Windows"
  sku_name                     = "EP1"  # Elastic Premium
  app_service_environment_id   = azurerm_app_service_environment_v3.main.id

  # Elastic Premium specific settings
  maximum_elastic_worker_count = 20
  zone_balancing_enabled       = true  # Match ASE zone redundancy

  tags = local.common_tags
}

# Dedicated App Service Plan in ASE v3 for Web App (SPA)
resource "azurerm_service_plan" "webapp" {
  name                         = "asp-web-${local.app_name}-${local.environment}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  os_type                      = "Windows"
  sku_name                     = var.app_service_plan_sku  # I1v2 Dedicated
  app_service_environment_id   = azurerm_app_service_environment_v3.main.id

  tags = local.common_tags
}

# Private DNS Zone for ASE
resource "azurerm_private_dns_zone" "ase" {
  name                = "${azurerm_app_service_environment_v3.main.name}.appserviceenvironment.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "ase" {
  name                  = "link-ase-${local.environment}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.ase.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = true
  tags                  = local.common_tags
}