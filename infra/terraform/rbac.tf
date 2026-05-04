# ============================================================
# rbac.tf
# Role assignments enforcing least-privilege access.
# ============================================================

# Get current user's object ID for self-assignments
data "azurerm_client_config" "user" {}

# ------------------------------------------------------------
# Access Connector for Databricks Unity Catalog
# Managed Identity used for Event Hub access from Databricks
# ------------------------------------------------------------
resource "azurerm_databricks_access_connector" "main" {
  name                = local.access_connector_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# ------------------------------------------------------------
# RBAC: User as Event Hub Data Sender (producer side)
# Scoped to specific Event Hub, not namespace - blast radius minimization
# ------------------------------------------------------------
resource "azurerm_role_assignment" "user_eventhub_sender" {
  scope                = azurerm_eventhub.airline_events.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = data.azurerm_client_config.user.object_id
}

# ------------------------------------------------------------
# RBAC: Access Connector MI as Event Hub Data Receiver (consumer side)
# Same hub-level scope. Producer and consumer have different roles.
# ------------------------------------------------------------
resource "azurerm_role_assignment" "databricks_eventhub_receiver" {
  scope                = azurerm_eventhub.airline_events.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_databricks_access_connector.main.identity[0].principal_id
}

# ------------------------------------------------------------
# RBAC: User as Key Vault Secrets Officer (read + write)
# Required to populate the Event Hub connection string secret
# ------------------------------------------------------------
resource "azurerm_role_assignment" "user_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.user.object_id
}

# ------------------------------------------------------------
# RBAC: Databricks service principal as Key Vault Secrets User (read-only)
# Databricks 1st-party SP - same well-known ID across all tenants
# ------------------------------------------------------------
resource "azurerm_role_assignment" "databricks_kv_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"  # Databricks 1st-party SP
}