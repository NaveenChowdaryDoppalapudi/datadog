#!/usr/bin/env bash
################################################################################
# T360 Datadog Monitoring - Deployment Script
# Deploys Datadog Agent to AKS and Terraform monitors
################################################################################

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELM_DIR="$PROJECT_DIR/helm"
TF_DIR="$PROJECT_DIR/terraform"
TF_ENV_DIR="$TF_DIR/environments/production"

AKS_CLUSTER="zuse1-d003-b066-aks-p1-t360-b"
AKS_RG="zuse1-d003-b066-rgp-p1-t360-aks-b"
SUBSCRIPTION="D003-B066-ELM-Z-PRD-001"
DD_NAMESPACE="datadog"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ──────────────────────────────────────────────────────────────────────────────
# Functions
# ──────────────────────────────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

check_prerequisites() {
    log_info "Checking prerequisites..."
    local FAILED=0

    for cmd in az kubectl helm terraform; do
        if command -v "$cmd" &>/dev/null; then
            log_ok "$cmd found: $(command -v "$cmd")"
        else
            log_error "$cmd not found. Please install it first."
            FAILED=1
        fi
    done

    if [[ $FAILED -eq 1 ]]; then
        log_error "Prerequisites check failed. Aborting."
        exit 1
    fi

    # Check Azure login
    if az account show &>/dev/null; then
        log_ok "Azure CLI authenticated"
    else
        log_warn "Not logged in to Azure. Running az login..."
        az login
    fi
}

setup_aks_context() {
    log_info "Setting up AKS context..."

    az account set --subscription "$SUBSCRIPTION"
    log_ok "Subscription set to $SUBSCRIPTION"

    az aks get-credentials \
        --resource-group "$AKS_RG" \
        --name "$AKS_CLUSTER" \
        --overwrite-existing
    log_ok "kubectl context set to $AKS_CLUSTER"

    # Verify connectivity
    if kubectl cluster-info &>/dev/null; then
        log_ok "Cluster is reachable"
    else
        log_error "Cannot connect to cluster $AKS_CLUSTER"
        exit 1
    fi
}

create_datadog_secret() {
    log_info "Setting up Datadog secrets..."

    if kubectl get namespace "$DD_NAMESPACE" &>/dev/null; then
        log_ok "Namespace $DD_NAMESPACE exists"
    else
        kubectl create namespace "$DD_NAMESPACE"
        log_ok "Created namespace $DD_NAMESPACE"
    fi

    if kubectl get secret datadog-secret -n "$DD_NAMESPACE" &>/dev/null; then
        log_warn "Secret 'datadog-secret' already exists in $DD_NAMESPACE"
        read -rp "Overwrite? (y/N): " OVERWRITE
        if [[ "$OVERWRITE" != "y" && "$OVERWRITE" != "Y" ]]; then
            log_info "Keeping existing secret"
            return
        fi
        kubectl delete secret datadog-secret -n "$DD_NAMESPACE"
    fi

    read -rsp "Enter Datadog API Key: " DD_API_KEY
    echo
    read -rsp "Enter Datadog App Key: " DD_APP_KEY
    echo

    kubectl create secret generic datadog-secret \
        --from-literal=api-key="$DD_API_KEY" \
        --from-literal=app-key="$DD_APP_KEY" \
        -n "$DD_NAMESPACE"

    log_ok "Datadog secret created in $DD_NAMESPACE"
}

deploy_agent() {
    log_info "Deploying Datadog Agent to AKS..."

    # Add Helm repo
    helm repo add datadog https://helm.datadoghq.com 2>/dev/null || true
    helm repo update
    log_ok "Helm repo updated"

    # Check if already installed
    if helm status datadog -n "$DD_NAMESPACE" &>/dev/null; then
        log_warn "Datadog Helm release already exists. Upgrading..."
        helm upgrade datadog datadog/datadog \
            -f "$HELM_DIR/datadog-values.yaml" \
            -n "$DD_NAMESPACE" \
            --wait \
            --timeout 10m
        log_ok "Datadog Agent upgraded"
    else
        helm install datadog datadog/datadog \
            -f "$HELM_DIR/datadog-values.yaml" \
            -n "$DD_NAMESPACE" \
            --wait \
            --timeout 10m
        log_ok "Datadog Agent installed"
    fi

    # Wait for agent pods
    log_info "Waiting for agent pods to be ready..."
    kubectl rollout status daemonset/datadog -n "$DD_NAMESPACE" --timeout=300s
    log_ok "Datadog Agent DaemonSet is ready"

    kubectl rollout status deployment/datadog-cluster-agent -n "$DD_NAMESPACE" --timeout=300s
    log_ok "Cluster Agent is ready"

    # Show pod status
    echo ""
    kubectl get pods -n "$DD_NAMESPACE" -o wide
    echo ""
}

deploy_terraform() {
    log_info "Deploying Terraform monitors..."

    cd "$TF_DIR"

    # Check for tfvars
    if [[ ! -f "$TF_ENV_DIR/terraform.tfvars" ]]; then
        log_error "terraform.tfvars not found at $TF_ENV_DIR/terraform.tfvars"
        log_error "Copy terraform.tfvars.example and fill in your values:"
        log_error "  cp $TF_DIR/terraform.tfvars.example $TF_ENV_DIR/terraform.tfvars"
        exit 1
    fi

    # Init
    terraform init -upgrade
    log_ok "Terraform initialized"

    # Plan
    log_info "Running terraform plan..."
    terraform plan \
        -var-file="$TF_ENV_DIR/terraform.tfvars" \
        -out=tfplan

    echo ""
    read -rp "Apply this plan? (y/N): " APPLY
    if [[ "$APPLY" != "y" && "$APPLY" != "Y" ]]; then
        log_warn "Terraform apply cancelled"
        rm -f tfplan
        return
    fi

    # Apply
    terraform apply tfplan
    rm -f tfplan
    log_ok "Terraform monitors deployed"

    # Show outputs
    echo ""
    log_info "Deployed resources:"
    terraform output
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy T360 Datadog monitoring stack.

OPTIONS:
    --step <step>       Run a specific step only:
                          prereq    - Check prerequisites
                          context   - Set up AKS kubectl context
                          secret    - Create Datadog K8s secret
                          agent     - Deploy Datadog Agent (Helm)
                          terraform - Deploy monitors (Terraform)
                          all       - Run all steps (default)
    --dry-run           Show what would be done without executing
    -h, --help          Show this help

EXAMPLES:
    $0                          # Full deployment
    $0 --step agent             # Deploy agent only
    $0 --step terraform         # Deploy monitors only
    $0 --step prereq            # Check prerequisites only
EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
STEP="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --step) STEP="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) show_usage; exit 0 ;;
        *) log_error "Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       T360 Datadog Monitoring - Deployment Script          ║"
echo "║  Cluster: zuse1-d003-b066-aks-p1-t360-b                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

case "$STEP" in
    prereq)    check_prerequisites ;;
    context)   check_prerequisites; setup_aks_context ;;
    secret)    check_prerequisites; setup_aks_context; create_datadog_secret ;;
    agent)     check_prerequisites; setup_aks_context; create_datadog_secret; deploy_agent ;;
    terraform) check_prerequisites; deploy_terraform ;;
    all)
        check_prerequisites
        setup_aks_context
        create_datadog_secret
        deploy_agent
        deploy_terraform
        echo ""
        log_ok "═══════════════════════════════════════════════════"
        log_ok "  Full deployment complete!"
        log_ok "  Next steps:"
        log_ok "    1. Install ITP scripts: see scripts/powershell/"
        log_ok "    2. Import dashboard: see dashboards/"
        log_ok "    3. Run validation: bash scripts/bash/validate.sh"
        log_ok "═══════════════════════════════════════════════════"
        ;;
    *)
        log_error "Unknown step: $STEP"
        show_usage
        exit 1
        ;;
esac
