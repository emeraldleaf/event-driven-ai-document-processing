# Key Vault for storing secrets (Anthropic API key, connection strings, etc.)
resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.app_name}-${local.environment}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard" # Premium for HSM protection in production
  soft_delete_retention_days = 7 # Minimum for POC, 90 for production
  purge_protection_enabled   = var.environment == "production" ? true : false

  # Network restrictions
  public_network_access_enabled = var.environment == "production" ? false : true # Allow public access for POC

  network_acls {
    bypass         = "AzureServices"
    default_action = var.environment == "production" ? "Deny" : "Allow"
  }

  tags = local.common_tags
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Access Policy for current user/service principal (for Terraform)
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
    "Recover"
  ]

  certificate_permissions = [
    "Get",
    "List",
    "Create",
    "Delete"
  ]

  key_permissions = [
    "Get",
    "List",
    "Create",
    "Delete"
  ]
}

# Access Policy for Document Processor Function App
resource "azurerm_key_vault_access_policy" "document_processor" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_function_app.document_processor.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]

  depends_on = [azurerm_windows_function_app.document_processor]
}

# Access Policy for Main Function App (if needed)
resource "azurerm_key_vault_access_policy" "main_function" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_function_app.main.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# Access Policy for Web App
resource "azurerm_key_vault_access_policy" "web_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_web_app.main.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# Secret: Anthropic API Key
resource "azurerm_key_vault_secret" "anthropic_api_key" {
  name         = "anthropic-api-key"
  value        = var.anthropic_api_key
  key_vault_id = azurerm_key_vault.main.id

  content_type = "API Key"

  tags = merge(
    local.common_tags,
    {
      Purpose = "Claude API authentication"
    }
  )

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# Secret: Document Storage Connection String (for local dev)
resource "azurerm_key_vault_secret" "document_storage_connection" {
  name         = "document-storage-connection-string"
  value        = azurerm_storage_account.documents.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  content_type = "Connection String"

  tags = merge(
    local.common_tags,
    {
      Purpose = "Document storage access"
    }
  )

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# Secret: Cosmos DB Connection String
resource "azurerm_key_vault_secret" "cosmos_connection" {
  name         = "cosmos-connection-string"
  value        = azurerm_cosmosdb_account.main.primary_key
  key_vault_id = azurerm_key_vault.main.id

  content_type = "Connection String"

  tags = merge(
    local.common_tags,
    {
      Purpose = "Cosmos DB access"
    }
  )

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# Secret: Service Bus Connection String
resource "azurerm_key_vault_secret" "servicebus_connection" {
  name         = "servicebus-connection-string"
  value        = azurerm_servicebus_namespace.main.default_primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  content_type = "Connection String"

  tags = merge(
    local.common_tags,
    {
      Purpose = "Service Bus access"
    }
  )

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# Private Endpoint for Key Vault (production only)
resource "azurerm_private_endpoint" "keyvault" {
  count               = var.environment == "production" ? 1 : 0
  name                = "pe-kv-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-kv-${local.environment}"
    private_connection_resource_id = azurerm_key_vault.main.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.keyvault[0].id]
  }

  tags = local.common_tags
}

# Private DNS Zone for Key Vault (production only)
resource "azurerm_private_dns_zone" "keyvault" {
  count               = var.environment == "production" ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  count                 = var.environment == "production" ? 1 : 0
  name                  = "link-keyvault-${local.environment}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

# Outputs
output "key_vault_name" {
  value       = azurerm_key_vault.main.name
  description = "Name of the Key Vault"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.main.vault_uri
  description = "URI of the Key Vault"
}

output "anthropic_api_key_secret_id" {
  value       = azurerm_key_vault_secret.anthropic_api_key.id
  description = "Key Vault secret ID for Anthropic API key"
}
