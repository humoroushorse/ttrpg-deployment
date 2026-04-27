#!/usr/bin/env bash

# Bootstrap Cloudflare Tunnel
# This script creates a Cloudflare Tunnel and stores credentials in Vault
#
# Prerequisites:
# - cloudflared CLI installed
# - Cloudflare API token with Tunnel permissions
# - Vault CLI installed and authenticated
# - kubectl configured with cluster access
#
# Usage:
#   ./bootstrap-cloudflare-tunnel.sh <environment> <tunnel-name> <domain>
#
# Example:
#   ./bootstrap-cloudflare-tunnel.sh dev ttrpg-dev dev.mysite.com

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [ $# -ne 3 ]; then
    log_error "Usage: $0 <environment> <tunnel-name> <domain>"
    log_error "Example: $0 dev ttrpg-dev dev.mysite.com"
    exit 1
fi

ENVIRONMENT="$1"
TUNNEL_NAME="$2"
DOMAIN="$3"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(local|dev|prod)$ ]]; then
    log_error "Environment must be one of: local, dev, prod"
    exit 1
fi

log_info "Bootstrapping Cloudflare Tunnel for environment: $ENVIRONMENT"
log_info "Tunnel name: $TUNNEL_NAME"
log_info "Domain: $DOMAIN"

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v cloudflared &> /dev/null; then
    log_error "cloudflared CLI not found. Install from: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/"
    exit 1
fi

if ! command -v vault &> /dev/null; then
    log_error "vault CLI not found. Install from: https://www.vaultproject.io/downloads"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Install from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq not found. Install from: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Check if Cloudflare API token is set
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    log_error "CLOUDFLARE_API_TOKEN environment variable not set"
    log_error "Create a token at: https://dash.cloudflare.com/profile/api-tokens"
    log_error "Required permissions: Account.Cloudflare Tunnel:Edit"
    exit 1
fi

# Check if Vault is accessible
if ! vault status &> /dev/null; then
    log_error "Cannot connect to Vault. Ensure VAULT_ADDR and VAULT_TOKEN are set"
    log_error "Example: export VAULT_ADDR=http://localhost:8200"
    exit 1
fi

log_info "All prerequisites met"

# Create temporary directory for tunnel files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log_info "Creating Cloudflare Tunnel..."

# Login to Cloudflare (if not already logged in)
if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
    log_info "Logging in to Cloudflare..."
    cloudflared tunnel login
fi

# Check if tunnel already exists
EXISTING_TUNNEL=$(cloudflared tunnel list --output json 2>/dev/null | jq -r ".[] | select(.name == \"$TUNNEL_NAME\") | .id" || echo "")

if [ -n "$EXISTING_TUNNEL" ]; then
    log_warn "Tunnel '$TUNNEL_NAME' already exists with ID: $EXISTING_TUNNEL"
    TUNNEL_ID="$EXISTING_TUNNEL"
    
    # Get existing credentials
    log_info "Retrieving existing tunnel credentials..."
    CREDENTIALS_FILE="$HOME/.cloudflared/$TUNNEL_ID.json"
    
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        log_error "Credentials file not found at: $CREDENTIALS_FILE"
        log_error "You may need to delete and recreate the tunnel"
        exit 1
    fi
else
    # Create new tunnel
    log_info "Creating new tunnel..."
    TUNNEL_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
    
    # Extract tunnel ID from output
    TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oP 'Created tunnel .* with id \K[a-f0-9-]+' || echo "")
    
    if [ -z "$TUNNEL_ID" ]; then
        log_error "Failed to create tunnel. Output:"
        echo "$TUNNEL_OUTPUT"
        exit 1
    fi
    
    log_info "Tunnel created with ID: $TUNNEL_ID"
    
    # Credentials file location
    CREDENTIALS_FILE="$HOME/.cloudflared/$TUNNEL_ID.json"
fi

# Verify credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
    log_error "Credentials file not found at: $CREDENTIALS_FILE"
    exit 1
fi

log_info "Reading tunnel credentials..."
CREDENTIALS=$(cat "$CREDENTIALS_FILE")

# Validate credentials JSON
if ! echo "$CREDENTIALS" | jq empty 2>/dev/null; then
    log_error "Invalid JSON in credentials file"
    exit 1
fi

# Store credentials in Vault
log_info "Storing credentials in Vault..."

VAULT_PATH="${ENVIRONMENT}/cloudflare/tunnel"

# Create JSON payload for Vault
VAULT_PAYLOAD=$(jq -n \
    --arg tunnel_id "$TUNNEL_ID" \
    --arg tunnel_name "$TUNNEL_NAME" \
    --arg domain "$DOMAIN" \
    --argjson credentials "$CREDENTIALS" \
    '{
        tunnel_id: $tunnel_id,
        tunnel_name: $tunnel_name,
        domain: $domain,
        credentials: $credentials
    }')

# Write to Vault
if vault kv put "$VAULT_PATH" - <<< "$VAULT_PAYLOAD" &> /dev/null; then
    log_info "Credentials stored in Vault at: $VAULT_PATH"
else
    log_error "Failed to store credentials in Vault"
    exit 1
fi

# Configure DNS (optional - requires Cloudflare API)
log_info "Configuring DNS..."
log_warn "You need to create a CNAME record for your domain:"
log_warn "  Name: $DOMAIN (or subdomain)"
log_warn "  Target: $TUNNEL_ID.cfargotunnel.com"
log_warn "  Proxied: Yes (orange cloud)"

# Create DNS record automatically if CLOUDFLARE_ZONE_ID is set
if [ -n "${CLOUDFLARE_ZONE_ID:-}" ]; then
    log_info "CLOUDFLARE_ZONE_ID set, attempting to create DNS record..."
    
    # Extract subdomain from domain
    RECORD_NAME=$(echo "$DOMAIN" | cut -d'.' -f1)
    
    DNS_PAYLOAD=$(jq -n \
        --arg name "$DOMAIN" \
        --arg target "$TUNNEL_ID.cfargotunnel.com" \
        '{
            type: "CNAME",
            name: $name,
            content: $target,
            ttl: 1,
            proxied: true
        }')
    
    DNS_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$DNS_PAYLOAD")
    
    if echo "$DNS_RESPONSE" | jq -e '.success' &> /dev/null; then
        log_info "DNS record created successfully"
    else
        log_warn "Failed to create DNS record automatically"
        log_warn "Response: $(echo "$DNS_RESPONSE" | jq -r '.errors[0].message // "Unknown error"')"
        log_warn "Please create the DNS record manually"
    fi
else
    log_warn "Set CLOUDFLARE_ZONE_ID to automatically create DNS records"
fi

# Create Kubernetes secret with tunnel ID (for Helm values)
log_info "Creating Kubernetes secret..."

NAMESPACE="ttrpg-${ENVIRONMENT}"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_warn "Namespace $NAMESPACE does not exist, creating it..."
    kubectl create namespace "$NAMESPACE"
fi

# Create or update secret
kubectl create secret generic cloudflare-tunnel \
    --from-literal=tunnel-id="$TUNNEL_ID" \
    --from-literal=domain="$DOMAIN" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

log_info "Kubernetes secret created in namespace: $NAMESPACE"

# Print summary
echo ""
log_info "=========================================="
log_info "Cloudflare Tunnel Bootstrap Complete!"
log_info "=========================================="
echo ""
echo "Tunnel Details:"
echo "  Name: $TUNNEL_NAME"
echo "  ID: $TUNNEL_ID"
echo "  Domain: $DOMAIN"
echo "  Environment: $ENVIRONMENT"
echo ""
echo "Vault Path: $VAULT_PATH"
echo "Kubernetes Secret: cloudflare-tunnel (namespace: $NAMESPACE)"
echo ""
echo "Next Steps:"
echo "  1. Verify DNS record is created and proxied through Cloudflare"
echo "  2. Deploy the Helm chart with cloudflare.enabled=true"
echo "  3. Set cloudflare.tunnel.id=$TUNNEL_ID in your values"
echo "  4. Monitor tunnel status: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=cloudflare-tunnel"
echo ""
echo "To deploy with Helm:"
echo "  helm upgrade --install ttrpg charts/ttrpg-umbrella \\"
echo "    --values charts/ttrpg-umbrella/values-${ENVIRONMENT}.yaml \\"
echo "    --set cloudflare.enabled=true \\"
echo "    --set cloudflare.tunnel.id=$TUNNEL_ID \\"
echo "    --set cloudflare.tunnel.domain=$DOMAIN \\"
echo "    --namespace $NAMESPACE"
echo ""

log_info "Bootstrap complete!"
