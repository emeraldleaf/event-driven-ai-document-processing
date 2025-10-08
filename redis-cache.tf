# Azure Cache for Redis - Premium tier with zone redundancy
resource "azurerm_redis_cache" "main" {
  name                = "redis-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = 1
  family              = "P" # Premium
  sku_name            = "Premium"
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  # Zone redundancy for high availability
  zones = ["1", "2", "3"]

  # Redis configuration
  redis_configuration {
    enable_authentication           = true
    maxmemory_reserved             = 125
    maxmemory_delta                = 125
    maxmemory_policy               = "allkeys-lru"

    # Persistence for data durability
    rdb_backup_enabled             = true
    rdb_backup_frequency           = 60
    rdb_backup_max_snapshot_count  = 1
    rdb_storage_connection_string  = azurerm_storage_account.redis_backup.primary_blob_connection_string

    # AOF persistence for additional durability
    aof_backup_enabled = true
    aof_storage_connection_string_0 = azurerm_storage_account.redis_backup.primary_blob_connection_string
    aof_storage_connection_string_1 = azurerm_storage_account.redis_backup.secondary_blob_connection_string
  }

  # Patch schedule for maintenance
  patch_schedule {
    day_of_week    = "Sunday"
    start_hour_utc = 2
  }

  # Network security
  public_network_access_enabled = false
  replicas_per_master          = 1
  replicas_per_primary         = 1
  shard_count                  = 3 # Sharding for better performance

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Storage Account for Redis backups
resource "azurerm_storage_account" "redis_backup" {
  name                     = "st${replace(local.app_name, "-", "")}${local.environment}rdb"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }
  }

  tags = local.common_tags
}

# Private Endpoint for Redis Cache
resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-redis-${local.environment}"
    private_connection_resource_id = azurerm_redis_cache.main.id
    is_manual_connection           = false
    subresource_names              = ["redisCache"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-redis"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis.id]
  }

  tags = local.common_tags
}

# Private Endpoint for Redis Backup Storage
resource "azurerm_private_endpoint" "redis_backup_storage" {
  name                = "pe-st-redis-backup-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-st-redis-backup-${local.environment}"
    private_connection_resource_id = azurerm_storage_account.redis_backup.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "pdz-group-st-redis-backup"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  tags = local.common_tags
}

# Private DNS Zone for Redis Cache
resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "link-redis-${local.environment}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

# Redis Firewall Rules
resource "azurerm_redis_firewall_rule" "ase_subnet" {
  name                = "AllowASESubnet"
  redis_cache_name    = azurerm_redis_cache.main.name
  resource_group_name = azurerm_resource_group.main.name
  start_ip            = cidrhost(azurerm_subnet.ase.address_prefixes[0], 0)
  end_ip              = cidrhost(azurerm_subnet.ase.address_prefixes[0], -1)
}

# Redis Enterprise Geo-Replication (Optional - for multi-region)
# Uncomment if using Redis Enterprise tier
# resource "azurerm_redis_enterprise_cluster" "main" {
#   name                = "redisent-${local.app_name}-${local.environment}"
#   resource_group_name = azurerm_resource_group.main.name
#   location            = azurerm_resource_group.main.location
#   sku_name            = "Enterprise_E10-2"
#   zones               = ["1", "2", "3"]
#
#   tags = local.common_tags
# }

# Outputs for application configuration
output "redis_connection_string" {
  value       = azurerm_redis_cache.main.primary_connection_string
  sensitive   = true
  description = "Redis Cache primary connection string"
}

output "redis_hostname" {
  value       = azurerm_redis_cache.main.hostname
  description = "Redis Cache hostname"
}
