#!/bin/bash
# Initialize Vault and configure Kubernetes auth method
# Usage: ./init-vault.sh [ENV]
# ENV: local, dev, or prod (default: local)

set -e

ENV="${1:-local}"
VAULT_NAMESPACE="security"

echo "=== Initializing Vault for environment: ${ENV} ==="

# Check if Vault pod is running
echo "Checking Vault pod status..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n ${VAULT_NAMESPACE} --timeout=300s

# Port forward to Vault
echo "Setting up port forward to Vault..."
kubectl port-forward -n ${VAULT_NAMESPACE} svc/vault 8200:8200 &
PF_PID=$!
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'

# For local environment, use dev mode with root token
if [ "${ENV}" = "local" ]; then
  echo "Using dev mode Vault with root token"
  ROOT_TOKEN="root"
  export VAULT_TOKEN=${ROOT_TOKEN}
else
  # Check if Vault is already initialized
  if vault status 2>/dev/null | grep -q "Initialized.*true"; then
    echo "Vault is already initialized"
  else
    echo "Initializing Vault..."
    
    # Initialize Vault with 5 key shares and 3 key threshold
    vault operator init \
      -key-shares=5 \
      -key-threshold=3 \
      -format=json > vault-init-keys.json
    
    echo "Vault initialized. Keys saved to vault-init-keys.json"
    echo "IMPORTANT: Store these keys securely!"
    
    # Extract unseal keys and root token
    UNSEAL_KEY_1=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[0]')
    UNSEAL_KEY_2=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[1]')
    UNSEAL_KEY_3=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[2]')
    ROOT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')
    
    # Unseal Vault
    echo "Unsealing Vault..."
    vault operator unseal ${UNSEAL_KEY_1}
    vault operator unseal ${UNSEAL_KEY_2}
    vault operator unseal ${UNSEAL_KEY_3}
    
    # Login with root token and export token
    export VAULT_TOKEN=${ROOT_TOKEN}
    vault login ${ROOT_TOKEN}
    
    echo "Vault unsealed and logged in"
  fi

  # If already initialized, get the root token from the file
  if [ -f "vault-init-keys.json" ]; then
    ROOT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')
    export VAULT_TOKEN=${ROOT_TOKEN}
    echo "Using existing root token from vault-init-keys.json"
  else
    echo "ERROR: vault-init-keys.json not found"
    kill ${PF_PID} 2>/dev/null || true
    exit 1
  fi
fi

# Configure Kubernetes auth method
echo "Configuring Kubernetes auth method..."

# Enable Kubernetes auth if not already enabled
if ! vault auth list | grep -q "kubernetes/"; then
  vault auth enable kubernetes
fi

# Configure Kubernetes auth
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

# Create Vault policies and roles for applications
echo "Creating Vault policies and roles..."

# Define app namespace based on environment
if [ "${ENV}" = "local" ]; then
  APP_NAMESPACE="apps"
else
  APP_NAMESPACE="apps"
fi

for APP in go-auth go-sprint py-dnd; do
  echo "Creating Vault role for ${APP}..."
  
  # Create Vault role for the application
  vault write auth/kubernetes/role/${APP} \
    bound_service_account_names=${APP} \
    bound_service_account_namespaces=${APP_NAMESPACE} \
    policies=default,${APP}-policy \
    ttl=1h
  
  echo "Vault role created for ${APP}"
done

echo "=== Vault initialization complete ==="
echo ""
echo "Next steps:"
echo "1. Run make configure-vault ENV=${ENV} to configure database secrets engine"
echo ""
echo "Vault UI: http://localhost:8200"
if [ "${ENV}" = "local" ]; then
  echo "Root token: root"
else
  echo "Root token: $(cat vault-init-keys.json | jq -r '.root_token')"
fi

# Cleanup port forward
kill ${PF_PID} 2>/dev/null || true
