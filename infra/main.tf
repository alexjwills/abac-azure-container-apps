locals {
  location = "uksouth"
  tags = {
    project    = "abac-azure"
    managed_by = "terraform"
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