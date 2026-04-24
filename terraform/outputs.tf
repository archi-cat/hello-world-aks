output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_resource_group" {
  description = "AKS resource group"
  value       = azurerm_resource_group.main.name
}

output "oidc_issuer_url" {
  description = "AKS OIDC issuer URL"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "workload_identity_client_id" {
  description = "API UAMI client ID — injected into the Kubernetes service account annotation"
  value       = azurerm_user_assigned_identity.api.client_id
}

output "workload_identity_principal_id" {
  description = "API UAMI principal ID — used to grant SQL database access"
  value       = azurerm_user_assigned_identity.api.principal_id
}

output "agc_frontend_id" {
  description = "AGC frontend resource ID — referenced in the Gateway manifest"
  value       = azapi_resource.agc_frontend.id
}

output "agc_name" {
  description = "AGC resource name"
  value       = azapi_resource.agc.name
}

output "alb_controller_identity_client_id" {
  description = "ALB Controller UAMI client ID — used when installing the ALB Controller via Helm"
  value       = azurerm_user_assigned_identity.alb_controller.client_id
}

output "acr_login_server" {
  description = "ACR login server URL"
  value       = azurerm_container_registry.main.login_server
}

output "sql_server_fqdn" {
  description = "SQL Server fully qualified domain name"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_server_identity_principal_id" {
  description = "SQL server system-assigned identity principal ID — needed for Directory Readers role"
  value       = azurerm_mssql_server.main.identity[0].principal_id
}

output "web_app_insights_connection_string" {
  description = "Web App Insights connection string"
  value       = azurerm_application_insights.web.connection_string
  sensitive   = true
}

output "api_app_insights_connection_string" {
  description = "API App Insights connection string"
  value       = azurerm_application_insights.api.connection_string
  sensitive   = true
}