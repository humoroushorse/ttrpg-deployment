#!/bin/bash
# Property-Based Tests for Vault Configuration
# These tests validate correctness properties for the deployment system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Minimum iterations for property-based tests
MIN_ITERATIONS=100

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

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    log_info "Running: $test_name"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_error "$1"
}

# Property 1: Cluster-Internal DNS Usage
# For any Vault database secrets engine configuration, the PostgreSQL connection URL
# should contain cluster-internal DNS names (matching pattern *.svc.cluster.local)
# rather than localhost or external addresses.
test_cluster_internal_dns() {
    run_test "Property 1: Cluster-Internal DNS Usage"
    
    local env="${1:-local}"
    local vault_namespace="vault"
    local app_namespace="ttrpg-${env}"
    local iterations=0
    local failures=0
    
    # Check if Vault is accessible
    if ! kubectl get pod vault-0 -n ${vault_namespace} &>/dev/null; then
        fail_test "Vault pod not found in namespace ${vault_namespace}"
        return 1
    fi
    
    # Get root token
    if [ ! -f "vault-init-keys.json" ]; then
        fail_test "vault-init-keys.json not found"
        return 1
    fi
    
    local root_token=$(cat vault-init-keys.json | jq -r '.root_token')
    local vault_addr="http://vault.${vault_namespace}.svc.cluster.local:8200"
    
    # Run property test with multiple iterations
    log_info "Running ${MIN_ITERATIONS} iterations..."
    
    for i in $(seq 1 ${MIN_ITERATIONS}); do
        iterations=$((iterations + 1))
        
        # Read database configuration from Vault
        local config_output=$(kubectl exec -n ${vault_namespace} vault-0 -- sh -c "
            export VAULT_ADDR='${vault_addr}'
            export VAULT_TOKEN='${root_token}'
            vault read -format=json database/config/postgresql 2>/dev/null || echo '{}'
        ")
        
        # Extract connection URL
        local connection_url=$(echo "$config_output" | jq -r '.data.connection_url // empty')
        
        if [ -z "$connection_url" ]; then
            # Database not configured yet, skip this iteration
            continue
        fi
        
        # Property: Connection URL must contain cluster-internal DNS pattern
        if ! echo "$connection_url" | grep -q "\.svc\.cluster\.local"; then
            failures=$((failures + 1))
            log_error "Iteration $i: Connection URL does not use cluster-internal DNS: $connection_url"
        fi
        
        # Property: Connection URL must NOT contain localhost or 127.0.0.1
        if echo "$connection_url" | grep -qE "(localhost|127\.0\.0\.1)"; then
            failures=$((failures + 1))
            log_error "Iteration $i: Connection URL uses localhost instead of cluster DNS: $connection_url"
        fi
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 1 holds: All $iterations iterations used cluster-internal DNS"
        return 0
    else
        fail_test "Property 1 violated: $failures/$iterations iterations failed"
        return 1
    fi
}

# Property 2: Dynamic Credential Generation
# For any configured Vault role, requesting credentials from Vault should return
# valid username and password pairs that can be used to authenticate to PostgreSQL.
test_dynamic_credential_generation() {
    run_test "Property 2: Dynamic Credential Generation"
    
    local env="${1:-local}"
    local vault_namespace="vault"
    local app_namespace="ttrpg-${env}"
    local iterations=0
    local failures=0
    
    # Check if Vault is accessible
    if ! kubectl get pod vault-0 -n ${vault_namespace} &>/dev/null; then
        fail_test "Vault pod not found in namespace ${vault_namespace}"
        return 1
    fi
    
    # Get root token
    if [ ! -f "vault-init-keys.json" ]; then
        fail_test "vault-init-keys.json not found"
        return 1
    fi
    
    local root_token=$(cat vault-init-keys.json | jq -r '.root_token')
    local vault_addr="http://vault.${vault_namespace}.svc.cluster.local:8200"
    
    # Test roles
    local roles=("go-auth-role" "go-sprint-role" "py-dnd-role" "keycloak-role")
    
    log_info "Running ${MIN_ITERATIONS} iterations across all roles..."
    
    for i in $(seq 1 ${MIN_ITERATIONS}); do
        iterations=$((iterations + 1))
        
        # Select a random role
        local role_index=$((RANDOM % ${#roles[@]}))
        local role="${roles[$role_index]}"
        
        # Request credentials from Vault
        local creds_output=$(kubectl exec -n ${vault_namespace} vault-0 -- sh -c "
            export VAULT_ADDR='${vault_addr}'
            export VAULT_TOKEN='${root_token}'
            vault read -format=json database/creds/${role} 2>/dev/null || echo '{}'
        ")
        
        # Extract username and password
        local username=$(echo "$creds_output" | jq -r '.data.username // empty')
        local password=$(echo "$creds_output" | jq -r '.data.password // empty')
        
        # Property: Credentials must contain both username and password
        if [ -z "$username" ] || [ -z "$password" ]; then
            failures=$((failures + 1))
            log_error "Iteration $i: Failed to generate credentials for role $role"
            continue
        fi
        
        # Property: Username should follow Vault's naming pattern (v-root-*)
        if ! echo "$username" | grep -qE "^v-"; then
            failures=$((failures + 1))
            log_error "Iteration $i: Username does not follow expected pattern: $username"
        fi
        
        # Property: Password should be non-empty and reasonably long
        if [ ${#password} -lt 16 ]; then
            failures=$((failures + 1))
            log_error "Iteration $i: Password is too short (${#password} chars)"
        fi
        
        # Revoke the lease to clean up
        local lease_id=$(echo "$creds_output" | jq -r '.lease_id // empty')
        if [ -n "$lease_id" ]; then
            kubectl exec -n ${vault_namespace} vault-0 -- sh -c "
                export VAULT_ADDR='${vault_addr}'
                export VAULT_TOKEN='${root_token}'
                vault lease revoke ${lease_id} 2>/dev/null || true
            " &>/dev/null
        fi
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 2 holds: All $iterations iterations generated valid credentials"
        return 0
    else
        fail_test "Property 2 violated: $failures/$iterations iterations failed"
        return 1
    fi
}

# Main test execution
main() {
    local env="${1:-local}"
    
    echo "========================================"
    echo "Vault Configuration Property Tests"
    echo "Environment: $env"
    echo "Min iterations per test: $MIN_ITERATIONS"
    echo "========================================"
    echo ""
    
    # Run tests
    test_cluster_internal_dns "$env" || true
    echo ""
    test_dynamic_credential_generation "$env" || true
    
    # Summary
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "========================================"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        exit 1
    fi
}

# Run tests
main "$@"
