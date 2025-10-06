variable "location" {
  description = "Azure region for disaster recovery deployment"
  type        = string
  default     = "East US 2"
}

variable "environment" {
  description = "Environment name (e.g., dr, disaster-recovery)"
  type        = string
  default     = "dr"
}

variable "app_name" {
  description = "Application name for resource naming"
  type        = string
  default     = "myapp"
}

variable "existing_front_door_id" {
  description = "Resource ID of the existing Azure Front Door"
  type        = string
}

variable "on_prem_sql_server" {
  description = "On-premises SQL Server connection details"
  type = object({
    server_name   = string
    database_name = string
    port          = optional(number, 1433)
  })
}

variable "ase_pricing_tier" {
  description = "ASE v3 pricing tier"
  type        = string
  default     = "I1v2"
  validation {
    condition = contains([
      "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2",
      "I1mv2", "I2mv2", "I3mv2", "I4mv2", "I5mv2"
    ], var.ase_pricing_tier)
    error_message = "ASE pricing tier must be a valid Isolated v2 SKU."
  }
}

variable "app_service_plan_sku" {
  description = "App Service Plan SKU for ASE v3"
  type        = string
  default     = "I1v2"
  validation {
    condition = contains([
      "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2",
      "I1mv2", "I2mv2", "I3mv2", "I4mv2", "I5mv2"
    ], var.app_service_plan_sku)
    error_message = "App Service Plan SKU must be a valid Isolated v2 SKU for ASE v3."
  }
}

variable "management_vm_admin_password" {
  description = "Admin password for the management VM (use strong password for PCI compliance)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.management_vm_admin_password) >= 12
    error_message = "Management VM password must be at least 12 characters long for security compliance."
  }
}