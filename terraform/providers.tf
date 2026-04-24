terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.9.0"
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
  skip_provider_registration = true
}

provider "azapi" {
  subscription_id = var.subscription_id
}