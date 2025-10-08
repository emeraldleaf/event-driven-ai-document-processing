# Event Grid System Topic for Storage Account Events
resource "azurerm_eventgrid_system_topic" "storage" {
  name                   = "egst-storage-${local.app_name}-${local.environment}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_storage_account.function.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Custom Event Grid Topic for Application Events
resource "azurerm_eventgrid_topic" "application_events" {
  name                = "egt-app-events-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  input_schema                  = "CloudEventSchemaV1_0"
  public_network_access_enabled = false
  local_auth_enabled            = false

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Custom Event Grid Topic for Domain Events (Event Sourcing)
resource "azurerm_eventgrid_topic" "domain_events" {
  name                = "egt-domain-events-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  input_schema                  = "CloudEventSchemaV1_0"
  public_network_access_enabled = false
  local_auth_enabled            = false

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Event Grid Subscription - Storage Blob Created Events to Service Bus
resource "azurerm_eventgrid_event_subscription" "blob_created" {
  name  = "egs-blob-created-${local.environment}"
  scope = azurerm_eventgrid_system_topic.storage.id

  service_bus_queue_endpoint_id = azurerm_servicebus_queue.file_processing.id

  included_event_types = [
    "Microsoft.Storage.BlobCreated",
  ]

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440 # 24 hours
  }

  advanced_filter {
    string_begins_with {
      key    = "subject"
      values = ["/blobServices/default/containers/uploads/"]
    }
  }
}

# Event Grid Subscription - Application Events to Azure Function
resource "azurerm_eventgrid_event_subscription" "app_events_to_function" {
  name  = "egs-app-events-func-${local.environment}"
  scope = azurerm_eventgrid_topic.application_events.id

  azure_function_endpoint {
    function_id                       = "${azurerm_windows_function_app.main.id}/functions/EventProcessor"
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 64
  }

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }

  dead_letter_identity {
    type = "SystemAssigned"
  }

  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.function.id
    storage_blob_container_name = azurerm_storage_container.deadletter.name
  }
}

# Event Grid Subscription - Domain Events to Event Hubs (Event Sourcing)
resource "azurerm_eventgrid_event_subscription" "domain_events_to_eventhub" {
  name  = "egs-domain-events-eh-${local.environment}"
  scope = azurerm_eventgrid_topic.domain_events.id

  event_hub_endpoint_id = azurerm_eventhub.domain_events.id

  retry_policy {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }
}

# Private Endpoint for Application Events Topic
resource "azurerm_private_endpoint" "eventgrid_app_events" {
  name                = "pe-egt-app-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-egt-app-${local.environment}"
    private_connection_resource_id = azurerm_eventgrid_topic.application_events.id
    is_manual_connection           = false
    subresource_names              = ["topic"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-egt-app"
    private_dns_zone_ids = [azurerm_private_dns_zone.eventgrid.id]
  }

  tags = local.common_tags
}

# Private Endpoint for Domain Events Topic
resource "azurerm_private_endpoint" "eventgrid_domain_events" {
  name                = "pe-egt-domain-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-egt-domain-${local.environment}"
    private_connection_resource_id = azurerm_eventgrid_topic.domain_events.id
    is_manual_connection           = false
    subresource_names              = ["topic"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-egt-domain"
    private_dns_zone_ids = [azurerm_private_dns_zone.eventgrid.id]
  }

  tags = local.common_tags
}

# Private DNS Zone for Event Grid
resource "azurerm_private_dns_zone" "eventgrid" {
  name                = "privatelink.eventgrid.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventgrid" {
  name                  = "link-eventgrid-${local.environment}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.eventgrid.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

# Storage Container for Dead Letter Queue
resource "azurerm_storage_container" "deadletter" {
  name                  = "deadletter"
  storage_account_name  = azurerm_storage_account.function.name
  container_access_type = "private"
}
