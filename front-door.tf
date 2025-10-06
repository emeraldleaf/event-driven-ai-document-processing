# Data source for existing Azure Front Door
data "azurerm_cdn_frontdoor_profile" "existing" {
  name                = split("/", var.existing_front_door_id)[8]
  resource_group_name = split("/", var.existing_front_door_id)[4]
}

# Private Endpoint connection for Azure Front Door to Function App
resource "azurerm_cdn_frontdoor_origin_group" "function_app" {
  name                     = "og-func-${local.app_name}-${local.environment}"
  cdn_frontdoor_profile_id = var.existing_front_door_id
  session_affinity_enabled = true

  health_probe {
    interval_in_seconds = 240
    path                = "/api/health"
    protocol            = "Https"
    request_type        = "GET"
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "function_app" {
  name                          = "origin-func-${local.app_name}-${local.environment}"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.function_app.id

  enabled                        = true
  host_name                      = azurerm_windows_function_app.main.default_hostname
  http_port                      = 80
  https_port                     = 443
  origin_host_header            = azurerm_windows_function_app.main.default_hostname
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true

  private_link {
    request_message        = "Request access for Azure Front Door"
    target_type           = "sites"
    location              = azurerm_resource_group.main.location
    private_link_target_id = azurerm_windows_function_app.main.id
  }
}

# Private Endpoint connection for Azure Front Door to Web App
resource "azurerm_cdn_frontdoor_origin_group" "web_app" {
  name                     = "og-app-${local.app_name}-${local.environment}"
  cdn_frontdoor_profile_id = var.existing_front_door_id
  session_affinity_enabled = true

  health_probe {
    interval_in_seconds = 240
    path                = "/health"
    protocol            = "Https"
    request_type        = "GET"
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "web_app" {
  name                          = "origin-app-${local.app_name}-${local.environment}"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.web_app.id

  enabled                        = true
  host_name                      = azurerm_windows_web_app.main.default_hostname
  http_port                      = 80
  https_port                     = 443
  origin_host_header            = azurerm_windows_web_app.main.default_hostname
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true

  private_link {
    request_message        = "Request access for Azure Front Door"
    target_type           = "sites"
    location              = azurerm_resource_group.main.location
    private_link_target_id = azurerm_windows_web_app.main.id
  }
}

# Web Application Firewall Policy for PCI Compliance
resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  name                              = "waf${replace(local.app_name, "-", "")}${local.environment}"
  resource_group_name               = azurerm_resource_group.main.name
  sku_name                         = data.azurerm_cdn_frontdoor_profile.existing.sku_name
  enabled                          = true
  mode                             = "Prevention"
  redirect_url                     = "https://www.microsoft.com/en-us/404"
  custom_block_response_status_code = 403
  custom_block_response_body        = "Access Denied - Security Policy Violation"

  # OWASP Core Rule Set for PCI compliance
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"

    override {
      rule_group_name = "SQLI"
      rule {
        rule_id = "942100"
        enabled = true
        action  = "Block"
      }
    }

    override {
      rule_group_name = "XSS"
      rule {
        rule_id = "941100"
        enabled = true
        action  = "Block"
      }
    }
  }

  # Bot protection
  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  # Rate limiting rule for DDoS protection
  custom_rule {
    name                           = "RateLimitRule"
    enabled                        = true
    priority                       = 1
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 100
    type                           = "RateLimitRule"
    action                         = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["0.0.0.0/0"]
    }
  }

  # Geo-blocking (example - adjust based on your business needs)
  custom_rule {
    name     = "GeoBlockRule"
    enabled  = false  # Enable and configure based on your requirements
    priority = 2
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "GeoMatch"
      negation_condition = false
      match_values       = ["CN", "RU"]  # Block China and Russia (example)
    }
  }

  tags = local.common_tags
}

# Security Policy to associate WAF with Front Door endpoints
resource "azurerm_cdn_frontdoor_security_policy" "main" {
  name                     = "security-policy-${local.app_name}-${local.environment}"
  cdn_frontdoor_profile_id = var.existing_front_door_id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.main.id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_origin.function_app.id
        }
        patterns_to_match = ["/*"]
      }

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_origin.web_app.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}