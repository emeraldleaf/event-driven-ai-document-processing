# Azure Function for Dead Letter Queue Monitoring and Processing
resource "azurerm_windows_function_app" "dlq_processor" {
  name                = "func-dlq-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  service_plan_id            = azurerm_service_plan.functions.id

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_key               = azurerm_application_insights.main.instrumentation_key

    application_stack {
      dotnet_version = "v8.0"
    }

    vnet_route_all_enabled = true

    pre_warmed_instance_count = 1
    elastic_instance_minimum  = 1
    elastic_instance_maximum  = 10
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "dotnet"
    "WEBSITE_RUN_FROM_PACKAGE" = "1"

    # Service Bus connections for DLQ monitoring
    "ServiceBus_ConnectionString" = azurerm_servicebus_namespace.main.default_primary_connection_string
    "DLQ_Monitor_Queue"           = azurerm_servicebus_queue.dlq_monitor.name

    # File Processing DLQ
    "FileProcessing_DLQ" = "${azurerm_servicebus_queue.file_processing.name}/$DeadLetterQueue"

    # Order Processing DLQ
    "OrderProcessing_DLQ" = "${azurerm_servicebus_queue.order_processing.name}/$DeadLetterQueue"

    # Notifications DLQ
    "Notifications_DLQ" = "${azurerm_servicebus_queue.notifications.name}/$DeadLetterQueue"

    # Event Grid DLQ Storage
    "EventGrid_DLQ_Container" = azurerm_storage_container.deadletter.name
    "EventGrid_DLQ_Storage"   = azurerm_storage_account.function.primary_connection_string

    # Retry policy configuration
    "DLQ_Retry_MaxAttempts"     = "5"
    "DLQ_Retry_InitialDelay_Ms" = "1000"
    "DLQ_Retry_MaxDelay_Ms"     = "60000"
    "DLQ_Retry_BackoffMultiplier" = "2"

    # Alert configuration
    "DLQ_Alert_Threshold"    = "10"
    "DLQ_Alert_Window_Minutes" = "15"

    # Cosmos DB for DLQ tracking
    "CosmosDB_Endpoint"   = azurerm_cosmosdb_account.main.endpoint
    "CosmosDB_Database"   = azurerm_cosmosdb_sql_database.application.name
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# VNet Integration for DLQ Processor
resource "azurerm_app_service_virtual_network_swift_connection" "dlq_processor" {
  app_service_id = azurerm_windows_function_app.dlq_processor.id
  subnet_id      = azurerm_subnet.ase.id
}

# Role Assignment for DLQ Processor to access Service Bus
resource "azurerm_role_assignment" "dlq_processor_servicebus" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_windows_function_app.dlq_processor.identity[0].principal_id
}

# Role Assignment for DLQ Processor to access Cosmos DB
resource "azurerm_role_assignment" "dlq_processor_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = azurerm_windows_function_app.dlq_processor.identity[0].principal_id
}

# Role Assignment for DLQ Processor to access Storage
resource "azurerm_role_assignment" "dlq_processor_storage" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_windows_function_app.dlq_processor.identity[0].principal_id
}

# Cosmos DB Container for DLQ Tracking
resource "azurerm_cosmosdb_sql_container" "dlq_tracking" {
  name                  = "DLQTracking"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.application.name
  partition_key_path    = "/queueName"
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
        path  = "/queueName"
        order = "ascending"
      }

      index {
        path  = "/failureTimestamp"
        order = "descending"
      }
    }

    composite_index {
      index {
        path  = "/retryCount"
        order = "ascending"
      }

      index {
        path  = "/failureTimestamp"
        order = "descending"
      }
    }
  }

  # Auto-expire after 90 days
  default_ttl = 7776000
}

# Container for Circuit Breaker State
resource "azurerm_cosmosdb_sql_container" "circuit_breaker" {
  name                  = "CircuitBreakerState"
  resource_group_name   = azurerm_cosmosdb_account.main.resource_group_name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.application.name
  partition_key_path    = "/serviceName"
  partition_key_version = 2

  autoscale_settings {
    max_throughput = 400
  }

  # Keep state for 24 hours
  default_ttl = 86400
}

# Update Function App with resilience configuration
resource "null_resource" "update_function_app_settings" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Note: Update your Function App code to implement the following resilience patterns:"
      echo "1. Exponential Backoff with Jitter for retries"
      echo "2. Circuit Breaker pattern for external service calls"
      echo "3. Bulkhead isolation for different workloads"
      echo "4. Timeout policies for all external calls"
      echo "5. DLQ monitoring and automatic replay for transient failures"
    EOT
  }

  depends_on = [
    azurerm_windows_function_app.main,
    azurerm_windows_function_app.dlq_processor
  ]
}

# Example Retry Policy Configuration (for documentation)
locals {
  retry_policies = {
    transient_errors = {
      max_attempts          = 5
      initial_delay_ms      = 1000
      max_delay_ms          = 60000
      backoff_multiplier    = 2
      jitter_enabled        = true
    }

    rate_limiting = {
      max_attempts          = 3
      initial_delay_ms      = 5000
      max_delay_ms          = 30000
      backoff_multiplier    = 2
      jitter_enabled        = true
    }

    timeout = {
      http_timeout_seconds  = 30
      database_timeout_seconds = 10
      cache_timeout_seconds = 5
    }
  }

  circuit_breaker_policies = {
    external_api = {
      failure_threshold     = 5
      success_threshold     = 2
      timeout_seconds       = 60
      half_open_duration_seconds = 30
    }

    database = {
      failure_threshold     = 3
      success_threshold     = 1
      timeout_seconds       = 30
      half_open_duration_seconds = 15
    }
  }

  bulkhead_policies = {
    critical_operations = {
      max_concurrent        = 100
      max_queued           = 50
    }

    background_jobs = {
      max_concurrent        = 20
      max_queued           = 100
    }
  }
}

# Output retry configuration for application reference
output "retry_policies" {
  value = local.retry_policies
  description = "Recommended retry policies for application implementation"
}

output "circuit_breaker_policies" {
  value = local.circuit_breaker_policies
  description = "Recommended circuit breaker policies for application implementation"
}

output "bulkhead_policies" {
  value = local.bulkhead_policies
  description = "Recommended bulkhead isolation policies for application implementation"
}
