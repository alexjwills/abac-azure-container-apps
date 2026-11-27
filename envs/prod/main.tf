module "abac" {
  source = "../../modules/abac-app"

  environment              = "prod"
  admin_object_id          = var.admin_object_id
  storage_replication_type = "ZRS"
}

output "storage_account_name" {
  value = module.abac.storage_account_name
}

output "acr_login_server" {
  value = module.abac.acr_login_server
}