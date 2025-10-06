# Storage Account for Function App (required)
resource "azurerm_storage_account" "function" {
  name                     = "st${replace(local.app_name, "-", "")}${local.environment}fn"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.common_tags
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "appi-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"

  tags = local.common_tags
}

# Azure Function App (.NET 8 on Windows)
resource "azurerm_windows_function_app" "main" {
  name                = "func-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  service_plan_id            = azurerm_service_plan.functions.id  # Use Elastic Premium plan

  site_config {
    # always_on not needed for Elastic Premium (auto-managed)
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key

    application_stack {
      dotnet_version = "v8.0"
    }

    # Enable private endpoint support and VNet integration
    vnet_route_all_enabled = true
    
    # Elastic Premium specific settings
    pre_warmed_instance_count = 1  # Always keep 1 instance warm
    elastic_instance_minimum  = 1  # Minimum instances
    elastic_instance_maximum  = 20 # Maximum instances (matches plan)
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "dotnet"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    # Hybrid connection settings (will be configured later)
    "HYBRID_CONNECTION_NAME" = "sql-hybrid-connection"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_ENABLE_SYNC_UPDATE_SITE"],
    ]
  }
}

# Azure App Service (.NET 8 on Windows)
resource "azurerm_windows_web_app" "main" {
  name                = "app-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.webapp.id  # Use Dedicated plan for Web App

  site_config {
    always_on                              = true
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key

    application_stack {
      current_stack  = "dotnet"
      dotnet_version = "v8.0"
    }

    # Enable private endpoint support
    vnet_route_all_enabled = true
  }

  app_settings = {
    "ASPNETCORE_ENVIRONMENT" = "Production"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_ENABLE_SYNC_UPDATE_SITE"],
    ]
  }
}