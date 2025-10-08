# Storage Account for Document Processor Function App
resource "azurerm_storage_account" "document_functions" {
  name                     = "st${replace(local.app_name, "-", "")}${local.environment}func"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # LRS sufficient for function storage
  min_tls_version          = "TLS1_2"

  tags = local.common_tags
}

# App Service Plan for Document Processing Functions (Consumption for cost savings)
resource "azurerm_service_plan" "document_processor" {
  name                = "asp-doc-processor-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"

  # Use Consumption plan for POC (Y1), Premium (EP1) for production
  sku_name = var.enable_cost_optimization ? "Y1" : "EP1"

  tags = local.common_tags
}

# Function App for Document Processing
resource "azurerm_linux_function_app" "document_processor" {
  name                       = "func-doc-${local.app_name}-${local.environment}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.document_processor.id
  storage_account_name       = azurerm_storage_account.document_functions.name
  storage_account_access_key = azurerm_storage_account.document_functions.primary_access_key

  site_config {
    application_stack {
      python_version = "3.11"
    }

    # Enable Application Insights
    application_insights_key = azurerm_application_insights.main.instrumentation_key

    # CORS for local development
    cors {
      allowed_origins = var.environment == "production" ? [] : ["http://localhost:3000", "http://localhost:8000"]
    }

    # Function timeout
    function_app_scale_limit = var.enable_cost_optimization ? 10 : 200
    health_check_path        = "/api/health"
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "PYTHON_ISOLATE_WORKER_DEPS"     = "1"
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing"

    # Anthropic API
    "ANTHROPIC_API_KEY"              = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.anthropic_api_key.id})"

    # Azure Storage
    "DOCUMENT_STORAGE_CONNECTION"    = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.document_storage_connection.id})"
    "INCOMING_CONTAINER"             = azurerm_storage_container.documents_incoming.name
    "PROCESSED_CONTAINER"            = azurerm_storage_container.documents_processed.name
    "FAILED_CONTAINER"               = azurerm_storage_container.documents_failed.name

    # Cosmos DB
    "COSMOS_ENDPOINT"                = azurerm_cosmosdb_account.main.endpoint
    "COSMOS_DATABASE"                = azurerm_cosmosdb_sql_database.application.name
    "COSMOS_DOCUMENTS_CONTAINER"     = azurerm_cosmosdb_sql_container.documents.name
    "COSMOS_EXTRACTED_CONTAINER"     = azurerm_cosmosdb_sql_container.extracted_data.name
    "COSMOS_JOBS_CONTAINER"          = azurerm_cosmosdb_sql_container.processing_jobs.name

    # Service Bus
    "SERVICEBUS_CONNECTION"          = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.servicebus_connection.id})"
    "PROCESSING_QUEUE"               = azurerm_servicebus_queue.document_processing.name
    "COMPLETION_QUEUE"               = azurerm_servicebus_queue.document_extraction_complete.name

    # Configuration
    "MAX_DOCUMENT_SIZE_MB"           = var.max_document_size_mb
    "ENABLE_DETAILED_LOGGING"        = var.environment != "production"
    "CLAUDE_MODEL"                   = "claude-3-5-sonnet-20241022"
    "MAX_TOKENS"                     = "4096"

    # Feature Flags
    "ENABLE_MOCK_AI"                 = var.environment == "local" ? "true" : "false"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags

  depends_on = [
    azurerm_service_plan.document_processor,
    azurerm_key_vault_secret.anthropic_api_key,
    azurerm_key_vault_secret.document_storage_connection
  ]
}

# Application Insights for monitoring (if not exists)
resource "azurerm_application_insights" "main" {
  name                = "appi-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = var.enable_cost_optimization ? 30 : 90

  tags = local.common_tags
}

# Role Assignment - Function App to Cosmos DB
resource "azurerm_role_assignment" "doc_function_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = azurerm_linux_function_app.document_processor.identity[0].principal_id
}

# Role Assignment - Function App to Service Bus
resource "azurerm_role_assignment" "doc_function_servicebus_sender" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_linux_function_app.document_processor.identity[0].principal_id
}

resource "azurerm_role_assignment" "doc_function_servicebus_receiver" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_linux_function_app.document_processor.identity[0].principal_id
}

# Outputs
output "document_function_app_name" {
  value       = azurerm_linux_function_app.document_processor.name
  description = "Name of the document processing function app"
}

output "document_function_app_url" {
  value       = "https://${azurerm_linux_function_app.document_processor.default_hostname}"
  description = "URL of the document processing function app"
}

output "application_insights_instrumentation_key" {
  value       = azurerm_application_insights.main.instrumentation_key
  description = "Application Insights instrumentation key"
  sensitive   = true
}
