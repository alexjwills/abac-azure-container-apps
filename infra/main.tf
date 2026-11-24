locals {
  location = "uksouth"
  tags = {
    project    = "abac-azure"
    managed_by = "terraform"
    environment = "lab"
  }
}

resource "azurerm_resource_group" "abac" {
  name     = "rg-abac-tf"
  location = local.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-abac-workload-tf"
  resource_group_name = azurerm_resource_group.abac.name
  location            = azurerm_resource_group.abac.location
  tags                = local.tags
}

output "identity_client_id" {
  value = azurerm_user_assigned_identity.workload.client_id
}

output "identity_principal_id" {
  value = azurerm_user_assigned_identity.workload.principal_id
}

data "azurerm_client_config" "current" {}

resource "azurerm_storage_account" "data" {
  name                     = "stabacdataajwtf"
  resource_group_name      = azurerm_resource_group.abac.name
  location                 = azurerm_resource_group.abac.location
  tags                     = local.tags
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "dept" {
  for_each              = toset(["engineering", "finance", "marketing"])
  name                  = each.value
  storage_account_id    = azurerm_storage_account.data.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "data_blob" {
  scope                = azurerm_storage_account.data.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

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

# The registry: where the image is stored. Like ECR.
resource "azurerm_container_registry" "acr" {
  name                = "acrabacajwtf" # letters and numbers only, globally unique
  resource_group_name = azurerm_resource_group.abac.name
  location            = azurerm_resource_group.abac.location
  sku                 = "Basic"
  admin_enabled       = false # no admin username and password: Entra only
  tags                = local.tags
}

# The workload identity can pull images from this registry only.
resource "azurerm_role_assignment" "workload_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
  principal_type       = "ServicePrincipal"
}

# You can push images to this registry.
resource "azurerm_role_assignment" "me_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Where logs go. Like a CloudWatch log group, but queryable with KQL.
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-abac-tf"
  resource_group_name = azurerm_resource_group.abac.name
  location            = azurerm_resource_group.abac.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# The environment that jobs run in, sending its logs to the workspace. Like an ECS cluster.
resource "azurerm_container_app_environment" "env" {
  name                       = "cae-abac-tf"
  resource_group_name        = azurerm_resource_group.abac.name
  location                   = azurerm_resource_group.abac.location
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  tags                       = local.tags
  timeouts {
    delete = "60m"
  }
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

resource "azurerm_container_app_job" "abac_test" {
  name                         = "caj-abac-test-tf"
  location                     = azurerm_resource_group.abac.location
  resource_group_name          = azurerm_resource_group.abac.name
  container_app_environment_id = azurerm_container_app_environment.env.id # runs in your environment
  replica_timeout_in_seconds   = 300
  replica_retry_limit          = 0 # fail once, don't retry
  tags                         = local.tags

  # Started by hand, like ECS run-task.
  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  # The job runs as your managed identity. Like an ECS task role.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }

  # Pull the image using the same identity (its AcrPull role). No registry password.
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
        name  = "AZURE_CLIENT_ID" # which identity DefaultAzureCredential uses
        value = azurerm_user_assigned_identity.workload.client_id
      }
    }
  }

  depends_on = [azurerm_role_assignment.workload_acr_pull]
}