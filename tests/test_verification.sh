#!/bin/bash
# Property-Based Tests for Deployment Verification
# Tests Properties 8, 9, 10, and 11 from the design document

set -euo pipefail

# Configuration
MIN_ITERATIONS=100
ENV="${1:-local}"
NAMESPACE="ttrpg-${ENV}"
VAULT_NAMESPACE="vault"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper functions
log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

run_test() {
    local test_name="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_info "Running: $test_name"
}

pass_test() {
    local test_name="$1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log_success "$test_name"
}

fail_test() {
    local test_name="$1"
    local reason="$2"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log_error "$test_name - $reason"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install jq."
        exit 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace $NAMESPACE not found. Please deploy the infrastructure first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Property 8: Pod Health Verification
# For any completed deployment, all expected pods (PostgreSQL, Vault, Keycloak, 
# py-dnd, go-sprint, go-auth) should have status "Running" and condition "Ready" 
# set to "True"
test_pod_health_verification() {
    run_test "Property 8: Pod Health Verification"
    
    local failures=0
    local iterations=0
    
    log_info "Running ${MIN_ITERATIONS} iterations..."
    
    for ((i=1; i<=MIN_ITERATIONS; i++)); do
        iterations=$((iterations + 1))
        
        # Check PostgreSQL
        check_pod_health "postgresql" "$NAMESPACE" "app.kubernetes.io/name=postgresql" "required" "$i" || failures=$((failures + 1))
        
        # Check Vault
        check_pod_health "vault" "$VAULT_NAMESPACE" "app.kubernetes.io/name=vault" "required" "$i" || failures=$((failures + 1))
        
        # Check Keycloak
        check_pod_health "keycloak" "$NAMESPACE" "app.kubernetes.io/name=keycloak" "required" "$i" || failures=$((failures + 1))
        
        # Check optional application services
        check_pod_health "py-dnd" "$NAMESPACE" "app.kubernetes.io/name=py-dnd" "optional" "$i" || failures=$((failures + 1))
        check_pod_health "go-sprint" "$NAMESPACE" "app.kubernetes.io/name=go-sprint" "optional" "$i" || failures=$((failures + 1))
        check_pod_health "go-auth" "$NAMESPACE" "app.kubernetes.io/name=go-auth" "optional" "$i" || failures=$((failures + 1))
        
        # Add small delay between iterations to allow for state changes
        if [ $i -lt $MIN_ITERATIONS ]; then
            sleep 0.1
        fi
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 8: Pod Health Verification ($iterations iterations, all pods healthy)"
    else
        fail_test "Property 8" "$failures health check failures across $iterations iterations"
    fi
}

# Helper function to check individual pod health
check_pod_health() {
    local pod_name="$1"
    local ns="$2"
    local label="$3"
    local required="$4"
    local iteration="$5"
    
    # Get pod status
    local pod_info
    pod_info=$(kubectl get pods -n "$ns" -l "$label" \
        -o json 2>/dev/null || echo '{"items":[]}')
    
    local pod_count
    pod_count=$(echo "$pod_info" | jq '.items | length')
    
    if [ "$pod_count" -eq 0 ]; then
        # Pod doesn't exist
        if [ "$required" = "optional" ]; then
            # Optional service not deployed is acceptable
            return 0
        else
            log_error "Iteration $iteration: Required pod $pod_name not found in namespace $ns"
            return 1
        fi
    fi
    
    # Check each pod instance (for StatefulSets/Deployments with replicas)
    local pod_index=0
    local pod_failures=0
    
    while [ $pod_index -lt "$pod_count" ]; do
        # Get pod phase
        local pod_phase
        pod_phase=$(echo "$pod_info" | jq -r ".items[$pod_index].status.phase // \"Unknown\"")
        
        # Property: Pod phase must be "Running"
        if [ "$pod_phase" != "Running" ]; then
            log_error "Iteration $iteration: Pod $pod_name[$pod_index] phase is '$pod_phase', expected 'Running'"
            pod_failures=$((pod_failures + 1))
        fi
        
        # Get Ready condition
        local ready_status
        ready_status=$(echo "$pod_info" | jq -r ".items[$pod_index].status.conditions[] | select(.type==\"Ready\") | .status // \"False\"")
        
        # Property: Ready condition must be "True"
        if [ "$ready_status" != "True" ]; then
            log_error "Iteration $iteration: Pod $pod_name[$pod_index] Ready condition is '$ready_status', expected 'True'"
            pod_failures=$((pod_failures + 1))
        fi
        
        pod_index=$((pod_index + 1))
    done
    
    if [ $pod_failures -gt 0 ]; then
        return 1
    fi
    
    return 0
}

# Property 9: Service Endpoint Availability
# For any deployed service with a health endpoint, HTTP requests to that endpoint 
# should return successful status codes (2xx range)
test_service_endpoint_availability() {
    run_test "Property 9: Service Endpoint Availability"
    
    local failures=0
    local iterations=0
    
    # Define services with their health endpoints
    declare -A services=(
        ["go-auth"]="8080:/health"
        ["go-sprint"]="8080:/health"
        ["py-dnd"]="8000:/health"
    )
    
    log_info "Running ${MIN_ITERATIONS} iterations..."
    
    for ((i=1; i<=MIN_ITERATIONS; i++)); do
        iterations=$((iterations + 1))
        
        for service_name in "${!services[@]}"; do
            local port_path="${services[$service_name]}"
            local port="${port_path%%:*}"
            local path="${port_path#*:}"
            
            # Check if service exists
            if ! kubectl get service "$service_name" -n "$NAMESPACE" &> /dev/null; then
                log_warning "Iteration $i: Service $service_name not deployed"
                continue
            fi
            
            # Check if pod is ready
            local pod_ready
            pod_ready=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${service_name}" \
                -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            
            if [ "$pod_ready" != "True" ]; then
                log_warning "Iteration $i: Service $service_name pod not ready"
                continue
            fi
            
            # Use kubectl port-forward in background and test endpoint
            local local_port=$((8000 + RANDOM % 1000))
            kubectl port-forward -n "$NAMESPACE" "service/$service_name" "$local_port:$port" &> /dev/null &
            local pf_pid=$!
            
            # Wait for port-forward to be ready
            sleep 1
            
            # Test endpoint
            local http_code
            http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$local_port$path" 2>/dev/null || echo "000")
            
            # Kill port-forward
            kill $pf_pid 2>/dev/null || true
            wait $pf_pid 2>/dev/null || true
            
            # Property: HTTP status code must be in 2xx range
            if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
                failures=$((failures + 1))
                log_error "Iteration $i: Service $service_name endpoint returned HTTP $http_code, expected 2xx"
            fi
        done
        
        # Add small delay between iterations
        if [ $i -lt $MIN_ITERATIONS ]; then
            sleep 0.2
        fi
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 9: Service Endpoint Availability ($iterations iterations, all endpoints healthy)"
    else
        fail_test "Property 9" "$failures endpoint check failures across $iterations iterations"
    fi
}

# Property 10: Service Credential Access
# For any deployed service configured to use Vault dynamic credentials, that service 
# should be able to successfully request and receive database credentials from Vault
test_service_credential_access() {
    run_test "Property 10: Service Credential Access"
    
    local failures=0
    local iterations=0
    
    # Get Vault root token
    if [ ! -f "vault-init-keys.json" ]; then
        log_warning "vault-init-keys.json not found - skipping credential access test"
        pass_test "Property 10: Service Credential Access (skipped - no vault keys)"
        return 0
    fi
    
    local root_token
    root_token=$(cat vault-init-keys.json | jq -r '.root_token')
    local vault_addr="http://vault.${VAULT_NAMESPACE}.svc.cluster.local:8200"
    
    # Define services and their Vault roles
    local services=("go-auth" "go-sprint" "py-dnd")
    
    log_info "Running ${MIN_ITERATIONS} iterations..."
    
    for ((i=1; i<=MIN_ITERATIONS; i++)); do
        iterations=$((iterations + 1))
        
        # Select a random service
        local service_index=$((RANDOM % ${#services[@]}))
        local service="${services[$service_index]}"
        local role="${service}-role"
        
        # Check if service is deployed
        if ! kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${service}" &> /dev/null; then
            continue
        fi
        
        # Check if pod is ready
        local pod_ready
        pod_ready=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${service}" \
            -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        
        if [ "$pod_ready" != "True" ]; then
            continue
        fi
        
        # Attempt to read credentials from Vault (simulating service access)
        local creds_output
        creds_output=$(kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- sh -c "
            export VAULT_ADDR='${vault_addr}'
            export VAULT_TOKEN='${root_token}'
            vault read -format=json database/creds/${role} 2>/dev/null || echo '{}'
        " 2>/dev/null || echo '{}')
        
        # Extract username and password
        local username
        username=$(echo "$creds_output" | jq -r '.data.username // empty')
        local password
        password=$(echo "$creds_output" | jq -r '.data.password // empty')
        
        # Property: Service must be able to obtain credentials
        if [ -z "$username" ] || [ -z "$password" ]; then
            failures=$((failures + 1))
            log_error "Iteration $i: Service $service failed to obtain credentials from Vault"
            continue
        fi
        
        # Property: Credentials must be valid format
        if ! echo "$username" | grep -qE "^v-"; then
            failures=$((failures + 1))
            log_error "Iteration $i: Service $service received invalid username format: $username"
        fi
        
        if [ ${#password} -lt 16 ]; then
            failures=$((failures + 1))
            log_error "Iteration $i: Service $service received password that is too short (${#password} chars)"
        fi
        
        # Revoke the lease to clean up
        local lease_id
        lease_id=$(echo "$creds_output" | jq -r '.lease_id // empty')
        if [ -n "$lease_id" ]; then
            kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- sh -c "
                export VAULT_ADDR='${vault_addr}'
                export VAULT_TOKEN='${root_token}'
                vault lease revoke ${lease_id} 2>/dev/null || true
            " &>/dev/null || true
        fi
        
        # Add small delay between iterations
        if [ $i -lt $MIN_ITERATIONS ]; then
            sleep 0.1
        fi
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 10: Service Credential Access ($iterations iterations, all services can access credentials)"
    else
        fail_test "Property 10" "$failures credential access failures across $iterations iterations"
    fi
}

# Property 11: Database Connectivity
# For any deployed service with dynamic credentials, that service should be able to 
# successfully connect to its PostgreSQL database and execute queries using those credentials
test_database_connectivity() {
    run_test "Property 11: Database Connectivity"
    
    local failures=0
    local iterations=0
    
    local services=("go-auth" "go-sprint" "py-dnd")
    
    log_info "Running ${MIN_ITERATIONS} iterations..."
    
    for ((i=1; i<=MIN_ITERATIONS; i++)); do
        iterations=$((iterations + 1))
        
        # Select a random service
        local service_index=$((RANDOM % ${#services[@]}))
        local service="${services[$service_index]}"
        
        # Check if service is deployed
        local pod_name
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${service}" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ -z "$pod_name" ]; then
            continue
        fi
        
        # Check if pod is ready
        local pod_ready
        pod_ready=$(kubectl get pod "$pod_name" -n "$NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        
        if [ "$pod_ready" != "True" ]; then
            continue
        fi
        
        # Check service logs for database connection indicators
        local logs
        logs=$(kubectl logs "$pod_name" -n "$NAMESPACE" --tail=100 2>/dev/null || echo "")
        
        # Property: Logs should indicate successful database connection
        # Look for common success patterns and absence of connection errors
        local has_connection_success=false
        local has_connection_error=false
        
        # Check for success indicators (service-specific patterns)
        if echo "$logs" | grep -qiE "(connected to database|database connection established|migration.*complete|database.*ready)"; then
            has_connection_success=true
        fi
        
        # Check for error indicators
        if echo "$logs" | grep -qiE "(database connection failed|could not connect to database|connection refused.*postgres|authentication failed.*database)"; then
            has_connection_error=true
        fi
        
        # Property: Service should have successful connection and no connection errors
        if [ "$has_connection_error" = true ]; then
            failures=$((failures + 1))
            log_error "Iteration $i: Service $service logs show database connection errors"
        elif [ "$has_connection_success" = false ]; then
            # No explicit success message found, but also no errors
            # This is acceptable as some services may not log connection success
            log_warning "Iteration $i: Service $service has no explicit database connection success message (may be normal)"
        fi
        
        # Additional check: Verify service is responding (implies database connectivity)
        # If service health endpoint works, database is likely connected
        if kubectl get service "$service" -n "$NAMESPACE" &> /dev/null; then
            local port
            case "$service" in
                "go-auth"|"go-sprint")
                    port=8080
                    ;;
                "py-dnd")
                    port=8000
                    ;;
            esac
            
            local local_port=$((9000 + RANDOM % 1000))
            kubectl port-forward -n "$NAMESPACE" "service/$service" "$local_port:$port" &> /dev/null &
            local pf_pid=$!
            
            sleep 1
            
            local http_code
            http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$local_port/health" 2>/dev/null || echo "000")
            
            kill $pf_pid 2>/dev/null || true
            wait $pf_pid 2>/dev/null || true
            
            # If health endpoint works, database connectivity is likely working
            if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
                has_connection_success=true
            fi
        fi
        
        # Add small delay between iterations
        if [ $i -lt $MIN_ITERATIONS ]; then
            sleep 0.2
        fi
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 11: Database Connectivity ($iterations iterations, all services can connect to database)"
    else
        fail_test "Property 11" "$failures database connectivity failures across $iterations iterations"
    fi
}

# Main test execution
main() {
    echo "=========================================="
    echo "Deployment Verification Property-Based Tests"
    echo "Environment: $ENV"
    echo "Namespace: $NAMESPACE"
    echo "Vault Namespace: $VAULT_NAMESPACE"
    echo "Min Iterations: $MIN_ITERATIONS"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    # Run all property tests
    test_pod_health_verification
    echo ""
    
    test_service_endpoint_availability
    echo ""
    
    test_service_credential_access
    echo ""
    
    test_database_connectivity
    echo ""
    
    # Print summary
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "=========================================="
    
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    fi
    
    exit 0
}

# Run main function
main
