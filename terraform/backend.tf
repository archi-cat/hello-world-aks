terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstatefloryda"
    container_name       = "tfstate-aks"
    key                  = "hello-world-aks.tfstate"
  }
}