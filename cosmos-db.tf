# Cosmos DB Account with multi-region write and automatic failover
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Enable automatic failover
  automatic_failover_enabled = true
  multiple_write_locations_enabled = true

  # Consistency level for event sourcing
  consistency_policy {
    consistency_level       = "Session" # Good balance for event sourcing
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  # Primary region
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
    zone_redundant    = true
  }

  # Secondary region for disaster recovery
  geo_location {
    location          = "West US 2"
    failover_priority = 1
    zone_redundant    = true
  }

  # Third region for read replicas
  geo_location {
    location          = "Central US"
    failover_priority = 2
    zone_redundant    = false
  }

  # Backup configuration
  backup {
    type                = "Continuous"
    interval_in_minutes = 240
    retention_in_hours  = 720 # 30 days
  }

  # Advanced threat protection
  analytical_storage_enabled = true

  # Network security
  public_network_access_enabled = false
  is_virtual_network_filter_enabled = true

  virtual_network_rule {
    id                                   = azurerm_subnet.ase.id
    ignore_missing_vnet_service_endpoint = false
  }

  virtual_network_rule {
    id                                   = azurerm_subnet.private_endpoints.id
    ignore_missing_vnet_service_endpoint = false
  }

  # Capabilities
  capabilities {
    name = "EnableServerless"
  }

  capabilities {
    name = "EnableAggregationPipeline"
  }

  capabilities {
    name = "EnablePartialUniqueIndex"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# SQL Database for Event Store
resource "azurerm_cosmosdb_sql_database" "event_store" {
  name                = "EventStore"
  resource_group_name = azurerm_cosmosdb_account.main.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name

  autoscale_settings {
    max_throughput = 4000
  }
}

# Container for Domain Events
resource "azurerm_cosmosdb_sql_container" "domain_events" {
  name                  = "DomainEvents"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.event_store.name
  partition_key_path    = "/aggregateId"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 4000
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }

  # Time-to-live for automatic cleanup
  default_ttl = -1 # Never expire events

  # Change feed for event replay
  analytical_storage_ttl = -1 # Keep in analytical storage indefinitely

  unique_key {
    paths = ["/aggregateId", "/eventId"]
  }
}

# Container for Aggregate Snapshots
resource "azurerm_cosmosdb_sql_container" "snapshots" {
  name                  = "Snapshots"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.event_store.name
  partition_key_path    = "/aggregateId"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 1000
  }

  # Keep only recent snapshots
  default_ttl = 2592000 # 30 days
}

# Container for Read Models (CQRS)
resource "azurerm_cosmosdb_sql_container" "read_models" {
  name                  = "ReadModels"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.event_store.name
  partition_key_path    = "/entityType"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 4000
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    composite_index {
      index {
        path  = "/entityType"
        order = "ascending"
      }

      index {
        path  = "/createdAt"
        order = "descending"
      }
    }
  }
}

# SQL Database for Application Data
resource "azurerm_cosmosdb_sql_database" "application" {
  name                = "Application"
  resource_group_name = azurerm_cosmosdb_account.main.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name

  autoscale_settings {
    max_throughput = 4000
  }
}

# Container for Session State
resource "azurerm_cosmosdb_sql_container" "session_state" {
  name                  = "SessionState"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.application.name
  partition_key_path    = "/sessionId"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 1000
  }

  # Auto-expire sessions after 24 hours
  default_ttl = 86400
}

# Container for Document Metadata
resource "azurerm_cosmosdb_sql_container" "documents" {
  name                  = "Documents"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.application.name
  partition_key_path    = "/uploadDate"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 4000
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }

    # Composite index for common queries
    composite_index {
      index {
        path  = "/uploadDate"
        order = "descending"
      }

      index {
        path  = "/status"
        order = "ascending"
      }
    }

    composite_index {
      index {
        path  = "/userId"
        order = "ascending"
      }

      index {
        path  = "/uploadDate"
        order = "descending"
      }
    }
  }

  # Keep documents for configured retention period
  default_ttl = var.document_retention_days * 86400

  unique_key {
    paths = ["/blobUrl"]
  }
}

# Container for Extracted Data
resource "azurerm_cosmosdb_sql_container" "extracted_data" {
  name                  = "ExtractedData"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.application.name
  partition_key_path    = "/documentId"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 4000
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }

    # Index for full-text search on extracted content
    included_path {
      path = "/extractedFields/*"
    }
  }

  # Match document retention
  default_ttl = var.document_retention_days * 86400

  unique_key {
    paths = ["/documentId"]
  }
}

# Container for Processing Jobs
resource "azurerm_cosmosdb_sql_container" "processing_jobs" {
  name                  = "ProcessingJobs"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.application.name
  partition_key_path    = "/status"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 1000
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    composite_index {
      index {
        path  = "/status"
        order = "ascending"
      }

      index {
        path  = "/createdAt"
        order = "descending"
      }
    }
  }

  # Auto-expire completed jobs after 90 days
  default_ttl = 7776000 # 90 days
}

# Private Endpoint for Cosmos DB
resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-cosmos-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-cosmos-${local.environment}"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    is_manual_connection           = false
    subresource_names              = ["Sql"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-cosmos"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos.id]
  }

  tags = local.common_tags
}

# Private DNS Zone for Cosmos DB
resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = "link-cosmos-${local.environment}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

# Role Assignment for Function App to access Cosmos DB
resource "azurerm_role_assignment" "function_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = azurerm_windows_function_app.main.identity[0].principal_id
}

# Role Assignment for Web App to access Cosmos DB
resource "azurerm_role_assignment" "webapp_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = azurerm_windows_web_app.main.identity[0].principal_id
}

# Role Assignment for Logic Apps to access Cosmos DB
resource "azurerm_role_assignment" "logic_order_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = azurerm_logic_app_standard.order_workflow.identity[0].principal_id
}
