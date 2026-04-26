# hello-world-aks
Two-tier application deployed in AKS

Note: The github service principal will need "User Access Administrator" permissions at the subscription level for the following:

# 1. AcrPull → AKS kubelet identity on ACR
resource "azurerm_role_assignment" "aks_acr_pull" { ... }

# 2. AppGw for Containers Configuration Manager → ALB controller UAMI on resource group
resource "azurerm_role_assignment" "alb_controller_rg" { ... }

# 3. Network Contributor → ALB controller UAMI on AGC subnet
resource "azurerm_role_assignment" "alb_controller_subnet" { ... }


# Hello World — AKS Two-Tier Application

A two-tier Python web application deployed on Azure Kubernetes Service (AKS) using infrastructure-as-code and fully automated CI/CD pipelines. Built as a learning project covering AKS, Application Gateway for Containers (AGC), Workload Identity, Azure SQL Database, Application Insights, and Terraform.

![Architecture](aks_architecture.png)

---

## Architecture

```
User (global)
      │
      ▼
App Gateway for Containers (AGC) ← public entry point · Gateway API · ALB Controller
      │
      ▼
AKS Cluster (aks-hello-world)
  └── Namespace: hello-world
        ├── Gateway + HTTPRoute        ← routing rules
        ├── Web Pod × 2  (Flask)       ← renders DB status page
        └── API Pod × 2  (Flask)       ← checks SQL connectivity
                │
                │  Workload Identity (UAMI + federated service account)
                │  No passwords — Entra ID token exchange
                ▼
        Azure SQL Database (Basic, 5 DTUs)
```

Both pods push telemetry to their own Application Insights instances feeding into a shared Log Analytics workspace. A metric alert fires when DTU consumption exceeds 85% for 20 minutes.

---

## Repository structure

```
hello-world-aks/
├── app/
│   ├── web/                              # Flask web app
│   │   ├── app.py                        # Calls API, renders DB status page
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── api/                              # Flask API
│       ├── app.py                        # Checks SQL DB connection via Workload Identity
│       ├── requirements.txt
│       └── Dockerfile                    # Includes Microsoft ODBC Driver 18
├── terraform/
│   ├── main.tf                           # All Azure resources
│   ├── variables.tf                      # Input variable declarations
│   ├── outputs.tf                        # Cluster name, identity IDs, App Insights strings
│   ├── backend.tf                        # Azure Blob Storage remote state
│   └── terraform.tfvars                  # Your values — gitignored, never commit
├── k8s/
│   ├── namespace.yaml                    # hello-world namespace
│   ├── serviceaccount.yaml               # Workload Identity service account
│   ├── web-deployment.yaml               # Web pod deployment
│   ├── web-service.yaml                  # Web ClusterIP service
│   ├── api-deployment.yaml               # API pod deployment
│   ├── api-service.yaml                  # API ClusterIP service
│   ├── gateway.yaml                      # AGC Gateway resource
│   └── httproute.yaml                    # AGC HTTPRoute routing rules
├── scripts/
│   └── Set-AksWorkloadIdentity.ps1       # Grants UAMI least-privilege DB access
└── .github/
    └── workflows/
        ├── infra.yml                     # Terraform plan + apply + ALB Controller install
        └── deploy.yml                    # Docker build, push, k8s apply, SQL setup
```

---

## Key design decisions

### Application Gateway for Containers (AGC)
AGC is used instead of Application Gateway V2 + AGIC. AGC implements the Kubernetes Gateway API natively, meaning routing rules (`Gateway` and `HTTPRoute` resources) are Kubernetes-native objects managed alongside application code. The ALB Controller inside the cluster programs AGC automatically when these resources change — propagation takes seconds rather than the 30–90 seconds typical of AGIC.

### Workload Identity
The API pod authenticates to Azure SQL Database using Workload Identity — the Kubernetes-native equivalent of Managed Identity for App Service. A User-Assigned Managed Identity (UAMI) is federated to a Kubernetes Service Account via the cluster's OIDC issuer. When the API pod runs with that service account, Azure AD issues a short-lived token without any password or secret being stored anywhere.

```
API pod (service account) → OIDC token → Azure AD → UAMI token → SQL Database
                                         (no password at any point)
```

### Internal API — not exposed publicly
The API is only reachable from within the cluster via a ClusterIP service and Kubernetes internal DNS. The AGC Gateway routes only to the web service. The web pod reaches the API via `http://api.hello-world.svc.cluster.local` — traffic never leaves the cluster network to reach the API.

```
Internet → AGC → web pod → [cluster DNS] → api pod → SQL
                 ↑                          ↑
              public                     internal only
```

### Separate Terraform state
The AKS deployment uses a separate Terraform state container (`tfstate-aks`) from the App Service deployment, keeping the two deployments fully independent.

---

## Prerequisites

The following tools must be installed locally:

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) >= 2.50
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.0
- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Git](https://git-scm.com/)
- PowerShell 7+ (for the SQL setup script)

You will also need:

- An Azure subscription
- A GitHub account
- Sufficient Azure AD permissions to create service principals, security groups, and assign directory roles

---

## First-time setup

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/hello-world-aks.git
cd hello-world-aks
```

### 2. Log in to Azure

```powershell
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
$SUBSCRIPTION_ID = az account show --query id --output tsv
```

### 3. Create the Terraform state storage

If not already created from a previous deployment, create the state storage account. If reusing an existing one, just add a new container:

```powershell
# Option A — reuse existing storage account, add new container
az storage container create `
  --name tfstate-aks `
  --account-name stterraformstateyourname

# Option B — create a new storage account
az group create --name rg-terraform-state --location uksouth

az storage account create `
  --name stterraformstateyourname `
  --resource-group rg-terraform-state `
  --location uksouth `
  --sku Standard_LRS

az storage container create `
  --name tfstate-aks `
  --account-name stterraformstateyourname
```

### 4. Create the service principal

Skip this step if reusing the service principal from the App Service deployment — just add a new federated credential for this repository.

```powershell
az ad sp create-for-rbac `
  --name "sp-hello-world-github" `
  --role Contributor `
  --scopes /subscriptions/$SUBSCRIPTION_ID

# Grant role assignment permissions (required for Terraform to create role assignments)
$SP_APP_ID = az ad sp list `
  --display-name "sp-hello-world-github" `
  --query "[0].appId" --output tsv

az role assignment create `
  --assignee $SP_APP_ID `
  --role "User Access Administrator" `
  --scope /subscriptions/$SUBSCRIPTION_ID
```

### 5. Add the federated credential for this repository

```powershell
$SP_APP_ID = az ad sp list `
  --display-name "sp-hello-world-github" `
  --query "[0].appId" --output tsv

$credentialJson = @{
    name        = "github-main-aks"
    issuer      = "https://token.actions.githubusercontent.com"
    subject     = "repo:YOUR_USERNAME/hello-world-aks:ref:refs/heads/main"
    description = "GitHub Actions — hello-world-aks main branch"
    audiences   = @("api://AzureADTokenExchange")
} | ConvertTo-Json

$tempFile = New-TemporaryFile
$credentialJson | Out-File -FilePath $tempFile.FullName -Encoding utf8

az ad app federated-credential create `
  --id $SP_APP_ID `
  --parameters $tempFile.FullName

Remove-Item $tempFile.FullName
```

### 6. Create the Entra SQL admin security group

Reuse the existing group from the App Service deployment if it exists, or create a new one:

```powershell
$group = az ad group create `
  --display-name "sql-admins-hello-world" `
  --mail-nickname "sql-admins-hello-world" | ConvertFrom-Json

# Add your personal user
$myObjectId = az ad user show `
  --id you@yourdomain.com `
  --query id --output tsv
az ad group member add --group $group.id --member-id $myObjectId

# Add the service principal
$spObjectId = az ad sp list `
  --display-name "sp-hello-world-github" `
  --query "[0].id" --output tsv
az ad group member add --group $group.id --member-id $spObjectId

echo "Group ID: $($group.id)"
```

### 7. Create `terraform/terraform.tfvars`

This file is gitignored and must never be committed:

```hcl
subscription_id                 = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
location                        = "uksouth"
resource_group_name             = "rg-hello-world-aks"
aks_cluster_name                = "aks-hello-world"
acr_name                        = "acrhelloworldaksyourname"
sql_server_name                 = "sql-hello-world-aks-yourname"
sql_database_name               = "sqldb-hello-world-aks"
sql_admin_login                 = "sqladmin"
sql_admin_password              = "YourStrongPassword123!"
sql_entra_admin_group_name      = "sql-admins-hello-world"
sql_entra_admin_group_object_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
workload_identity_name          = "uami-hello-world-api"
k8s_namespace                   = "hello-world"
k8s_service_account_name        = "api-service-account"
log_analytics_workspace_name    = "log-hello-world-aks"
alert_email                     = "you@example.com"
docker_image_tag                = "latest"
```

### 8. Add GitHub Actions secrets

Go to your repository → **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal app ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `TF_STATE_RESOURCE_GROUP` | `rg-terraform-state` |
| `TF_STATE_STORAGE_ACCOUNT` | Your state storage account name |
| `TF_STATE_CONTAINER` | `tfstate-aks` |
| `ACR_NAME` | Your ACR name (e.g. `acrhelloworldaksyourname`) |
| `AKS_CLUSTER_NAME` | `aks-hello-world` |
| `AKS_RESOURCE_GROUP` | `rg-hello-world-aks` |
| `SQL_SERVER_NAME` | Your SQL server name |
| `SQL_DATABASE_NAME` | `sqldb-hello-world-aks` |
| `SQL_ADMIN_PASSWORD` | Your SQL admin password |
| `SQL_ENTRA_ADMIN_GROUP_NAME` | `sql-admins-hello-world` |
| `SQL_ENTRA_ADMIN_OBJECT_ID` | The security group object ID |
| `ALERT_EMAIL` | Email address for DTU alerts |
| `WORKLOAD_IDENTITY_CLIENT_ID` | Populated after first `terraform apply` |

---

## Deployment

### First deployment

Run the workflows in this exact order:

**1. Infrastructure pipeline**

Go to **Actions → Infrastructure — Terraform → Run workflow**

This provisions:
- Resource group, VNet, subnets
- AKS cluster (with OIDC issuer and Workload Identity enabled)
- ACR with AcrPull role for the AKS kubelet identity
- AGC with ALB Controller identity and subnet association
- UAMI for the API pod (Workload Identity)
- Federated credential linking UAMI to the Kubernetes service account
- SQL Server and SQL Database
- Log Analytics workspace, Application Insights instances
- DTU alert rule and action group

After provisioning, the pipeline also installs the ALB Controller into the cluster via Helm.

Expect 10–15 minutes. AKS cluster provisioning is the longest step.

**2. Grant Directory Readers to the SQL server identity**

This must be done manually after the infrastructure pipeline completes — the SQL server needs to resolve Entra ID objects to create external users.

```powershell
cd terraform

# Authenticate Terraform locally
$env:ARM_CLIENT_ID       = "your-client-id"
$env:ARM_TENANT_ID       = "your-tenant-id"
$env:ARM_SUBSCRIPTION_ID = "your-subscription-id"
$env:ARM_USE_OIDC        = "true"

terraform init `
  -backend-config="resource_group_name=rg-terraform-state" `
  -backend-config="storage_account_name=stterraformstateyourname" `
  -backend-config="container_name=tfstate-aks" `
  -backend-config="key=hello-world-aks.tfstate"

$SQL_PRINCIPAL_ID    = terraform output -raw sql_server_identity_principal_id
$DIR_READERS_ROLE_ID = "962940ac-7bce-4bff-b93d-48519fda4dc8"

$body     = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$SQL_PRINCIPAL_ID" } | ConvertTo-Json
$tempFile = New-TemporaryFile
$body | Out-File -FilePath $tempFile.FullName -Encoding utf8

az rest `
  --method POST `
  --uri "https://graph.microsoft.com/v1.0/directoryRoles/$DIR_READERS_ROLE_ID/members/`$ref" `
  --body "@$($tempFile.FullName)" `
  --headers "Content-Type=application/json" 2>&1

Remove-Item $tempFile.FullName
```

**3. Update the `WORKLOAD_IDENTITY_CLIENT_ID` secret**

```powershell
terraform output -raw workload_identity_client_id
```

Copy the value and save it as the `WORKLOAD_IDENTITY_CLIENT_ID` secret in GitHub.

**4. Application pipeline**

Go to **Actions → Application — Build & Deploy → Run workflow**

This:
- Builds web and API Docker images and pushes both to ACR
- Retrieves Terraform outputs (UAMI client ID, AGC frontend ID, App Insights connection strings)
- Substitutes all `${PLACEHOLDER}` values in the Kubernetes manifests using `envsubst`
- Applies manifests to the cluster in order: namespace → service account → services → deployments → Gateway → HTTPRoute
- Waits for both deployments to roll out successfully
- Runs the SQL setup script to grant the UAMI `db_datareader` and `db_datawriter`

Expect 5–8 minutes.

### Subsequent deployments

Pushes to `main` trigger pipelines automatically:

| Changed files | Pipeline triggered |
|---|---|
| `terraform/**` | Infrastructure — Terraform |
| `app/**` or `k8s/**` | Application — Build & Deploy |

---

## Verifying the deployment

Get the public IP assigned to the AGC Gateway:

```powershell
kubectl get gateway hello-world-gateway -n hello-world
```

Wait until the `ADDRESS` column shows a public IP — this can take 2–3 minutes after the manifest is applied. Then open `http://<IP>` in your browser. You should see the Hello World page with a green "Connected" database status card.

Verify individual components:

```powershell
# Check all pods are running
kubectl get pods -n hello-world

# Check services
kubectl get services -n hello-world

# Check Gateway and HTTPRoute
kubectl get gateway,httproute -n hello-world

# Check web pod logs
kubectl logs -l app=web -n hello-world --tail=50

# Check API pod logs
kubectl logs -l app=api -n hello-world --tail=50

# Check ALB Controller is healthy
kubectl get pods -n azure-alb-system
```

---

## Tearing everything down

> **Important:** Always remove the SQL server identity from Directory Readers **before** running `terraform destroy`. Skipping this step will cause a stale identity conflict on the next deployment.

```powershell
# Step 1 — remove SQL server identity from Directory Readers
cd terraform

$SQL_PRINCIPAL_ID    = terraform output -raw sql_server_identity_principal_id
$DIR_READERS_ROLE_ID = "962940ac-7bce-4bff-b93d-48519fda4dc8"

az rest `
  --method DELETE `
  --uri "https://graph.microsoft.com/v1.0/directoryRoles/$DIR_READERS_ROLE_ID/members/$SQL_PRINCIPAL_ID/`$ref"

echo "SQL server identity removed from Directory Readers."

# Step 2 — destroy all Terraform-managed resources
$env:ARM_CLIENT_ID       = "your-client-id"
$env:ARM_TENANT_ID       = "your-tenant-id"
$env:ARM_SUBSCRIPTION_ID = "your-subscription-id"
$env:ARM_USE_OIDC        = "true"

terraform destroy `
  -var="subscription_id=$(az account show --query id --output tsv)" `
  -var="acr_name=acrhelloworldaksyourname" `
  -var="sql_server_name=sql-hello-world-aks-yourname" `
  -var="sql_database_name=sqldb-hello-world-aks" `
  -var="sql_admin_password=YourStrongPassword123!" `
  -var="sql_entra_admin_group_name=sql-admins-hello-world" `
  -var="sql_entra_admin_group_object_id=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
  -var="alert_email=you@example.com"

# Step 3 — delete Terraform state storage (if no longer needed)
az group delete --name rg-terraform-state --yes --no-wait

# Step 4 — delete the service principal (if no longer needed)
$SP_APP_ID = az ad sp list `
  --display-name "sp-hello-world-github" `
  --query "[0].appId" --output tsv
az ad sp delete --id $SP_APP_ID

# Step 5 — delete the Entra security group (if no longer needed)
az ad group delete --group "sql-admins-hello-world"
```

---

## Azure resources provisioned

| Resource | Name pattern | Purpose |
|---|---|---|
| Resource Group | `rg-hello-world-aks` | Container for all AKS resources |
| Virtual Network | `vnet-hello-world-aks` | Private network — 10.1.0.0/16 |
| AKS subnet | `aks-subnet` | AKS node pool — 10.1.1.0/24 |
| AGC subnet | `agc-subnet` | AGC delegation — 10.1.2.0/24 |
| AKS Cluster | `aks-hello-world` | Kubernetes cluster — Standard_B2s × 2 |
| Container Registry | `acrhelloworldaksyourname` | Private Docker image store |
| App Gateway for Containers | `agc-hello-world` | Public HTTP entry point via Gateway API |
| UAMI (API) | `uami-hello-world-api` | Workload Identity for API pods |
| UAMI (ALB Controller) | `uami-alb-controller` | Identity for ALB Controller to program AGC |
| SQL Server | `sql-hello-world-aks-yourname` | Logical SQL server with Entra AD admin |
| SQL Database | `sqldb-hello-world-aks` | Basic tier — 5 DTUs |
| App Insights (web) | `appi-web-hello-world-aks` | Telemetry for web pods |
| App Insights (API) | `appi-api-hello-world-aks` | Telemetry for API pods |
| Log Analytics | `log-hello-world-aks` | Centralised log and metric storage |
| Metric Alert | `alert-aks-dtu-85pct` | Fires at 85% DTU for 20 minutes |
| Action Group | `ag-hello-world-aks-dtu-alert` | Email notification on DTU alert |

---

## Kubernetes resources deployed

| Resource | Namespace | Purpose |
|---|---|---|
| `Namespace` | — | `hello-world` application namespace |
| `ServiceAccount` | `hello-world` | Annotated with UAMI client ID for Workload Identity |
| `Deployment` web | `hello-world` | 2 replicas — Flask web app |
| `Service` web | `hello-world` | ClusterIP — routes traffic to web pods |
| `Deployment` api | `hello-world` | 2 replicas — Flask API |
| `Service` api | `hello-world` | ClusterIP — internal only, not exposed publicly |
| `Gateway` | `hello-world` | AGC Gateway — public HTTP listener |
| `HTTPRoute` | `hello-world` | Routes all traffic to web service |
| `Deployment` alb-controller | `azure-alb-system` | Programs AGC from Gateway API resources |

---

## Security notes

- The API authenticates to SQL Database exclusively via **Workload Identity** — no passwords in code, secrets, or environment variables
- The API pod is **not exposed publicly** — only reachable via cluster-internal DNS from the web pod
- The SQL server's Entra admin is a **security group**, not an individual account or application identity
- The UAMI is granted only `db_datareader` and `db_datawriter` — no admin rights on the database
- The SQL server has a **system-assigned identity** with Directory Readers to resolve Entra objects when creating external users
- AKS Workload Identity uses **OIDC federation** — no long-lived credentials stored in the cluster
- All GitHub Actions authentication uses **OIDC federated identity** — no client secrets stored in GitHub
- The AKS cluster uses **Azure CNI** with Azure network policy for pod-level network controls
- Terraform state is stored in **Azure Blob Storage** with Contributor-scoped access

---

## Troubleshooting

**AGC Gateway shows no ADDRESS after deployment**

The AGC frontend can take 3–5 minutes to receive a public IP after the `Gateway` manifest is applied. Check the ALB Controller logs if it takes longer:

```powershell
kubectl logs -l app=alb-controller -n azure-alb-system --tail=100
```

**API pod crashes on startup (CrashLoopBackOff)**

The ODBC driver installation in the Dockerfile requires the Microsoft package repository. Check the pod logs:

```powershell
kubectl logs -l app=api -n hello-world --tail=50
```

If the image built successfully but the pod crashes, the most common cause is a missing or incorrect `SQL_SERVER` or `SQL_DATABASE` environment variable — verify the manifest substitution worked correctly.

**Web pod shows "API unreachable"**

Verify the API service is running and the cluster DNS name is correct:

```powershell
# From inside the web pod
kubectl exec -it $(kubectl get pod -l app=web -n hello-world -o jsonpath='{.items[0].metadata.name}') \
  -n hello-world -- curl http://api.hello-world.svc.cluster.local/health
```

Expected response: `OK`

**SQL setup script fails with "Principal could not be resolved"**

The SQL server identity has not been granted Directory Readers. Follow step 2 of the first deployment sequence. Verify the assignment:

```powershell
$SQL_PRINCIPAL_ID = terraform output -raw sql_server_identity_principal_id
$response = az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SQL_PRINCIPAL_ID/memberOf"
($response | ConvertFrom-Json).value | Select-Object displayName, id
```

`Directory Readers` should appear in the output.

**Terraform fails with AuthorizationFailed on role assignments**

The service principal requires `User Access Administrator` in addition to `Contributor` to create role assignments. See the setup step 4 for the required role assignment command.

**ALB Controller Helm install fails**

Ensure the Helm OCI registry URL is correct:

```powershell
helm upgrade --install alb-controller `
  oci://mcr.microsoft.com/application-lb/charts/alb-controller `
  --namespace azure-alb-system `
  --create-namespace `
  --set albController.namespace=azure-alb-system `
  --set albController.podIdentity.clientID=YOUR_ALB_CONTROLLER_CLIENT_ID
```

---

## Generating the architecture diagram

The architecture diagram is generated using the Python `diagrams` library. To regenerate it locally:

```powershell
# Install dependencies
pip install diagrams
# Install Graphviz (required by the diagrams library)
winget install graphviz.graphviz

# Generate the diagram
python diagram_aks.py
```

This produces `aks_architecture.png` in the current directory.