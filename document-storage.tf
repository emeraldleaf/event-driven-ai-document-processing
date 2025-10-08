# Storage Account for Document Processing
resource "azurerm_storage_account" "documents" {
  name                     = "st${replace(local.app_name, "-", "")}${local.environment}docs"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "production" ? "GRS" : "LRS" # LRS for POC cost savings
  min_tls_version          = "TLS1_2"

  # Enable for large file uploads
  large_file_shares_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.environment == "production" ? 30 : 7 # Shorter retention for POC
    }

    container_delete_retention_policy {
      days = var.environment == "production" ? 30 : 7
    }

    # CORS for web upload
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "POST", "PUT"]
      allowed_origins    = ["*"] # Restrict in production
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
  }

  # Enable static website hosting for demo UI
  static_website {
    index_document     = "index.html"
    error_404_document = "404.html"
  }

  tags = local.common_tags
}

# Container for incoming documents
resource "azurerm_storage_container" "documents_incoming" {
  name                  = "documents-incoming"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# Container for processed documents
resource "azurerm_storage_container" "documents_processed" {
  name                  = "documents-processed"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# Container for failed documents
resource "azurerm_storage_container" "documents_failed" {
  name                  = "documents-failed"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# Container for web UI (static site)
resource "azurerm_storage_container" "web" {
  name                  = "$web"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "blob"
}

# Lifecycle Management Policy - Auto-archive old documents
resource "azurerm_storage_management_policy" "documents" {
  storage_account_id = azurerm_storage_account.documents.id

  rule {
    name    = "archive-processed-documents"
    enabled = true

    filters {
      prefix_match = ["documents-processed/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = var.environment == "production" ? 30 : 7
        tier_to_archive_after_days_since_modification_greater_than = var.environment == "production" ? 90 : 30
        delete_after_days_since_modification_greater_than          = var.environment == "production" ? 365 : 90
      }

      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }

  rule {
    name    = "delete-failed-documents"
    enabled = true

    filters {
      prefix_match = ["documents-failed/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.environment == "production" ? 90 : 30
      }
    }
  }
}

# Event Grid System Topic for Blob Storage Events
resource "azurerm_eventgrid_system_topic" "document_storage" {
  name                   = "egt-documents-${local.app_name}-${local.environment}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.documents.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Event Grid Subscription for Document Upload Events
resource "azurerm_eventgrid_system_topic_event_subscription" "document_created" {
  name                = "document-created-subscription"
  system_topic        = azurerm_eventgrid_system_topic.document_storage.name
  resource_group_name = azurerm_resource_group.main.name

  # Send to Service Bus Queue
  service_bus_queue_endpoint_id = azurerm_servicebus_queue.document_processing.id

  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/documents-incoming/"
    case_sensitive      = false
  }

  # Advanced filters for file types
  advanced_filter {
    string_in {
      key = "data.contentType"
      values = [
        "application/pdf",
        "image/png",
        "image/jpeg",
        "image/jpg",
        "image/tiff",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ]
    }
  }

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440 # 24 hours
  }

  advanced_filtering_on_arrays_enabled = true
}

# Private Endpoint for Document Storage (optional for production)
resource "azurerm_private_endpoint" "documents_blob" {
  count               = var.environment == "production" ? 1 : 0
  name                = "pe-st-documents-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-st-documents-${local.environment}"
    private_connection_resource_id = azurerm_storage_account.documents.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-st-documents"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  tags = local.common_tags
}

# Role Assignment - Allow Function App to access storage
resource "azurerm_role_assignment" "function_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.documents.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_windows_function_app.document_processor.identity[0].principal_id

  depends_on = [azurerm_windows_function_app.document_processor]
}

# Role Assignment - Allow Event Grid to send to Service Bus
resource "azurerm_role_assignment" "eventgrid_servicebus_sender" {
  scope                = azurerm_servicebus_queue.document_processing.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_eventgrid_system_topic.document_storage.identity[0].principal_id
}

# Output storage account details
output "document_storage_account_name" {
  value       = azurerm_storage_account.documents.name
  description = "Name of the document storage account"
}

output "document_storage_primary_blob_endpoint" {
  value       = azurerm_storage_account.documents.primary_blob_endpoint
  description = "Primary blob endpoint for document storage"
}

output "document_storage_static_website_url" {
  value       = azurerm_storage_account.documents.primary_web_endpoint
  description = "Static website URL for document upload UI"
}

output "document_storage_connection_string" {
  value       = azurerm_storage_account.documents.primary_connection_string
  description = "Connection string for local development"
  sensitive   = true
}
