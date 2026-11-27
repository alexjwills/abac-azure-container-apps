terraform {
  required_version = "~> 1.17.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-tf"
    storage_account_name = "sttfstateajwtf"
    container_name       = "tfstate"
    key                  = "abac-dev.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "admin_object_id" {
  type        = string
  description = "Object ID of the admin user who uploads test data and pushes images"
}