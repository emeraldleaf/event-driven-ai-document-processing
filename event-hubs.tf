# Event Hubs Namespace for high-throughput event streaming
resource "azurerm_eventhub_namespace" "main" {
  name                = "eh-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Premium"
  capacity            = 1
  zone_redundant      = true

  auto_inflate_enabled     = true
  maximum_throughput_units = 10

  local_authentication_enabled  = false
  public_network_access_enabled = false
  minimum_tls_version          = "1.2"

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Event Hub for Domain Events (Event Sourcing)
resource "azurerm_eventhub" "domain_events" {
  name                = "domain-events"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = 8
  message_retention   = 7 # 7 days retention

  capture_description {
    enabled  = true
    encoding = "Avro"

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.eventhub_capture.name
      storage_account_id  = azurerm_storage_account.event_store.id
    }

    interval_in_seconds = 300 # 5 minutes
    size_limit_in_bytes = 314572800 # 300 MB
  }
}

# Event Hub for Telemetry and Metrics
resource "azurerm_eventhub" "telemetry" {
  name                = "telemetry"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = 16
  message_retention   = 1 # 1 day retention for telemetry

  capture_description {
    enabled  = true
    encoding = "Avro"

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.telemetry_capture.name
      storage_account_id  = azurerm_storage_account.event_store.id
    }

    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
  }
}

# Event Hub for Audit Logs (Long-term retention)
resource "azurerm_eventhub" "audit_logs" {
  name                = "audit-logs"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = 4
  message_retention   = 7

  capture_description {
    enabled  = true
    encoding = "Avro"

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.audit_capture.name
      storage_account_id  = azurerm_storage_account.event_store.id
    }

    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
  }
}

# Consumer Group for Analytics Processing
resource "azurerm_eventhub_consumer_group" "analytics" {
  name                = "analytics-processor"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.domain_events.name
  resource_group_name = azurerm_resource_group.main.name
}

# Consumer Group for Real-time Processing
resource "azurerm_eventhub_consumer_group" "realtime" {
  name                = "realtime-processor"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.domain_events.name
  resource_group_name = azurerm_resource_group.main.name
}

# Consumer Group for Event Store Materialization
resource "azurerm_eventhub_consumer_group" "event_store" {
  name                = "event-store-materializer"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.domain_events.name
  resource_group_name = azurerm_resource_group.main.name
}

# Storage Account for Event Hub Capture and Event Store
resource "azurerm_storage_account" "event_store" {
  name                     = "st${replace(local.app_name, "-", "")}${local.environment}evt"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS" # Geo-redundant for fault tolerance
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 90
    }

    container_delete_retention_policy {
      days = 90
    }
  }

  tags = local.common_tags
}

# Storage Containers for Event Hub Capture
resource "azurerm_storage_container" "eventhub_capture" {
  name                  = "domain-events-capture"
  storage_account_name  = azurerm_storage_account.event_store.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "telemetry_capture" {
  name                  = "telemetry-capture"
  storage_account_name  = azurerm_storage_account.event_store.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "audit_capture" {
  name                  = "audit-capture"
  storage_account_name  = azurerm_storage_account.event_store.name
  container_access_type = "private"
}

# Private Endpoint for Event Hubs
resource "azurerm_private_endpoint" "eventhub" {
  name                = "pe-eh-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-eh-${local.environment}"
    private_connection_resource_id = azurerm_eventhub_namespace.main.id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-eh"
    private_dns_zone_ids = [azurerm_private_dns_zone.eventhub.id]
  }

  tags = local.common_tags
}

# Private Endpoint for Event Store Storage Account
resource "azurerm_private_endpoint" "event_store_blob" {
  name                = "pe-st-eventstore-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-st-eventstore-${local.environment}"
    private_connection_resource_id = azurerm_storage_account.event_store.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-st-eventstore"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  tags = local.common_tags
}

# Private DNS Zone for Event Hubs
resource "azurerm_private_dns_zone" "eventhub" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventhub" {
  name                  = "link-eventhub-${local.environment}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

# Private DNS Zone for Storage Blob (if not already created)
resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "link-storage-blob-${local.environment}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

# Network Rules for Event Hubs
resource "azurerm_eventhub_namespace_network_rule_set" "main" {
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name

  default_action                 = "Deny"
  public_network_access_enabled  = false
  trusted_service_access_enabled = true

  virtual_network_rule {
    subnet_id                                       = azurerm_subnet.ase.id
    ignore_missing_virtual_network_service_endpoint = false
  }
}
