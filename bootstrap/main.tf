variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

data "azurerm_client_config" "current" {}

# State storage

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-tfstate-tf"
  location = "uksouth"
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

# My access to state, for local runs
resource "azurerm_role_assignment" "tfstate_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Plan identity (pull requests, read-only)

resource "azurerm_user_assigned_identity" "github_actions" {
  name                = "id-github-actions-tf"
  location            = azurerm_resource_group.tfstate.location
  resource_group_name = azurerm_resource_group.tfstate.name
}

resource "azurerm_federated_identity_credential" "github_main" {
  name                      = "github-main"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:alexjwills@327954023/abac-azure-container-apps@1457612196:ref:refs/heads/main"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_actions.id
}

resource "azurerm_federated_identity_credential" "github_pr" {
  name                      = "github-pr"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:alexjwills@327954023/abac-azure-container-apps@1457612196:pull_request"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_actions.id
}

resource "azurerm_role_assignment" "github_actions_reader" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github_actions.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_actions_state" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github_actions.principal_id
  principal_type       = "ServicePrincipal"
}

# Apply identity (production environment only)

resource "azurerm_user_assigned_identity" "github_apply" {
  name                = "id-github-apply-tf"
  location            = azurerm_resource_group.tfstate.location
  resource_group_name = azurerm_resource_group.tfstate.name
}

resource "azurerm_federated_identity_credential" "github_production" {
  name                      = "github-production"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:alexjwills@327954023/abac-azure-container-apps@1457612196:environment:production"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_apply.id
}

resource "azurerm_role_assignment" "github_apply_state" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github_apply.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_apply_contributor" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github_apply.principal_id
  principal_type       = "ServicePrincipal"
}

# Limited to the four roles infra/ assigns, so it can't grant itself Owner
resource "azurerm_role_assignment" "github_apply_rbac" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.github_apply.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {2a2b9908-6ea1-4ae2-8e65-a410df84e7d1, b7e6dc6d-f1e8-4753-8033-0f276bb0955b, 7f951dda-4ed3-4680-a7ca-43fe172d538d, 8311e382-0749-4cb8-b61a-304f252e45ec}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {2a2b9908-6ea1-4ae2-8e65-a410df84e7d1, b7e6dc6d-f1e8-4753-8033-0f276bb0955b, 7f951dda-4ed3-4680-a7ca-43fe172d538d, 8311e382-0749-4cb8-b61a-304f252e45ec}
     )
    )
  EOT
}

output "github_actions_client_id" {
  value = azurerm_user_assigned_identity.github_actions.client_id
}

output "github_apply_client_id" {
  value = azurerm_user_assigned_identity.github_apply.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}