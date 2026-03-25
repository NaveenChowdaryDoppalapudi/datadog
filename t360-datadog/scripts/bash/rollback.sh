#!/usr/bin/env bash
################################################################################
# T360 Datadog Monitoring - Emergency Rollback
# Removes all deployed components if issues are encountered
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DD_NAMESPACE="datadog"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/terraform"
TF_ENV_DIR="$TF_DIR/environments/production"

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║     T360 Datadog Monitoring - ROLLBACK                      ║${NC}"
echo -e "${RED}║     This will remove all deployed monitoring components     ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

read -rp "Are you sure you want to rollback? Type 'ROLLBACK' to confirm: " CONFIRM
if [[ "$CONFIRM" != "ROLLBACK" ]]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""

# ──────────────────────────────────────────────────────────────────
echo -e "${YELLOW}Step 1: Destroy Terraform resources${NC}"
if [[ -d "$TF_DIR/.terraform" ]]; then
    cd "$TF_DIR"
    if [[ -f "$TF_ENV_DIR/terraform.tfvars" ]]; then
        terraform destroy -var-file="$TF_ENV_DIR/terraform.tfvars" -auto-approve || true
        echo -e "${GREEN}  Terraform resources destroyed${NC}"
    else
        echo -e "${YELLOW}  No tfvars found, attempting destroy without vars...${NC}"
        terraform destroy -auto-approve || true
    fi
else
    echo -e "${YELLOW}  Terraform not initialized, skipping${NC}"
fi

# ──────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}Step 2: Uninstall Datadog Helm release${NC}"
if helm status datadog -n "$DD_NAMESPACE" &>/dev/null; then
    helm uninstall datadog -n "$DD_NAMESPACE" --wait
    echo -e "${GREEN}  Datadog Helm release uninstalled${NC}"
else
    echo -e "${YELLOW}  No Datadog Helm release found${NC}"
fi

# ──────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}Step 3: Clean up Kubernetes resources${NC}"
if kubectl get namespace "$DD_NAMESPACE" &>/dev/null; then
    read -rp "Delete namespace '$DD_NAMESPACE'? (y/N): " DEL_NS
    if [[ "$DEL_NS" == "y" || "$DEL_NS" == "Y" ]]; then
        kubectl delete namespace "$DD_NAMESPACE" --wait=true --timeout=120s || true
        echo -e "${GREEN}  Namespace $DD_NAMESPACE deleted${NC}"
    else
        echo -e "${YELLOW}  Namespace kept${NC}"
    fi
fi

# ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Rollback complete.${NC}"
echo ""
echo "Manual steps remaining:"
echo "  1. On ITP server, run: .\\Install-ScheduledTasks.ps1 -Uninstall"
echo "  2. Remove Azure integration in Datadog UI if no longer needed"
echo "  3. Delete Datadog API/App keys if no longer needed"
