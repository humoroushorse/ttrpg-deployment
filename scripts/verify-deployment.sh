#!/bin/bash
# Deployment Verification Script
# Validates that all services are deployed correctly and functioning

set -euo pipefail

# Configuration
ENV="${1:-local}"
PLATFORM_NS="platform"
SECURITY_NS="security"
APPS_NS="apps"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; PASSED_CHECKS=$((PASSED_CHECKS + 1)); }
log_error()   { echo -e "${RED}[✗]${NC} $1"; FAILED_CHECKS=$((FAILED_CHECKS + 1)); }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }

run_check() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_info "Checking: $1"
}

check_pod() {
    local ns="$1" label="$2" name="$3"
    run_check "$name pod status"
    if kubectl get pods -n "$ns" -l "$label" 2>/dev/null | grep -q .; then
        if kubectl wait --for=condition=ready pod -l "$label" -n "$ns" --timeout=10s &>/dev/null; then
            log_success "$name is Running and Ready"
        else
            log_error "$name is not Ready"
        fi
    else
        log_warning "$name pod not found"
    fi
}

# Check 1: Pod Health
check_pod_health() {
    echo ""
    echo "=========================================="
    echo "1. Pod Health Check"
    echo "=========================================="
    echo ""

    # Platform namespace
    check_pod "$PLATFORM_NS" "app.kubernetes.io/name=postgresql" "PostgreSQL"
    check_pod "$PLATFORM_NS" "app.kubernetes.io/name=keycloak" "Keycloak"
    check_pod "$PLATFORM_NS" "app.kubernetes.io/name=nats" "NATS"

    # Security namespace
    check_pod "$SECURITY_NS" "app.kubernetes.io/name=vault" "Vault"

    # Apps namespace
    check_pod "$APPS_NS" "app.kubernetes.io/name=go-auth" "go-auth"
    check_pod "$APPS_NS" "app.kubernetes.io/name=go-sprint" "go-sprint"
    check_pod "$APPS_NS" "app.kubernetes.io/name=py-dnd" "py-dnd"
    check_pod "$APPS_NS" "app.kubernetes.io/name=ui-dnd" "ui-dnd"
    check_pod "$APPS_NS" "app.kubernetes.io/name=ui-sprint-management" "ui-sprint-management"
}

# Check 2: Service Endpoints
check_service_endpoints() {
    echo ""
    echo "=========================================="
    echo "2. Service Endpoint Check"
    echo "=========================================="
    echo ""

    local -A svc_checks=(
        ["go-auth"]="apps-go-auth:8081:/health/live"
        ["go-sprint"]="apps-go-sprint:8003:/health/live"
        ["py-dnd"]="apps-py-dnd:8001:/api/v1/health"
    )

    for name in "${!svc_checks[@]}"; do
        run_check "$name health endpoint"
        IFS=':' read -r svc port path <<< "${svc_checks[$name]}"

        if ! kubectl get service "$svc" -n "$APPS_NS" &>/dev/null; then
            log_warning "$name service not found"
            continue
        fi

        if ! kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=${name}" -n "$APPS_NS" --timeout=5s &>/dev/null; then
            log_warning "$name pod not ready"
            continue
        fi

        local local_port=$((9000 + RANDOM % 1000))
        kubectl port-forward -n "$APPS_NS" "service/$svc" "$local_port:$port" &>/dev/null &
        local pf_pid=$!
        sleep 2

        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$local_port$path" 2>/dev/null || echo "000")
        kill $pf_pid 2>/dev/null || true
        wait $pf_pid 2>/dev/null || true

        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            log_success "$name health endpoint returned HTTP $http_code"
        else
            log_error "$name health endpoint returned HTTP $http_code (expected 2xx)"
        fi
    done
}

# Check 3: Vault Integration
check_vault_integration() {
    echo ""
    echo "=========================================="
    echo "3. Vault Integration Check"
    echo "=========================================="
    echo ""

    run_check "Vault seal status"
    local vault_addr="http://vault.${SECURITY_NS}.svc.cluster.local:8200"
    local root_token="root"

    if [ "$ENV" != "local" ] && [ -f "vault-init-keys.json" ]; then
        root_token=$(jq -r '.root_token' vault-init-keys.json)
    fi

    if kubectl exec -n "$SECURITY_NS" vault-0 -- vault status 2>/dev/null | grep -q "Sealed.*false"; then
        log_success "Vault is unsealed"
    else
        log_error "Vault is sealed or not accessible"
        return
    fi

    run_check "Database secrets engine"
    if kubectl exec -n "$SECURITY_NS" vault-0 -- sh -c "
        export VAULT_ADDR='${vault_addr}'; export VAULT_TOKEN='${root_token}'
        vault secrets list 2>/dev/null
    " | grep -q "database/"; then
        log_success "Database secrets engine is enabled"
    else
        log_error "Database secrets engine is not enabled"
    fi
}

# Check 4: Migration Jobs
check_migrations() {
    echo ""
    echo "=========================================="
    echo "4. Migration Job Status"
    echo "=========================================="
    echo ""

    local jobs=("apps-go-auth-migration" "apps-go-sprint-migration" "apps-py-dnd-migration")

    for job in "${jobs[@]}"; do
        run_check "$job"
        if kubectl get job "$job" -n "$APPS_NS" &>/dev/null; then
            local succeeded
            succeeded=$(kubectl get job "$job" -n "$APPS_NS" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
            if [ "${succeeded:-0}" -ge 1 ]; then
                log_success "$job completed successfully"
            else
                local failed
                failed=$(kubectl get job "$job" -n "$APPS_NS" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
                if [ "${failed:-0}" -gt 0 ]; then
                    log_error "$job failed"
                else
                    log_warning "$job in progress"
                fi
            fi
        else
            log_warning "$job not found"
        fi
    done
}

# Check 5: Ingress
check_ingress() {
    echo ""
    echo "=========================================="
    echo "5. Ingress Check"
    echo "=========================================="
    echo ""

    run_check "Ingress resource"
    if kubectl get ingress ttrpg-ingress -n "$PLATFORM_NS" &>/dev/null; then
        log_success "Ingress resource exists"
    else
        log_error "Ingress resource not found"
    fi

    run_check "Ingress controller"
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress -n "$PLATFORM_NS" --timeout=5s &>/dev/null; then
        log_success "Ingress controller is running"
    else
        log_error "Ingress controller is not ready"
    fi
}

# Main
main() {
    echo ""
    echo "=========================================="
    echo "Deployment Verification"
    echo "=========================================="
    echo "Environment: $ENV"
    echo "Namespaces: $PLATFORM_NS, $SECURITY_NS, $APPS_NS"
    echo "=========================================="

    check_pod_health
    check_service_endpoints
    check_vault_integration
    check_migrations
    check_ingress

    echo ""
    echo "=========================================="
    echo "Verification Summary"
    echo "=========================================="
    echo "Total Checks: $TOTAL_CHECKS"
    echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
    echo "=========================================="
    echo ""

    if [ $FAILED_CHECKS -gt 0 ]; then
        echo -e "${RED}Verification FAILED${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  • Platform pods: kubectl get pods -n $PLATFORM_NS"
        echo "  • App pods:      kubectl get pods -n $APPS_NS"
        echo "  • Vault:         kubectl exec -n $SECURITY_NS vault-0 -- vault status"
        echo "  • App logs:      kubectl logs -n $APPS_NS -l app.kubernetes.io/name=<service>"
        echo ""
        exit 1
    else
        echo -e "${GREEN}Verification PASSED${NC}"
        exit 0
    fi
}

main
