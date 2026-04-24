variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Main resource group name"
  type        = string
  default     = "rg-hello-world-aks"
}

variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-hello-world"
}

variable "acr_name" {
  description = "Azure Container Registry name (globally unique, alphanumeric only)"
  type        = string
}

variable "sql_server_name" {
  description = "SQL Server name (globally unique)"
  type        = string
}

variable "sql_database_name" {
  description = "SQL Database name"
  type        = string
  default     = "sqldb-hello-world-aks"
}

variable "sql_admin_login" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
}

variable "sql_entra_admin_group_name" {
  description = "Display name of the Entra security group to set as SQL Server AD admin"
  type        = string
}

variable "sql_entra_admin_group_object_id" {
  description = "Object ID of the Entra security group to set as SQL Server AD admin"
  type        = string
}

variable "workload_identity_name" {
  description = "Name of the user-assigned managed identity for Workload Identity"
  type        = string
  default     = "uami-hello-world-api"
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "hello-world"
}

variable "k8s_service_account_name" {
  description = "Kubernetes service account name for Workload Identity"
  type        = string
  default     = "api-service-account"
}

variable "log_analytics_workspace_name" {
  description = "Log Analytics workspace name"
  type        = string
  default     = "log-hello-world-aks"
}

variable "vnet_address_space" {
  description = "VNet address space"
  type        = string
  default     = "10.1.0.0/16"
}

variable "aks_subnet_prefix" {
  description = "AKS nodes subnet prefix"
  type        = string
  default     = "10.1.1.0/24"
}

variable "agc_subnet_prefix" {
  description = "Application Gateway for Containers subnet prefix"
  type        = string
  default     = "10.1.2.0/24"
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}