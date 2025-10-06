# Service Bus Namespace for Hybrid Connections
resource "azurerm_servicebus_namespace" "hybrid" {
  name                = "sb-${local.app_name}-${local.environment}-hybrid"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  capacity            = 0

  tags = local.common_tags
}

# Hybrid Connection for SQL Server
resource "azurerm_servicebus_hybrid_connection" "sql" {
  name                = "sql-hybrid-connection"
  resource_group_name = azurerm_resource_group.main.name
  servicebus_namespace_name = azurerm_servicebus_namespace.hybrid.name

  # This should point to your on-premises SQL Server
  endpoint_host = var.on_prem_sql_server.server_name
  endpoint_port = var.on_prem_sql_server.port

  requires_client_authorization = true
}

# Authorization rule for the hybrid connection
resource "azurerm_servicebus_hybrid_connection_authorization_rule" "sql" {
  name                    = "RootManageSharedAccessKey"
  hybrid_connection_name  = azurerm_servicebus_hybrid_connection.sql.name
  namespace_name          = azurerm_servicebus_namespace.hybrid.name
  resource_group_name     = azurerm_resource_group.main.name

  listen = true
  send   = true
  manage = true
}

# Key Vault for storing connection strings securely (PCI compliant)
resource "azurerm_key_vault" "main" {
  name                = "kv-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # PCI compliance settings
  soft_delete_retention_days = 90  # Extended retention for compliance
  purge_protection_enabled   = true # Prevent permanent deletion
  public_network_access_enabled = false # Disable public access for PCI compliance

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"  # Deny all traffic by default
    virtual_network_subnet_ids = [azurerm_subnet.private_endpoints.id]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get", "List", "Create", "Delete", "Update"
    ]

    secret_permissions = [
      "Get", "List", "Set", "Delete"
    ]
  }

  # Access policy for Function App managed identity
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_windows_function_app.main.identity[0].principal_id

    secret_permissions = [
      "Get", "List"
    ]
  }

  tags = local.common_tags
}

data "azurerm_client_config" "current" {}

# Store the hybrid connection string in Key Vault
resource "azurerm_key_vault_secret" "hybrid_connection_string" {
  name         = "hybrid-sql-connection-string"
  value        = azurerm_servicebus_hybrid_connection_authorization_rule.sql.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

# Store the SQL connection string template in Key Vault
resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "sql-connection-string"
  value        = "Server=${var.on_prem_sql_server.server_name},${var.on_prem_sql_server.port};Database=${var.on_prem_sql_server.database_name};Integrated Security=true;TrustServerCertificate=true;"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

# VNet Integration for Function App to access Key Vault
resource "azurerm_app_service_virtual_network_swift_connection" "function_app" {
  app_service_id = azurerm_windows_function_app.main.id
  subnet_id      = azurerm_subnet.hybrid.id
}

# Update Function App settings to include Key Vault references
resource "azurerm_windows_function_app_slot" "staging" {
  name            = "staging"
  function_app_id = azurerm_windows_function_app.main.id

  site_config {
    always_on = true

    application_stack {
      dotnet_version = "v8.0"
    }

    vnet_route_all_enabled = true
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "dotnet"
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    "HybridConnectionString" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.hybrid_connection_string.id})"
    "SqlConnectionString" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.sql_connection_string.id})"
  }

  tags = local.common_tags
}