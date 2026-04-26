from diagrams import Diagram, Cluster, Edge
from diagrams.azure.network import (
    ApplicationGateway, VirtualNetworks, Subnets,
    PublicIpAddresses, FrontDoors
)
from diagrams.azure.compute import (
    AKS, ContainerRegistries, KubernetesServices
)
from diagrams.azure.database import SQLDatabases, SQLServers
from diagrams.azure.monitor import (
    ApplicationInsights, LogAnalyticsWorkspaces, Monitor
)
from diagrams.azure.identity import ManagedIdentities, Groups, EntraManagedIdentities
from diagrams.azure.storage import StorageAccounts
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github
from diagrams.onprem.container import Docker

graph_attr = {
    "fontsize":  "14",
    "fontname":  "Helvetica",
    "bgcolor":   "white",
    "pad":       "0.85",
    "splines":   "ortho",
    "nodesep":   "0.65",
    "ranksep":   "1.0",
}

node_attr = {
    "fontsize": "11",
    "fontname": "Helvetica",
}

with Diagram(
    "Hello World — AKS Two-Tier Application",
    filename="/home/claude/aks_architecture",
    outformat="png",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    node_attr=node_attr,
):

    user   = Users("User\n(global)")
    github = Github("GitHub\n(source + CI/CD)")

    # ── CI/CD ─────────────────────────────────────────────────────────────────
    with Cluster("GitHub Actions CI/CD"):
        acr  = ContainerRegistries("Azure Container\nRegistry (ACR)")
        helm = Docker("Helm\nALB Controller")

    # ── Global entry point ────────────────────────────────────────────────────
    with Cluster("Azure — Global Edge"):
        agc = ApplicationGateway("App Gateway\nfor Containers (AGC)\nGateway API · ALB Controller")

    # ── Azure Subscription ────────────────────────────────────────────────────
    with Cluster("Azure Subscription — rg-hello-world-aks"):

        # ── Networking ────────────────────────────────────────────────────────
        with Cluster("VNet  10.1.0.0/16"):
            vnet = VirtualNetworks("vnet-hello-world-aks")

            with Cluster("agc-subnet  10.1.2.0/24"):
                agc_subnet = Subnets("AGC subnet\ndelegated to\nServiceNetworking")

            # ── AKS Cluster ───────────────────────────────────────────────────
            with Cluster("aks-subnet  10.1.1.0/24"):
                aks = AKS("AKS Cluster\naks-hello-world\nStandard_B2s × 2")

                with Cluster("Namespace: hello-world"):

                    with Cluster("Gateway API"):
                        gw      = KubernetesServices("Gateway +\nHTTPRoute")

                    with Cluster("Web tier"):
                        web_pod = KubernetesServices("Web Pod × 2\nFlask · :8000\nClusterIP svc")

                    with Cluster("API tier"):
                        api_pod = KubernetesServices("API Pod × 2\nFlask · :8000\nClusterIP svc")

                with Cluster("Namespace: azure-alb-system"):
                    alb_ctrl = KubernetesServices("ALB Controller\nprograms AGC\nvia Gateway API")

        # ── Identity ──────────────────────────────────────────────────────────
        with Cluster("Workload Identity"):
            uami     = EntraManagedIdentities("UAMI\nuami-hello-world-api\nfederated to SA")
            alb_uami = ManagedIdentities("UAMI\nuami-alb-controller\nfederated to ALB SA")
            sa       = Groups("K8s Service\nAccount\napi-service-account")

        # ── Data ─────────────────────────────────────────────────────────────
        with Cluster("Data"):
            sql_server = SQLServers("SQL Server\nSystem-assigned\nidentity")
            sql_db     = SQLDatabases("SQL Database\nBasic · 5 DTUs")

        # ── Observability ─────────────────────────────────────────────────────
        with Cluster("Observability"):
            appi_web = ApplicationInsights("App Insights\n(web)")
            appi_api = ApplicationInsights("App Insights\n(api)")
            log_ws   = LogAnalyticsWorkspaces("Log Analytics\nWorkspace")
            dtu_alert = Monitor("DTU Alert\n85% · 20 min")

        # ── Terraform state ───────────────────────────────────────────────────
        with Cluster("rg-terraform-state"):
            tf_state = StorageAccounts("Blob Storage\ntfstate-aks")

    # ── Traffic flow ──────────────────────────────────────────────────────────
    user      >> Edge(label="HTTP :80\nglobal anycast")     >> agc
    agc       >> Edge(color="black")                        >> agc_subnet
    agc_subnet >> Edge(label="routes to")                   >> gw
    gw        >> Edge(label="HTTPRoute\n/ → web")           >> web_pod
    web_pod   >> Edge(label="cluster DNS\nHTTP internal")   >> api_pod

    # ── Workload Identity → SQL ───────────────────────────────────────────────
    api_pod   >> Edge(label="uses",
                      color="darkorange",
                      style="dashed")                       >> sa
    sa        >> Edge(label="federated\nOIDC token",
                      color="darkorange",
                      style="dashed")                       >> uami
    uami      >> Edge(label="Entra token\nno password",
                      color="darkgreen",
                      style="dashed")                       >> sql_server
    sql_server >> Edge(color="gray")                        >> sql_db

    # ── ALB Controller programs AGC ───────────────────────────────────────────
    alb_ctrl  >> Edge(label="programs AGC\nvia ARM API",
                      color="purple",
                      style="dashed")                       >> agc
    alb_ctrl  >> Edge(label="uses",
                      color="purple",
                      style="dashed")                       >> alb_uami

    # ── Observability ─────────────────────────────────────────────────────────
    web_pod   >> Edge(color="orange",
                      style="dashed")                       >> appi_web
    api_pod   >> Edge(color="orange",
                      style="dashed")                       >> appi_api
    appi_web  >> Edge(color="orange",
                      style="dashed")                       >> log_ws
    appi_api  >> Edge(color="orange",
                      style="dashed")                       >> log_ws
    sql_db    >> Edge(label="DTU metric",
                      color="red",
                      style="dashed")                       >> dtu_alert

    # ── CI/CD ─────────────────────────────────────────────────────────────────
    github    >> Edge(label="docker push",
                      color="steelblue",
                      style="dashed")                       >> acr
    github    >> Edge(label="helm install\nALB Controller",
                      color="steelblue",
                      style="dashed")                       >> helm
    helm      >> Edge(color="steelblue",
                      style="dashed")                       >> alb_ctrl
    acr       >> Edge(label="AcrPull\nkubelet identity",
                      color="steelblue",
                      style="dashed")                       >> aks
    github    >> Edge(label="terraform apply",
                      color="blueviolet",
                      style="dashed")                       >> tf_state

print("AKS diagram generated successfully.")