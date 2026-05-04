# ============================================================
# providers.tf
# Defines which cloud providers Terraform will manage and how
# Terraform itself is configured.
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    key_vault {
      # If a Key Vault is destroyed, allow purge instead of soft-delete-only
      purge_soft_delete_on_destroy = false
      recover_soft_deleted_key_vaults = true
    }
  }
}