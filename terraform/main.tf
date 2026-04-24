# ── Resource Group ────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# ── Container Registry ────────────────────────────────────────────────────────

resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
}

# ── Networking ────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "vnet-hello-world-aks"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vnet_address_space]
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_prefix]
}

resource "azurerm_subnet" "agc" {
  name                 = "agc-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.agc_subnet_prefix]

  delegation {
    name = "agc-delegation"
    service_delegation {
      name = "Microsoft.ServiceNetworking/trafficControllers"
    }
  }
}

# ── Observability ─────────────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "web" {
  name                = "appi-web-hello-world-aks"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}

resource "azurerm_application_insights" "api" {
  name                = "appi-api-hello-world-aks"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}

# ── SQL Server + Database ─────────────────────────────────────────────────────

resource "azurerm_mssql_server" "main" {
  name                         = var.sql_server_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password

  # System-assigned identity required for Entra ID directory lookups
  # (CREATE USER ... FROM EXTERNAL PROVIDER)
  identity {
    type = "SystemAssigned"
  }

  azuread_administrator {
    login_username              = var.sql_entra_admin_group_name
    object_id                   = var.sql_entra_admin_group_object_id
    azuread_authentication_only = false
  }
}

resource "azurerm_mssql_database" "main" {
  name        = var.sql_database_name
  server_id   = azurerm_mssql_server.main.id
  sku_name    = "Basic"
  max_size_gb = 2
}

# Allow Azure-internal services to reach the SQL server
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ── Workload Identity — User Assigned Managed Identity ────────────────────────

resource "azurerm_user_assigned_identity" "api" {
  name                = var.workload_identity_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

# ── AKS Cluster ───────────────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.aks_cluster_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dns_prefix          = var.aks_cluster_name

  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  default_node_pool {
    name           = "system"
    node_count     = 2
    vm_size        = "Standard_B2s"
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  web_app_routing {
    dns_zone_ids = []
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
}

# ── Grant AKS access to pull from ACR ────────────────────────────────────────

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}

# ── Application Gateway for Containers ───────────────────────────────────────

resource "azapi_resource" "agc" {
  type      = "Microsoft.ServiceNetworking/trafficControllers@2023-11-01"
  name      = "agc-hello-world"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  body = {
    properties = {}
  }
}

resource "azapi_resource" "agc_frontend" {
  type      = "Microsoft.ServiceNetworking/trafficControllers/frontends@2023-11-01"
  name      = "agc-frontend"
  location  = azurerm_resource_group.main.location
  parent_id = azapi_resource.agc.id

  body = {
    properties = {}
  }
}

resource "azapi_resource" "agc_subnet_association" {
  type      = "Microsoft.ServiceNetworking/trafficControllers/associations@2023-11-01"
  name      = "agc-subnet-association"
  location  = azurerm_resource_group.main.location
  parent_id = azapi_resource.agc.id

  body = {
    properties = {
      associationType = "subnets"
      subnet = {
        id = azurerm_subnet.agc.id
      }
    }
  }
}

# ── ALB Controller identity ───────────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "alb_controller" {
  name                = "uami-alb-controller"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

resource "azurerm_role_assignment" "alb_controller_rg" {
  principal_id         = azurerm_user_assigned_identity.alb_controller.principal_id
  role_definition_name = "AppGw for Containers Configuration Manager"
  scope                = azurerm_resource_group.main.id
}

resource "azurerm_role_assignment" "alb_controller_subnet" {
  principal_id         = azurerm_user_assigned_identity.alb_controller.principal_id
  role_definition_name = "Network Contributor"
  scope                = azurerm_subnet.agc.id
}

resource "azurerm_federated_identity_credential" "alb_controller" {
  name                = "alb-controller-federated"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.alb_controller.id
  subject             = "system:serviceaccount:azure-alb-system:alb-controller-sa"
}

# ── Workload Identity federation ──────────────────────────────────────────────

resource "azurerm_federated_identity_credential" "api" {
  name                = "api-workload-identity-federated"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.api.id
  subject             = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"
}

# ── Alerting ──────────────────────────────────────────────────────────────────

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-hello-world-aks-dtu-alert"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "aks-dtu"

  email_receiver {
    name          = "admin-email"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "dtu" {
  name                = "alert-aks-dtu-85pct"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_mssql_database.main.id]
  description         = "Fires when DTU consumption exceeds 85% for 20 minutes"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT20M"

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "dtu_consumption_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}