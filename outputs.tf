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