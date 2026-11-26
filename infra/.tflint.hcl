plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Lab resources are destroyed after each stage, so prevent_destroy would block clean-up
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}