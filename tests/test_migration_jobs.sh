#!/bin/bash

# Property-Based Tests for Database Migration Jobs
# Tests Properties 3, 4, and 5 from the design document

set -euo pipefail

# Configuration
MIN_ITERATIONS=100
ENV="${1:-local}"
NAMESPACE="ttrpg-${ENV}"

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

# Property 3: Migration Precedes Application
# For any service deployment, the migration job should complete successfully 
# before the application pod transitions to the Ready state
test_migration_precedes_application() {
    run_test "Property 3: Migration Precedes Application"
    
    local services=("py-dnd" "go-sprint" "go-auth")
    local failures=0
    local iterations=0
    
    for service in "${services[@]}"; do
        for ((i=1; i<=MIN_ITERATIONS; i++)); do
            iterations=$((iterations + 1))
            
            # Check if migration job exists
            local migration_job="${service}-migration"
            if ! kubectl get job "$migration_job" -n "$NAMESPACE" &> /dev/null; then
                # Migration not enabled for this service, skip
                continue
            fi
            
            # Get migration job completion time
            local migration_complete_time
            migration_complete_time=$(kubectl get job "$migration_job" -n "$NAMESPACE" \
                -o jsonpath='{.status.completionTime}' 2>/dev/null || echo "")
            
            if [ -z "$migration_complete_time" ]; then
                # Migration job hasn't completed yet
                continue
            fi
            
            # Get application pod ready time
            local app_pod
            app_pod=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${service}" \
                -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            
            if [ -z "$app_pod" ]; then
                # Application pod doesn't exist yet
                continue
            fi
            
            # Check if pod is ready
            local pod_ready
            pod_ready=$(kubectl get pod "$app_pod" -n "$NAMESPACE" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            
            if [ "$pod_ready" != "True" ]; then
                # Pod not ready yet
                continue
            fi
            
            # Get pod creation time (approximation of ready time)
            local pod_start_time
            pod_start_time=$(kubectl get pod "$app_pod" -n "$NAMESPACE" \
                -o jsonpath='{.status.startTime}' 2>/dev/null || echo "")
            
            if [ -z "$pod_start_time" ]; then
                continue
            fi
            
            # Convert times to seconds since epoch for comparison
            local migration_epoch
            migration_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$migration_complete_time" "+%s" 2>/dev/null || echo "0")
            local pod_epoch
            pod_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$pod_start_time" "+%s" 2>/dev/null || echo "0")
            
            # Migration should complete before pod starts
            if [ "$migration_epoch" -gt "$pod_epoch" ]; then
                failures=$((failures + 1))
                fail_test "Property 3" "Service $service: Migration completed AFTER pod started (migration: $migration_complete_time, pod: $pod_start_time)"
                break 2
            fi
        done
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 3: Migration Precedes Application ($iterations iterations)"
    fi
}

# Property 4: Failed Migrations Block Deployment
# For any service with a failed migration job, the application deployment 
# should not proceed and the application pod should not reach the Running state
test_failed_migrations_block_deployment() {
    run_test "Property 4: Failed Migrations Block Deployment"
    
    local services=("py-dnd" "go-sprint" "go-auth")
    local failures=0
    local iterations=0
    
    for service in "${services[@]}"; do
        for ((i=1; i<=MIN_ITERATIONS; i++)); do
            iterations=$((iterations + 1))
            
            # Check if migration job exists
            local migration_job="${service}-migration"
            if ! kubectl get job "$migration_job" -n "$NAMESPACE" &> /dev/null; then
                # Migration not enabled for this service, skip
                continue
            fi
            
            # Check if migration job failed
            local job_failed
            job_failed=$(kubectl get job "$migration_job" -n "$NAMESPACE" \
                -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
            
            if [ "$job_failed" -eq 0 ]; then
                # Migration hasn't failed, skip
                continue
            fi
            
            # Check if application pod is running
            local app_pod
            app_pod=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${service}" \
                -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            
            if [ -z "$app_pod" ]; then
                # No application pod exists, which is correct behavior
                continue
            fi
            
            # Check pod phase
            local pod_phase
            pod_phase=$(kubectl get pod "$app_pod" -n "$NAMESPACE" \
                -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            
            # If migration failed, pod should not be Running
            if [ "$pod_phase" = "Running" ]; then
                failures=$((failures + 1))
                fail_test "Property 4" "Service $service: Application pod is Running despite failed migration"
                break 2
            fi
        done
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 4: Failed Migrations Block Deployment ($iterations iterations)"
    fi
}

# Property 5: Successful Migrations Enable Deployment
# For any service with a successfully completed migration job, the application 
# deployment should proceed and the application pod should eventually reach the Ready state
test_successful_migrations_enable_deployment() {
    run_test "Property 5: Successful Migrations Enable Deployment"
    
    local services=("py-dnd" "go-sprint" "go-auth")
    local failures=0
    local iterations=0
    
    for service in "${services[@]}"; do
        for ((i=1; i<=MIN_ITERATIONS; i++)); do
            iterations=$((iterations + 1))
            
            # Check if migration job exists
            local migration_job="${service}-migration"
            if ! kubectl get job "$migration_job" -n "$NAMESPACE" &> /dev/null; then
                # Migration not enabled for this service, skip
                continue
            fi
            
            # Check if migration job succeeded
            local job_succeeded
            job_succeeded=$(kubectl get job "$migration_job" -n "$NAMESPACE" \
                -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
            
            if [ "$job_succeeded" -eq 0 ]; then
                # Migration hasn't succeeded yet, skip
                continue
            fi
            
            # Wait for application pod to be created (with timeout)
            local timeout=60
            local elapsed=0
            local app_pod=""
            
            while [ $elapsed -lt $timeout ]; do
                app_pod=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${service}" \
                    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                
                if [ -n "$app_pod" ]; then
                    break
                fi
                
                sleep 2
                elapsed=$((elapsed + 2))
            done
            
            if [ -z "$app_pod" ]; then
                failures=$((failures + 1))
                fail_test "Property 5" "Service $service: Application pod not created after successful migration"
                break 2
            fi
            
            # Wait for pod to be ready (with timeout)
            timeout=120
            elapsed=0
            local pod_ready="False"
            
            while [ $elapsed -lt $timeout ]; do
                pod_ready=$(kubectl get pod "$app_pod" -n "$NAMESPACE" \
                    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
                
                if [ "$pod_ready" = "True" ]; then
                    break
                fi
                
                # Check if pod is in error state
                local pod_phase
                pod_phase=$(kubectl get pod "$app_pod" -n "$NAMESPACE" \
                    -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
                
                if [ "$pod_phase" = "Failed" ] || [ "$pod_phase" = "CrashLoopBackOff" ]; then
                    failures=$((failures + 1))
                    fail_test "Property 5" "Service $service: Application pod failed to start after successful migration (phase: $pod_phase)"
                    break 3
                fi
                
                sleep 2
                elapsed=$((elapsed + 2))
            done
            
            if [ "$pod_ready" != "True" ]; then
                failures=$((failures + 1))
                fail_test "Property 5" "Service $service: Application pod not ready after successful migration (timeout after ${timeout}s)"
                break 2
            fi
        done
    done
    
    if [ $failures -eq 0 ]; then
        pass_test "Property 5: Successful Migrations Enable Deployment ($iterations iterations)"
    fi
}

# Main test execution
main() {
    echo "=========================================="
    echo "Database Migration Property-Based Tests"
    echo "Environment: $ENV"
    echo "Namespace: $NAMESPACE"
    echo "Min Iterations: $MIN_ITERATIONS"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    echo ""
    
    # Run all property tests
    test_migration_precedes_application
    echo ""
    
    test_failed_migrations_block_deployment
    echo ""
    
    test_successful_migrations_enable_deployment
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
