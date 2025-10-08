output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "virtual_network_id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "ase_name" {
  description = "The name of the App Service Environment v3"
  value       = azurerm_app_service_environment_v3.main.name
}

output "ase_dns_suffix" {
  description = "The DNS suffix for the ASE v3"
  value       = azurerm_app_service_environment_v3.main.dns_suffix
}

output "function_app_name" {
  description = "The name of the Function App"
  value       = azurerm_windows_function_app.main.name
}

output "function_app_hostname" {
  description = "The default hostname of the Function App"
  value       = azurerm_windows_function_app.main.default_hostname
}

output "web_app_name" {
  description = "The name of the Web App"
  value       = azurerm_windows_web_app.main.name
}

output "web_app_hostname" {
  description = "The default hostname of the Web App"
  value       = azurerm_windows_web_app.main.default_hostname
}

output "private_endpoint_function_ip" {
  description = "The private IP address of the Function App private endpoint"
  value       = azurerm_private_endpoint.function_app.private_service_connection[0].private_ip_address
}

output "private_endpoint_webapp_ip" {
  description = "The private IP address of the Web App private endpoint"
  value       = azurerm_private_endpoint.web_app.private_service_connection[0].private_ip_address
}

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "servicebus_namespace_name" {
  description = "The name of the Service Bus namespace for hybrid connections"
  value       = azurerm_servicebus_namespace.hybrid.name
}

output "hybrid_connection_name" {
  description = "The name of the hybrid connection"
  value       = azurerm_servicebus_hybrid_connection.sql.name
}

output "function_app_plan_name" {
  description = "The name of the Elastic Premium plan for Functions"
  value       = azurerm_service_plan.functions.name
}

output "web_app_plan_name" {
  description = "The name of the Dedicated plan for Web App"
  value       = azurerm_service_plan.webapp.name
}

output "function_app_plan_sku" {
  description = "The SKU of the Function App hosting plan"
  value       = azurerm_service_plan.functions.sku_name
}

# Event-Driven Architecture Outputs

output "servicebus_namespace_id" {
  description = "The ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "servicebus_namespace_hostname" {
  description = "The hostname of the Service Bus namespace"
  value       = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
}

output "eventhub_namespace_id" {
  description = "The ID of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.id
}

output "eventhub_namespace_hostname" {
  description = "The hostname of the Event Hubs namespace"
  value       = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net"
}

output "eventgrid_application_topic_endpoint" {
  description = "The endpoint of the Event Grid application events topic"
  value       = azurerm_eventgrid_topic.application_events.endpoint
  sensitive   = true
}

output "eventgrid_domain_topic_endpoint" {
  description = "The endpoint of the Event Grid domain events topic"
  value       = azurerm_eventgrid_topic.domain_events.endpoint
  sensitive   = true
}

output "cosmos_db_endpoint" {
  description = "The endpoint of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_id" {
  description = "The ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "redis_cache_hostname" {
  description = "The hostname of the Redis cache"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_cache_ssl_port" {
  description = "The SSL port of the Redis cache"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_cache_primary_key" {
  description = "The primary access key for the Redis cache"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "logic_app_order_workflow_id" {
  description = "The ID of the order workflow Logic App"
  value       = azurerm_logic_app_standard.order_workflow.id
}

output "logic_app_error_handler_id" {
  description = "The ID of the error handler Logic App"
  value       = azurerm_logic_app_standard.error_handler.id
}

output "dlq_processor_function_app_name" {
  description = "The name of the DLQ processor Function App"
  value       = azurerm_windows_function_app.dlq_processor.name
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

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

output "recovery_services_vault_name" {
  description = "The name of the Recovery Services vault"
  value       = azurerm_recovery_services_vault.main.name
}

output "application_gateway_public_ip" {
  description = "The public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "traffic_manager_fqdn" {
  description = "The FQDN of the Traffic Manager profile for multi-region failover"
  value       = azurerm_traffic_manager_profile.main.fqdn
}