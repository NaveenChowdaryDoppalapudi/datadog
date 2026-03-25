#!/usr/bin/env bash
################################################################################
# T360 Datadog Monitoring - Post-Deployment Validation
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AKS_CLUSTER="zuse1-d003-b066-aks-p1-t360-b"
DD_NAMESPACE="datadog"
PASS=0
FAIL=0
WARN=0

check() {
    local NAME="$1"
    shift
    if eval "$@" &>/dev/null; then
        echo -e "  ${GREEN}[PASS]${NC} $NAME"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} $NAME"
        ((FAIL++))
    fi
}

warn_check() {
    local NAME="$1"
    shift
    if eval "$@" &>/dev/null; then
        echo -e "  ${GREEN}[PASS]${NC} $NAME"
        ((PASS++))
    else
        echo -e "  ${YELLOW}[WARN]${NC} $NAME"
        ((WARN++))
    fi
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     T360 Datadog Monitoring - Deployment Validation        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────────────────────────
echo -e "${BLUE}1. Kubernetes Cluster${NC}"
check "kubectl connected to cluster" "kubectl cluster-info"
check "Datadog namespace exists" "kubectl get namespace $DD_NAMESPACE"

# ──────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}2. Datadog Agent Pods${NC}"
check "Datadog Agent DaemonSet running" \
    "kubectl get daemonset datadog -n $DD_NAMESPACE -o jsonpath='{.status.numberReady}' | grep -v '^0$'"
check "Cluster Agent deployment running" \
    "kubectl get deployment datadog-cluster-agent -n $DD_NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -v '^0$'"
check "No agent pods in CrashLoopBackOff" \
    "! kubectl get pods -n $DD_NAMESPACE -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' | grep -q CrashLoopBackOff"
check "All agent pods Ready" \
    "test \$(kubectl get pods -n $DD_NAMESPACE --field-selector=status.phase!=Running 2>/dev/null | tail -n +2 | wc -l) -eq 0"

# ──────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}3. Datadog Agent Health${NC}"
AGENT_POD=$(kubectl get pods -n "$DD_NAMESPACE" -l app=datadog -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$AGENT_POD" ]]; then
    check "Agent can reach Datadog intake" \
        "kubectl exec -n $DD_NAMESPACE $AGENT_POD -c agent -- agent status 2>&1 | grep -q 'API Key.*valid'"
    warn_check "Kubernetes integration running" \
        "kubectl exec -n $DD_NAMESPACE $AGENT_POD -c agent -- agent status 2>&1 | grep -qi 'kubernetes'"
    warn_check "DogStatsD listening" \
        "kubectl exec -n $DD_NAMESPACE $AGENT_POD -c agent -- agent status 2>&1 | grep -qi 'dogstatsd'"
else
    echo -e "  ${RED}[FAIL]${NC} No agent pod found to test"
    ((FAIL++))
fi

# ──────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}4. Terraform State${NC}"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/terraform"
if [[ -d "$TF_DIR" ]]; then
    cd "$TF_DIR"
    check "Terraform initialized" "test -d .terraform"
    warn_check "Terraform state exists" "terraform state list 2>/dev/null | head -1"

    MONITOR_COUNT=$(terraform state list 2>/dev/null | grep -c "datadog_monitor\|datadog_synthetics" || echo "0")
    echo -e "  ${BLUE}[INFO]${NC} Monitors in state: $MONITOR_COUNT"

    if [[ "$MONITOR_COUNT" -ge 13 ]]; then
        echo -e "  ${GREEN}[PASS]${NC} All 13+ monitors deployed"
        ((PASS++))
    else
        echo -e "  ${YELLOW}[WARN]${NC} Expected 13+ monitors, found $MONITOR_COUNT"
        ((WARN++))
    fi
fi

# ──────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}5. Kubernetes Metrics Availability${NC}"
warn_check "kube-state-metrics running" \
    "kubectl get pods -A -l app.kubernetes.io/name=kube-state-metrics --field-selector=status.phase=Running 2>/dev/null | grep -q Running"

# ──────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL + WARN))
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC} (total: $TOTAL)"

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}Deployment validation PASSED${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Install PowerShell scripts on ITP server (Items 10, 13)"
    echo "  2. Verify monitors in Datadog UI: Monitors > Manage Monitors"
    echo "  3. Check dashboard: Dashboards > T360 Production"
    echo "  4. Set up Scheduled Reports for 8 AM, 1 PM, 6 PM CST"
    exit 0
else
    echo -e "${RED}Deployment validation FAILED — review failed checks above${NC}"
    exit 1
fi
