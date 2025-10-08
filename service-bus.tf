# Service Bus Namespace with Premium tier for fault tolerance
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Premium"
  capacity            = 1
  zone_redundant      = true

  local_auth_enabled        = false
  public_network_access_enabled = false
  minimum_tls_version       = "1.2"

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Queue for File Processing with dead-lettering
resource "azurerm_servicebus_queue" "file_processing" {
  name         = "file-processing"
  namespace_id = azurerm_servicebus_namespace.main.id

  enable_partitioning = true

  # Dead letter queue configuration
  dead_lettering_on_message_expiration = true
  max_delivery_count                   = 10
  default_message_ttl                  = "P14D" # 14 days

  # Duplicate detection
  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M" # 10 minutes

  # Lock duration for processing
  lock_duration = "PT5M" # 5 minutes
}

# Queue for Order Processing
resource "azurerm_servicebus_queue" "order_processing" {
  name         = "order-processing"
  namespace_id = azurerm_servicebus_namespace.main.id

  enable_partitioning = true

  dead_lettering_on_message_expiration = true
  max_delivery_count                   = 10
  default_message_ttl                  = "P14D"

  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M"

  lock_duration = "PT5M"

  # Enable sessions for ordered message processing
  requires_session = true
}

# Queue for Notification Processing
resource "azurerm_servicebus_queue" "notifications" {
  name         = "notifications"
  namespace_id = azurerm_servicebus_namespace.main.id

  enable_partitioning = true

  dead_lettering_on_message_expiration = true
  max_delivery_count                   = 5 # Lower for notifications
  default_message_ttl                  = "P7D" # 7 days

  lock_duration = "PT2M" # 2 minutes
}

# Queue for Dead Letter Queue Processing (DLQ Monitor)
resource "azurerm_servicebus_queue" "dlq_monitor" {
  name         = "dlq-monitor"
  namespace_id = azurerm_servicebus_namespace.main.id

  enable_partitioning = true
  max_delivery_count  = 1
  default_message_ttl = "P30D" # 30 days
}

# Topic for Event Broadcasting
resource "azurerm_servicebus_topic" "domain_events" {
  name         = "domain-events"
  namespace_id = azurerm_servicebus_namespace.main.id

  enable_partitioning = true

  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M"

  default_message_ttl = "P14D"
}

# Topic Subscription for Analytics Service
resource "azurerm_servicebus_subscription" "analytics" {
  name               = "analytics-subscription"
  topic_id           = azurerm_servicebus_topic.domain_events.id
  max_delivery_count = 10

  dead_lettering_on_message_expiration      = true
  dead_lettering_on_filter_evaluation_error = true

  lock_duration = "PT5M"
}

# Topic Subscription for Audit Service
resource "azurerm_servicebus_subscription" "audit" {
  name               = "audit-subscription"
  topic_id           = azurerm_servicebus_topic.domain_events.id
  max_delivery_count = 10

  dead_lettering_on_message_expiration      = true
  dead_lettering_on_filter_evaluation_error = true

  lock_duration = "PT5M"

  # Ensure audit messages are never lost
  requires_session = true
}

# Topic Subscription for Reporting Service with SQL Filter
resource "azurerm_servicebus_subscription" "reporting" {
  name               = "reporting-subscription"
  topic_id           = azurerm_servicebus_topic.domain_events.id
  max_delivery_count = 10

  dead_lettering_on_message_expiration      = true
  dead_lettering_on_filter_evaluation_error = true

  lock_duration = "PT5M"
}

resource "azurerm_servicebus_subscription_rule" "reporting_filter" {
  name            = "reporting-events-only"
  subscription_id = azurerm_servicebus_subscription.reporting.id
  filter_type     = "SqlFilter"
  sql_filter      = "EventType IN ('OrderCreated', 'OrderCompleted', 'PaymentProcessed')"
}

# Authorization Rules for Function App
resource "azurerm_servicebus_namespace_authorization_rule" "function_app" {
  name         = "function-app-access"
  namespace_id = azurerm_servicebus_namespace.main.id

  listen = true
  send   = true
  manage = false
}

# Private Endpoint for Service Bus
resource "azurerm_private_endpoint" "servicebus" {
  name                = "pe-sb-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-sb-${local.environment}"
    private_connection_resource_id = azurerm_servicebus_namespace.main.id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-sb"
    private_dns_zone_ids = [azurerm_private_dns_zone.servicebus.id]
  }

  tags = local.common_tags
}

# Private DNS Zone for Service Bus
resource "azurerm_private_dns_zone" "servicebus" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "servicebus" {
  name                  = "link-servicebus-${local.environment}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.servicebus.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

# Network Rules for Service Bus
resource "azurerm_servicebus_namespace_network_rule_set" "main" {
  namespace_id = azurerm_servicebus_namespace.main.id

  default_action                = "Deny"
  public_network_access_enabled = false
  trusted_services_allowed      = true

  network_rules {
    subnet_id                            = azurerm_subnet.ase.id
    ignore_missing_vnet_service_endpoint = false
  }
}
