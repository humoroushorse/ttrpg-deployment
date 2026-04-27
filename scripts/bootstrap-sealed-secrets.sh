#!/bin/bash
set -euo pipefail

# Bootstrap Sealed Secrets
# This script installs kubeseal CLI and creates initial sealed secrets

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-kube-system}"
KUBESEAL_VERSION="${KUBESEAL_VERSION:-0.24.0}"

echo "=== Sealed Secrets Bootstrap ==="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install kubeseal CLI if not present
install_kubeseal() {
    if command_exists kubeseal; then
        echo "✓ kubeseal already installed: $(kubeseal --version)"
        return 0
    fi

    echo "Installing kubeseal CLI..."
    
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    DOWNLOAD_URL="https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-${OS}-${ARCH}.tar.gz"
    
    echo "Downloading from: $DOWNLOAD_URL"
    curl -sL "$DOWNLOAD_URL" | tar xz -C /tmp
    
    sudo mv /tmp/kubeseal /usr/local/bin/kubeseal
    sudo chmod +x /usr/local/bin/kubeseal
    
    echo "✓ kubeseal installed: $(kubeseal --version)"
}

# Wait for sealed-secrets controller to be ready
wait_for_controller() {
    echo "Waiting for sealed-secrets controller to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/sealed-secrets-controller -n "$NAMESPACE" || {
        echo "ERROR: Sealed Secrets controller not ready"
        exit 1
    }
    echo "✓ Sealed Secrets controller is ready"
}

# Create sealed secret from literal values
create_sealed_secret() {
    local name=$1
    local namespace=$2
    local key=$3
    local value=$4
    
    echo "Creating sealed secret: $name in namespace $namespace"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create sealed secret
    kubectl create secret generic "$name" \
        --from-literal="$key=$value" \
        --namespace="$namespace" \
        --dry-run=client -o yaml | \
    kubeseal --controller-namespace="$NAMESPACE" \
        --controller-name=sealed-secrets-controller \
        --format yaml > "/tmp/${name}-sealed.yaml"
    
    # Apply sealed secret
    kubectl apply -f "/tmp/${name}-sealed.yaml"
    
    echo "✓ Sealed secret $name created"
}

# Create sealed secret for Vault unseal keys
create_vault_unseal_secret() {
    local env="${1:-local}"
    local namespace="vault"
    
    echo "Creating Vault unseal keys sealed secret for environment: $env"
    
    # Check if unseal keys file exists
    if [ ! -f "$SCRIPT_DIR/../vault-unseal-keys-${env}.json" ]; then
        echo "WARNING: Vault unseal keys file not found: vault-unseal-keys-${env}.json"
        echo "You'll need to initialize Vault first and then run this script again"
        return 0
    fi
    
    # Read unseal keys from file
    UNSEAL_KEYS=$(cat "$SCRIPT_DIR/../vault-unseal-keys-${env}.json")
    
    # Create sealed secret
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create secret generic "vault-unseal-keys" \
        --from-literal="keys.json=$UNSEAL_KEYS" \
        --namespace="$namespace" \
        --dry-run=client -o yaml | \
    kubeseal --controller-namespace="$NAMESPACE" \
        --controller-name=sealed-secrets-controller \
        --format yaml > "/tmp/vault-unseal-keys-sealed.yaml"
    
    kubectl apply -f "/tmp/vault-unseal-keys-sealed.yaml"
    
    echo "✓ Vault unseal keys sealed secret created"
}

# Create sealed secret for Cloudflare tunnel credentials
create_cloudflare_tunnel_secret() {
    local env="${1:-dev}"
    local namespace="ttrpg-${env}"
    
    echo "Creating Cloudflare tunnel credentials sealed secret for environment: $env"
    
    # Check if credentials file exists
    if [ ! -f "$SCRIPT_DIR/../cloudflare-tunnel-${env}.json" ]; then
        echo "WARNING: Cloudflare tunnel credentials file not found: cloudflare-tunnel-${env}.json"
        echo "Run bootstrap-cloudflare-tunnel.sh first"
        return 0
    fi
    
    # Read credentials from file
    TUNNEL_CREDS=$(cat "$SCRIPT_DIR/../cloudflare-tunnel-${env}.json")
    
    # Create sealed secret
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create secret generic "cloudflare-tunnel-credentials" \
        --from-literal="credentials.json=$TUNNEL_CREDS" \
        --namespace="$namespace" \
        --dry-run=client -o yaml | \
    kubeseal --controller-namespace="$NAMESPACE" \
        --controller-name=sealed-secrets-controller \
        --format yaml > "/tmp/cloudflare-tunnel-credentials-sealed.yaml"
    
    kubectl apply -f "/tmp/cloudflare-tunnel-credentials-sealed.yaml"
    
    echo "✓ Cloudflare tunnel credentials sealed secret created"
}

# Main execution
main() {
    local env="${1:-local}"
    
    echo "Environment: $env"
    
    # Install kubeseal
    install_kubeseal
    
    # Wait for controller
    wait_for_controller
    
    # Create sealed secrets
    if [ "$env" != "local" ]; then
        create_vault_unseal_secret "$env"
    fi
    
    if [ "$env" = "dev" ] || [ "$env" = "prod" ]; then
        create_cloudflare_tunnel_secret "$env"
    fi
    
    echo ""
    echo "=== Bootstrap Complete ==="
    echo "Sealed Secrets controller is ready"
    echo ""
    echo "To create additional sealed secrets:"
    echo "  kubectl create secret generic <name> --from-literal=<key>=<value> --dry-run=client -o yaml | \\"
    echo "    kubeseal --controller-namespace=$NAMESPACE --format yaml | \\"
    echo "    kubectl apply -f -"
}

# Run main with environment argument
main "${1:-local}"
