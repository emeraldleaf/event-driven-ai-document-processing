# Storage Account for Logic Apps
resource "azurerm_storage_account" "logic_apps" {
  name                     = "st${replace(local.app_name, "-", "")}${local.environment}la"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  min_tls_version          = "TLS1_2"

  tags = local.common_tags
}

# App Service Plan for Logic Apps (Standard)
resource "azurerm_service_plan" "logic_apps" {
  name                = "asp-la-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Windows"
  sku_name            = "WS1" # Workflow Standard

  tags = local.common_tags
}

# Logic App for Order Processing Workflow
resource "azurerm_logic_app_standard" "order_workflow" {
  name                       = "la-order-${local.app_name}-${local.environment}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  app_service_plan_id        = azurerm_service_plan.logic_apps.id
  storage_account_name       = azurerm_storage_account.logic_apps.name
  storage_account_access_key = azurerm_storage_account.logic_apps.primary_access_key

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "AzureWebJobsStorage"          = azurerm_storage_account.logic_apps.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.logic_apps.primary_connection_string
    "WEBSITE_CONTENTSHARE"         = "order-workflow"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key

    # Service Bus Connection
    "ServiceBus_ConnectionString" = azurerm_servicebus_namespace.main.default_primary_connection_string

    # Event Hub Connection
    "EventHub_ConnectionString" = azurerm_eventhub_namespace.main.default_primary_connection_string
  }

  site_config {
    vnet_route_all_enabled = true

    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Logic App for Error Handling and DLQ Processing
resource "azurerm_logic_app_standard" "error_handler" {
  name                       = "la-error-${local.app_name}-${local.environment}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  app_service_plan_id        = azurerm_service_plan.logic_apps.id
  storage_account_name       = azurerm_storage_account.logic_apps.name
  storage_account_access_key = azurerm_storage_account.logic_apps.primary_access_key

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "AzureWebJobsStorage"          = azurerm_storage_account.logic_apps.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.logic_apps.primary_connection_string
    "WEBSITE_CONTENTSHARE"         = "error-handler"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key

    # Service Bus Connection
    "ServiceBus_ConnectionString" = azurerm_servicebus_namespace.main.default_primary_connection_string

    # DLQ Monitor Queue
    "DLQMonitor_QueueName" = azurerm_servicebus_queue.dlq_monitor.name
  }

  site_config {
    vnet_route_all_enabled = true

    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Logic App for Notification Orchestration
resource "azurerm_logic_app_standard" "notification_orchestrator" {
  name                       = "la-notify-${local.app_name}-${local.environment}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  app_service_plan_id        = azurerm_service_plan.logic_apps.id
  storage_account_name       = azurerm_storage_account.logic_apps.name
  storage_account_access_key = azurerm_storage_account.logic_apps.primary_access_key

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "AzureWebJobsStorage"          = azurerm_storage_account.logic_apps.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.logic_apps.primary_connection_string
    "WEBSITE_CONTENTSHARE"         = "notification-orchestrator"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key

    # Service Bus Connection
    "ServiceBus_ConnectionString" = azurerm_servicebus_namespace.main.default_primary_connection_string
    "Notifications_QueueName"     = azurerm_servicebus_queue.notifications.name
  }

  site_config {
    vnet_route_all_enabled = true

    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# VNet Integration for Logic Apps
resource "azurerm_app_service_virtual_network_swift_connection" "order_workflow" {
  app_service_id = azurerm_logic_app_standard.order_workflow.id
  subnet_id      = azurerm_subnet.ase.id
}

resource "azurerm_app_service_virtual_network_swift_connection" "error_handler" {
  app_service_id = azurerm_logic_app_standard.error_handler.id
  subnet_id      = azurerm_subnet.ase.id
}

resource "azurerm_app_service_virtual_network_swift_connection" "notification_orchestrator" {
  app_service_id = azurerm_logic_app_standard.notification_orchestrator.id
  subnet_id      = azurerm_subnet.ase.id
}

# Private Endpoint for Logic Apps Storage Account
resource "azurerm_private_endpoint" "logic_apps_storage" {
  name                = "pe-st-la-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-st-la-${local.environment}"
    private_connection_resource_id = azurerm_storage_account.logic_apps.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-st-la"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  tags = local.common_tags
}

# Role Assignments for Logic Apps to access Service Bus
resource "azurerm_role_assignment" "order_workflow_servicebus" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_logic_app_standard.order_workflow.identity[0].principal_id
}

resource "azurerm_role_assignment" "error_handler_servicebus" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_logic_app_standard.error_handler.identity[0].principal_id
}

resource "azurerm_role_assignment" "notification_orchestrator_servicebus" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_logic_app_standard.notification_orchestrator.identity[0].principal_id
}

# Role Assignments for Logic Apps to access Event Hubs
resource "azurerm_role_assignment" "order_workflow_eventhub" {
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Owner"
  principal_id         = azurerm_logic_app_standard.order_workflow.identity[0].principal_id
}
