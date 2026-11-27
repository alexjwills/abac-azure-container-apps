locals {
  location = "uksouth"
  tags = {
    project     = "abac-azure"
    managed_by  = "terraform"
    environment = var.environment
  }
}

resource "azurerm_resource_group" "abac" {
  name     = "rg-abac-${var.environment}-tf"
  location = local.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-abac-workload-${var.environment}-tf"
  resource_group_name = azurerm_resource_group.abac.name
  location            = azurerm_resource_group.abac.location
  tags                = local.tags
}

resource "azurerm_storage_account" "data" {
  #checkov:skip=CKV_AZURE_33:Queue service not used
  #checkov:skip=CKV_AZURE_59:Public network access, private endpoint planned in Project B
  #checkov:skip=CKV2_AZURE_33:Private endpoint planned in Project B
  #checkov:skip=CKV_AZURE_206:LRS is enough for short-lived lab data
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys acceptable for lab data

  name                     = "stabac${var.environment}ajwtf"
  resource_group_name      = azurerm_resource_group.abac.name
  location                 = azurerm_resource_group.abac.location
  tags                     = local.tags
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "dept" {
  #checkov:skip=CKV2_AZURE_21:Storage logging planned in Project E

  for_each              = toset(["engineering", "finance", "marketing"])
  name                  = each.value
  storage_account_id    = azurerm_storage_account.data.id
  container_access_type = "private"
}

# Admin uploads test blobs and sets index tags (Contributor can't set tags)
resource "azurerm_role_assignment" "data_blob" {
  scope                = azurerm_storage_account.data.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = var.admin_object_id
  principal_type       = "User"
}

# Blob reads allowed only where the department index tag is engineering.
# Listing isn't covered by the condition, so all blob names are visible.
resource "azurerm_role_assignment" "workload_engineering_read" {
  scope                = azurerm_storage_account.data.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'} AND NOT SubOperationMatches{'Blob.List'})
     )
     OR
     (
      @Resource[Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags:department<$key_case_sensitive$>] StringEquals 'engineering'
     )
    )
  EOT
}

resource "azurerm_container_registry" "acr" {
  #checkov:skip=CKV_AZURE_163:Image scanning via Defender planned in Project E
  #checkov:skip=CKV_AZURE_139:Premium only, revisit with private endpoints in Project B
  #checkov:skip=CKV_AZURE_164:Premium only, not needed for lab
  #checkov:skip=CKV_AZURE_165:Premium only, not needed for lab
  #checkov:skip=CKV_AZURE_166:Premium only, not needed for lab
  #checkov:skip=CKV_AZURE_167:Premium only, not needed for lab
  #checkov:skip=CKV_AZURE_233:Premium only, not needed for lab
  #checkov:skip=CKV_AZURE_237:Premium only, revisit with private endpoints in Project B

  name                = "acrabac${var.environment}ajwtf" # letters and numbers only, globally unique
  resource_group_name = azurerm_resource_group.abac.name
  location            = azurerm_resource_group.abac.location
  sku                 = "Basic"
  admin_enabled       = false # Entra auth only
  tags                = local.tags
}

resource "azurerm_role_assignment" "workload_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "me_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = var.admin_object_id
  principal_type       = "User"
}

resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-abac-${var.environment}-tf"
  resource_group_name = azurerm_resource_group.abac.name
  location            = azurerm_resource_group.abac.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_container_app_environment" "env" {
  name                       = "cae-abac-${var.environment}-tf"
  resource_group_name        = azurerm_resource_group.abac.name
  location                   = azurerm_resource_group.abac.location
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  tags                       = local.tags

  # Deletion regularly takes longer than the 30 minute default
  timeouts {
    delete = "60m"
  }
}

# The image must already be in the registry when this is created
resource "azurerm_container_app_job" "abac_test" {
  name                         = "caj-abac-test-${var.environment}-tf"
  location                     = azurerm_resource_group.abac.location
  resource_group_name          = azurerm_resource_group.abac.name
  container_app_environment_id = azurerm_container_app_environment.env.id
  replica_timeout_in_seconds   = 300
  replica_retry_limit          = 0
  tags                         = local.tags

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }

  # Pull with the managed identity, no registry password
  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.workload.id
  }

  template {
    container {
      name   = "abac-test"
      image  = "${azurerm_container_registry.acr.login_server}/abac-azure-demo:v1"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "AZURE_STORAGE_ACCOUNT"
        value = azurerm_storage_account.data.name
      }
      env {
        name  = "AZURE_CLIENT_ID" # selects the user-assigned identity for DefaultAzureCredential
        value = azurerm_user_assigned_identity.workload.client_id
      }
    }
  }

  # No reference links the job to its AcrPull role, so make the order explicit
  depends_on = [azurerm_role_assignment.workload_acr_pull]
}