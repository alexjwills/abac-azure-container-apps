output "identity_client_id" {
  value = azurerm_user_assigned_identity.workload.client_id
}

output "identity_principal_id" {
  value = azurerm_user_assigned_identity.workload.principal_id
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "storage_account_name" {
  value = azurerm_storage_account.data.name
}

output "resource_group_name" {
  value = azurerm_resource_group.abac.name
}