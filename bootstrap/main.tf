variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-tfstate-tf"
  location = "uksouth"
}

resource "azurerm_user_assigned_identity" "github_actions" {
  name                = "id-github-actions-tf"
  location            = azurerm_resource_group.tfstate.location
  resource_group_name = azurerm_resource_group.tfstate.name
}

resource "azurerm_federated_identity_credential" "github_main" {
  name                      = "github-main"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:alexjwills/abac-azure-container-apps:ref:refs/heads/main"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_actions.id
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "sttfstateajwtf"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "tfstate_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "github_actions_reader" {
  scope                = azurerm_resource_group.tfstate.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github_actions.principal_id
  principal_type       = "ServicePrincipal"
}

output "github_actions_client_id" {
  value = azurerm_user_assigned_identity.github_actions.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}