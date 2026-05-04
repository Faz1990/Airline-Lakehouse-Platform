# ============================================================
# main.tf
# Core data infrastructure: Resource Group, Event Hubs Namespace,
# Event Hub, Consumer Group.
# ============================================================

# ------------------------------------------------------------
# Local values - computed naming conventions used throughout
# ------------------------------------------------------------
locals {
  # Naming convention: {resource-type}-{project}-{env}-{region-short}
  # e.g. ehns-airline-dlt-dev-uks
  region_short = "uks"  # uksouth abbreviated

  resource_group_name      = "rg-Faiko-${var.project_name}-${var.environment}-uksouth"
  eventhub_namespace_name  = "ehns-${var.project_name}-${var.environment}-${local.region_short}"
  eventhub_name            = "airline-events"
  key_vault_name           = "kv-${var.project_name}-${var.environment}-${local.region_short}"
  access_connector_name    = "dbc-${var.project_name}-${var.environment}-uksouth"

  # Merge common tags with environment-specific tag
  common_tags = merge(var.tags, {
    environment = var.environment
    owner       = var.owner
  })
}

# ------------------------------------------------------------
# Resource Group - logical container for all project resources
# ------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# Event Hubs Namespace - container for Event Hubs
# Standard tier required for Kafka surface and consumer groups
# ------------------------------------------------------------
resource "azurerm_eventhub_namespace" "main" {
  name                = local.eventhub_namespace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  capacity            = 1

  # Kafka surface enables Kafka protocol clients (used by DLT)
  # No additional cost on Standard tier
  zone_redundant = true

  tags = local.common_tags
}

# ------------------------------------------------------------
# Event Hub - the actual stream/topic
# 4 partitions enables parallel consumer reads
# 1-day retention is sufficient for streaming + replay-from-Bronze
# ------------------------------------------------------------
resource "azurerm_eventhub" "airline_events" {
  name                = local.eventhub_name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = 4
  message_retention   = 1
}

# ------------------------------------------------------------
# Consumer Group - dedicated read position for the DLT pipeline
# Separate from $Default keeps DLT independent from other consumers
# ------------------------------------------------------------
resource "azurerm_eventhub_consumer_group" "dlt_pipeline" {
  name                = "dlt-airline"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.airline_events.name
  resource_group_name = azurerm_resource_group.main.name
}