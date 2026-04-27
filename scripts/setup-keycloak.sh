#!/bin/bash
set -euo pipefail

# Script to configure Keycloak realms and clients using the Admin REST API
# This script is idempotent - it checks if resources exist before creating them

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="${ENV:-local}"
NAMESPACE="ttrpg-${ENV}"
KEYCLOAK_SERVICE="keycloak.${NAMESPACE}.svc.cluster.local"
KEYCLOAK_PORT="8080"
KEYCLOAK_URL="http://${KEYCLOAK_SERVICE}:${KEYCLOAK_PORT}"
DOMAIN="${DOMAIN:-localhost}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Wait for Keycloak to be ready
wait_for_keycloak() {
    log_info "Waiting for Keycloak to be ready..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "${KEYCLOAK_URL}/health/ready" > /dev/null 2>&1; then
            log_info "Keycloak is ready!"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    
    log_error "Keycloak did not become ready in time"
    return 1
}

# Get admin credentials from Vault via Kubernetes
get_admin_credentials() {
    log_info "Retrieving admin credentials from Keycloak pod..."
    
    # Get the Keycloak pod name
    local pod_name=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=keycloak" -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        log_error "Could not find Keycloak pod"
        return 1
    fi
    
    # Extract credentials from Vault secrets
    KEYCLOAK_ADMIN=$(kubectl exec -n "${NAMESPACE}" "${pod_name}" -- sh -c 'source /vault/secrets/admin && echo $KEYCLOAK_ADMIN')
    KEYCLOAK_ADMIN_PASSWORD=$(kubectl exec -n "${NAMESPACE}" "${pod_name}" -- sh -c 'source /vault/secrets/admin && echo $KEYCLOAK_ADMIN_PASSWORD')
    
    if [ -z "$KEYCLOAK_ADMIN" ] || [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
        log_error "Could not retrieve admin credentials"
        return 1
    fi
    
    log_info "Admin credentials retrieved successfully"
}

# Get admin access token
get_admin_token() {
    log_info "Obtaining admin access token..."
    
    local response=$(curl -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${KEYCLOAK_ADMIN}" \
        -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to obtain admin token"
        return 1
    fi
    
    ADMIN_TOKEN=$(echo "$response" | jq -r '.access_token')
    
    if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
        log_error "Invalid admin token received"
        return 1
    fi
    
    log_info "Admin token obtained successfully"
}

# Check if realm exists
realm_exists() {
    local realm_name=$1
    local response=$(curl -sf -X GET "${KEYCLOAK_URL}/admin/realms/${realm_name}" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json")
    
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Create realm
create_realm() {
    local realm_name=$1
    local display_name=$2
    
    log_info "Creating realm: ${realm_name}..."
    
    if realm_exists "$realm_name"; then
        log_warn "Realm ${realm_name} already exists, skipping creation"
        return 0
    fi
    
    local realm_config=$(cat <<EOF
{
  "realm": "${realm_name}",
  "displayName": "${display_name}",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "accessTokenLifespan": 300,
  "accessTokenLifespanForImplicitFlow": 900,
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 36000,
  "offlineSessionIdleTimeout": 2592000,
  "accessCodeLifespan": 60,
  "accessCodeLifespanUserAction": 300,
  "accessCodeLifespanLogin": 1800,
  "actionTokenGeneratedByAdminLifespan": 43200,
  "actionTokenGeneratedByUserLifespan": 300,
  "oauth2DeviceCodeLifespan": 600,
  "oauth2DevicePollingInterval": 5
}
EOF
)
    
    local response=$(curl -sf -X POST "${KEYCLOAK_URL}/admin/realms" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$realm_config")
    
    if [ $? -eq 0 ]; then
        log_info "Realm ${realm_name} created successfully"
        return 0
    else
        log_error "Failed to create realm ${realm_name}"
        return 1
    fi
}

# Check if client exists
client_exists() {
    local realm_name=$1
    local client_id=$2
    
    local response=$(curl -sf -X GET "${KEYCLOAK_URL}/admin/realms/${realm_name}/clients?clientId=${client_id}" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json")
    
    if [ $? -eq 0 ] && [ "$(echo "$response" | jq '. | length')" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Create client
create_client() {
    local realm_name=$1
    local client_id=$2
    local redirect_uri=$3
    
    log_info "Creating client: ${client_id} in realm ${realm_name}..."
    
    if client_exists "$realm_name" "$client_id"; then
        log_warn "Client ${client_id} already exists in realm ${realm_name}, skipping creation"
        return 0
    fi
    
    local client_config=$(cat <<EOF
{
  "clientId": "${client_id}",
  "name": "${client_id}",
  "description": "Client for ${realm_name} application",
  "enabled": true,
  "publicClient": true,
  "protocol": "openid-connect",
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": false,
  "authorizationServicesEnabled": false,
  "redirectUris": [
    "${redirect_uri}"
  ],
  "webOrigins": [
    "*"
  ],
  "attributes": {
    "pkce.code.challenge.method": "S256"
  }
}
EOF
)
    
    local response=$(curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/${realm_name}/clients" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$client_config")
    
    if [ $? -eq 0 ]; then
        log_info "Client ${client_id} created successfully in realm ${realm_name}"
        return 0
    else
        log_error "Failed to create client ${client_id} in realm ${realm_name}"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting Keycloak configuration for environment: ${ENV}"
    log_info "Domain: ${DOMAIN}"
    
    # Wait for Keycloak to be ready
    if ! wait_for_keycloak; then
        log_error "Keycloak is not ready, exiting"
        exit 1
    fi
    
    # Get admin credentials
    if ! get_admin_credentials; then
        log_error "Failed to get admin credentials, exiting"
        exit 1
    fi
    
    # Get admin token
    if ! get_admin_token; then
        log_error "Failed to get admin token, exiting"
        exit 1
    fi
    
    # Create dnd realm
    log_info "Configuring D&D realm..."
    if create_realm "dnd" "D&D Application"; then
        # Create dnd-client
        create_client "dnd" "dnd-client" "https://${DOMAIN}/ttrpg/dnd/*"
    fi
    
    # Create sprint-management realm
    log_info "Configuring Sprint Management realm..."
    if create_realm "sprint-management" "Sprint Management Application"; then
        # Create sprint-client
        create_client "sprint-management" "sprint-client" "https://${DOMAIN}/ttrpg/sprint-management/*"
    fi
    
    log_info "Keycloak configuration completed successfully!"
}

# Run main function
main "$@"
