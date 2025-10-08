# Core Infrastructure Outputs

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "virtual_network_id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

# Document Processing Outputs

output "document_function_app_name" {
  description = "The name of the document processing Function App"
  value       = azurerm_linux_function_app.document_processor.name
}

output "document_function_app_url" {
  description = "URL of the document processing function app"
  value       = "https://${azurerm_linux_function_app.document_processor.default_hostname}"
}

output "document_storage_account_name" {
  description = "Name of the document storage account"
  value       = azurerm_storage_account.documents.name
}

output "document_storage_primary_blob_endpoint" {
  description = "Primary blob endpoint for document storage"
  value       = azurerm_storage_account.documents.primary_blob_endpoint
}

output "document_storage_static_website_url" {
  description = "Static website URL for document upload UI"
  value       = azurerm_storage_account.documents.primary_web_endpoint
}

output "document_storage_connection_string" {
  description = "Connection string for local development"
  value       = azurerm_storage_account.documents.primary_connection_string
  sensitive   = true
}

# Key Vault Outputs

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "anthropic_api_key_secret_id" {
  description = "Key Vault secret ID for Anthropic API key"
  value       = azurerm_key_vault_secret.anthropic_api_key.id
}

# Service Bus Outputs

output "servicebus_namespace_name" {
  description = "The name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "servicebus_namespace_hostname" {
  description = "The hostname of the Service Bus namespace"
  value       = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
}

output "document_processing_queue_name" {
  description = "Name of the document processing queue"
  value       = azurerm_servicebus_queue.document_processing.name
}

# Cosmos DB Outputs

output "cosmos_db_endpoint" {
  description = "The endpoint of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_id" {
  description = "The ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.application.name
}

# Event Grid Outputs

output "document_storage_event_grid_topic_id" {
  description = "ID of the Event Grid system topic for document storage"
  value       = azurerm_eventgrid_system_topic.document_storage.id
}

# Application Insights Outputs

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Quick Start Commands

output "quick_start_local" {
  description = "Commands to run the system locally"
  value = <<-EOT

  🚀 Quick Start - Local Development:

  1. Setup environment:
     cp .env.example .env
     # Edit .env and set ENABLE_MOCK_AI=true for testing

  2. Run setup:
     ./scripts/setup-local.sh

  3. Start Functions (Terminal 1):
     cd src/functions && func start

  4. Start Web UI (Terminal 2):
     cd src/web && npm start

  5. Open: http://localhost:3000

  EOT
}

output "quick_start_azure" {
  description = "Quick start guide for Azure deployment"
  value = <<-EOT

  ☁️ Azure Deployment URLs:

  📦 Function App: https://${azurerm_linux_function_app.document_processor.default_hostname}
  🌐 Web UI: ${azurerm_storage_account.documents.primary_web_endpoint}
  🔑 Key Vault: ${azurerm_key_vault.main.vault_uri}
  📊 Cosmos DB: ${azurerm_cosmosdb_account.main.endpoint}

  📋 Next Steps:
  1. Deploy function code: func azure functionapp publish ${azurerm_linux_function_app.document_processor.name}
  2. Upload web UI to storage account: ${azurerm_storage_account.documents.name}
  3. Test upload at the Function URL above

  EOT
}
