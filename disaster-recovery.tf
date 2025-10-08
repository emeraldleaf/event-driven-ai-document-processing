# Recovery Services Vault for backup and disaster recovery
resource "azurerm_recovery_services_vault" "main" {
  name                = "rsv-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  soft_delete_enabled = true

  storage_mode_type = "GeoRedundant"

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Backup Policy for Virtual Machines
resource "azurerm_backup_policy_vm" "main" {
  name                = "backup-policy-vm-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name

  timezone = "Eastern Standard Time"

  backup {
    frequency = "Daily"
    time      = "02:00"
  }

  retention_daily {
    count = 30
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }

  retention_yearly {
    count    = 7
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }
}

# Azure Site Recovery for VM replication (DR)
resource "azurerm_site_recovery_fabric" "primary" {
  name                = "fabric-primary-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  location            = azurerm_resource_group.main.location
}

resource "azurerm_site_recovery_fabric" "secondary" {
  name                = "fabric-secondary-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  location            = "West US 2"
}

# Azure Backup for Storage Accounts
resource "azurerm_data_protection_backup_vault" "main" {
  name                = "bv-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  datastore_type      = "VaultStore"
  redundancy          = "GeoRedundant"

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Backup Policy for Storage Blobs
resource "azurerm_data_protection_backup_policy_blob_storage" "main" {
  name               = "backup-policy-blob-${local.environment}"
  vault_id           = azurerm_data_protection_backup_vault.main.id
  retention_duration = "P90D" # 90 days

  backup_repeating_time_intervals = [
    "R/2024-01-01T02:00:00+00:00/P1D"
  ]
}

# Role Assignment for Backup Vault to access Storage Accounts
resource "azurerm_role_assignment" "backup_vault_storage_function" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Account Backup Contributor"
  principal_id         = azurerm_data_protection_backup_vault.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "backup_vault_storage_eventstore" {
  scope                = azurerm_storage_account.event_store.id
  role_definition_name = "Storage Account Backup Contributor"
  principal_id         = azurerm_data_protection_backup_vault.main.identity[0].principal_id
}

# Traffic Manager Profile for multi-region failover
resource "azurerm_traffic_manager_profile" "main" {
  name                   = "tm-${local.app_name}-${local.environment}"
  resource_group_name    = azurerm_resource_group.main.name
  traffic_routing_method = "Priority" # Primary/Secondary failover

  dns_config {
    relative_name = "${local.app_name}-${local.environment}"
    ttl           = 30 # Fast failover
  }

  monitor_config {
    protocol                     = "HTTPS"
    port                         = 443
    path                         = "/health"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }

  tags = local.common_tags
}

# Traffic Manager Endpoint - Primary Region (Front Door)
resource "azurerm_traffic_manager_azure_endpoint" "primary" {
  name               = "endpoint-primary-${local.environment}"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target_resource_id = var.existing_front_door_id
  priority           = 1
  weight             = 100
}

# Application Gateway for regional load balancing and failover
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = local.common_tags
}

# Subnet for Application Gateway
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw-${local.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.6.0/24"]
}

resource "azurerm_application_gateway" "main" {
  name                = "appgw-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  zones               = ["1", "2", "3"]

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name  = "backend-pool-webapp"
    fqdns = [azurerm_windows_web_app.main.default_hostname]
  }

  backend_address_pool {
    name  = "backend-pool-function"
    fqdns = [azurerm_windows_function_app.main.default_hostname]
  }

  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 30
    pick_host_name_from_backend_address = true

    probe_name = "health-probe"
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool-webapp"
    backend_http_settings_name = "backend-http-settings"
    priority                   = 100
  }

  probe {
    name                                      = "health-probe"
    protocol                                  = "Https"
    path                                      = "/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }

  # Autoscale configuration
  autoscale_configuration {
    min_capacity = 2
    max_capacity = 10
  }

  tags = local.common_tags
}

# Azure Chaos Studio for chaos engineering and resilience testing
resource "azurerm_chaos_studio_target" "function_app" {
  location           = azurerm_resource_group.main.location
  target_resource_id = azurerm_windows_function_app.main.id
  target_type        = "Microsoft-AppService"
}

resource "azurerm_chaos_studio_capability" "function_app_stop" {
  chaos_studio_target_id = azurerm_chaos_studio_target.function_app.id
  capability_type        = "Stop-1.0"
}

# Storage Account Lifecycle Management for cost optimization
resource "azurerm_storage_management_policy" "event_store" {
  storage_account_id = azurerm_storage_account.event_store.id

  rule {
    name    = "archive-old-events"
    enabled = true

    filters {
      prefix_match = ["domain-events-capture/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 2555 # 7 years
      }

      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }
    }
  }

  rule {
    name    = "delete-old-telemetry"
    enabled = true

    filters {
      prefix_match = ["telemetry-capture/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 7
        delete_after_days_since_modification_greater_than       = 30
      }
    }
  }

  rule {
    name    = "archive-audit-logs"
    enabled = true

    filters {
      prefix_match = ["audit-capture/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 90
        tier_to_archive_after_days_since_modification_greater_than = 365
        delete_after_days_since_modification_greater_than          = 2555 # 7 years for compliance
      }
    }
  }
}

# Cross-region VNet Peering for DR (example)
# Uncomment and configure when secondary region is deployed
# resource "azurerm_virtual_network_peering" "primary_to_secondary" {
#   name                      = "peer-primary-to-secondary"
#   resource_group_name       = azurerm_resource_group.main.name
#   virtual_network_name      = azurerm_virtual_network.main.name
#   remote_virtual_network_id = azurerm_virtual_network.secondary.id
#   allow_forwarded_traffic   = true
#   allow_gateway_transit     = false
# }

# Azure Monitor Workbook for DR Dashboard
resource "azurerm_application_insights_workbook" "dr_dashboard" {
  name                = "workbook-dr-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "Disaster Recovery Dashboard"
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "## Disaster Recovery Monitoring Dashboard\n\nThis dashboard provides real-time visibility into the health and status of disaster recovery components."
        }
      },
      {
        type = 10
        content = {
          chartId          = "workbookmetrics"
          componentId      = azurerm_application_insights.main.id
          resourceIds      = [azurerm_application_insights.main.id]
          timeContextFromParameter = "timeRange"
          title            = "Application Health Metrics"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Output DR endpoints
output "traffic_manager_fqdn" {
  value       = azurerm_traffic_manager_profile.main.fqdn
  description = "Traffic Manager FQDN for multi-region failover"
}

output "application_gateway_public_ip" {
  value       = azurerm_public_ip.appgw.ip_address
  description = "Application Gateway public IP address"
}
