#!/bin/bash
# Unseal Vault using keys from sealed secret or vault-init-keys.json
# Usage: ./unseal-vault.sh [ENV]
# ENV: local, dev, or prod (default: local)

set -e

ENV="${1:-local}"
VAULT_NAMESPACE="security"

echo "=== Unsealing Vault for environment: ${ENV} ==="

# Check if Vault pod is running
echo "Checking Vault pod status..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n ${VAULT_NAMESPACE} --timeout=300s || true

# Port forward to Vault
echo "Setting up port forward to Vault..."
kubectl port-forward -n ${VAULT_NAMESPACE} svc/vault 8200:8200 &
PF_PID=$!
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'

# Check if Vault is sealed
if vault status 2>/dev/null | grep -q "Sealed.*false"; then
  echo "Vault is already unsealed"
  kill ${PF_PID} 2>/dev/null || true
  exit 0
fi

echo "Vault is sealed. Attempting to unseal..."

# Try to get unseal keys from sealed secret first
if kubectl get secret vault-unseal-keys -n ${VAULT_NAMESPACE} &>/dev/null; then
  echo "Using unseal keys from sealed secret..."
  
  UNSEAL_KEY_1=$(kubectl get secret vault-unseal-keys -n ${VAULT_NAMESPACE} -o jsonpath='{.data.key1}' | base64 -d)
  UNSEAL_KEY_2=$(kubectl get secret vault-unseal-keys -n ${VAULT_NAMESPACE} -o jsonpath='{.data.key2}' | base64 -d)
  UNSEAL_KEY_3=$(kubectl get secret vault-unseal-keys -n ${VAULT_NAMESPACE} -o jsonpath='{.data.key3}' | base64 -d)
  
elif [ -f "vault-init-keys.json" ]; then
  echo "Using unseal keys from vault-init-keys.json..."
  
  UNSEAL_KEY_1=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[0]')
  UNSEAL_KEY_2=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[1]')
  UNSEAL_KEY_3=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[2]')
  
else
  echo "ERROR: No unseal keys found!"
  echo "Please provide unseal keys manually or run init-vault.sh first"
  kill ${PF_PID} 2>/dev/null || true
  exit 1
fi

# Unseal Vault
echo "Unsealing Vault with key 1..."
vault operator unseal ${UNSEAL_KEY_1}

echo "Unsealing Vault with key 2..."
vault operator unseal ${UNSEAL_KEY_2}

echo "Unsealing Vault with key 3..."
vault operator unseal ${UNSEAL_KEY_3}

# Check status
if vault status | grep -q "Sealed.*false"; then
  echo "=== Vault successfully unsealed ==="
else
  echo "ERROR: Vault is still sealed"
  vault status
  kill ${PF_PID} 2>/dev/null || true
  exit 1
fi

# Cleanup port forward
kill ${PF_PID} 2>/dev/null || true
