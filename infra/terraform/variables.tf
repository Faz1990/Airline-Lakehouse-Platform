# ============================================================
# variables.tf
# Input parameters that make this configuration reusable.
# Values are supplied via terraform.tfvars or -var flags.
# ============================================================

variable "subscription_id" {
  description = "Azure subscription ID where resources will be created"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "uksouth"
}

variable "project_name" {
  description = "Project identifier used as a prefix in resource names"
  type        = string
  default     = "airline-dlt"
}

variable "owner" {
  description = "Resource owner for tagging and accountability"
  type        = string
  default     = "faisal-ahmed"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project       = "airline-dlt"
    workload_type = "streaming"
    data_domain   = "airlines"
    platform      = "databricks"
    cost_center   = "learning"
    managed_by    = "terraform"
  }
}