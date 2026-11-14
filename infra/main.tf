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
