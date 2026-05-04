# ============================================================
# keyvault.tf
# Key Vault for secrets management. RBAC-authorized (no legacy
# access policies). Soft delete + purge protection for safety.
# ============================================================

# Get current Azure AD tenant info for Key Vault config
data "azurerm_client_config" "current" {}

# ------------------------------------------------------------
# Key Vault - stores Event Hub connection string
# ------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"

  # RBAC instead of legacy access policies
  enable_rbac_authorization = true

  # Production-grade safety settings
  soft_delete_retention_days = 90
  purge_protection_enabled   = false  # set to true in prod; blocks purge for compliance

  tags = local.common_tags
}