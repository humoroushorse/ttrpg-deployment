#!/bin/bash
# Configure Vault with database secrets engine and policies
# Usage: ./vault-configure.sh [ENV]
# ENV: local, dev, or prod (default: local)

set -e

ENV="${1:-local}"
VAULT_NAMESPACE="security"
PLATFORM_NAMESPACE="platform"
# Use cluster-internal DNS for PostgreSQL
PG_HOST="platform-postgresql.${PLATFORM_NAMESPACE}.svc.cluster.local"
PG_PORT="5432"

echo "=== Configuring Vault for environment: ${ENV} ==="

# Check if Vault pod is ready
echo "Checking Vault pod status..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n ${VAULT_NAMESPACE} --timeout=300s

# Get root token based on environment
if [ "${ENV}" = "local" ]; then
  ROOT_TOKEN="root"
  echo "Using dev mode root token"
else
  if [ -f "vault-init-keys.json" ]; then
    ROOT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')
  else
    echo "ERROR: vault-init-keys.json not found. Please run init-vault.sh first"
    exit 1
  fi
fi

# Set Vault address for in-cluster access
VAULT_ADDR="http://vault.${VAULT_NAMESPACE}.svc.cluster.local:8200"

# Create password policy with standard characters
echo "Creating password policy..."
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault write sys/policies/password/standard-password-policy policy=-<<'EOF'
length = 32
rule \"charset\" {
  charset = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()_+-=[]{}|;:,.<>?\"
  min-chars = 1
}
EOF
"

# Enable database secrets engine
echo "Enabling database secrets engine..."
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
if ! vault secrets list | grep -q 'database/'; then
  vault secrets enable database
fi
"

# Get PostgreSQL password from Kubernetes secret or use default
echo "Retrieving PostgreSQL password..."
# First, try to get the postgres password from the environment variable in the pod
PG_PASSWORD=$(kubectl exec -n ${PLATFORM_NAMESPACE} platform-postgresql-0 -- sh -c 'echo $POSTGRES_PASSWORD' 2>/dev/null || echo "TEMPORARY_PASSWORD_WILL_BE_ROTATED")

# Set initial password for vault_admin if it doesn't have one
echo "Setting initial password for vault_admin user..."
kubectl exec -n ${PLATFORM_NAMESPACE} platform-postgresql-0 -- psql -U postgres -c "ALTER USER vault_admin WITH PASSWORD '${PG_PASSWORD}';" 2>/dev/null || true

# Configure PostgreSQL connection
echo "Configuring PostgreSQL connection..."
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault write database/config/postgresql \
  plugin_name=postgresql-database-plugin \
  allowed_roles='go-auth-role,go-sprint-role,py-dnd-role,keycloak-role' \
  connection_url='postgresql://{{username}}:{{password}}@${PG_HOST}:${PG_PORT}/postgres?sslmode=disable' \
  username='vault_admin' \
  password='${PG_PASSWORD}' \
  password_policy='standard-password-policy'
"

# Enable root credential rotation
echo "Enabling root credential rotation..."
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault write -force database/rotate-root/postgresql
"

echo "Root credentials rotated. Vault now manages the vault_admin password."

# Create database roles for each application
echo "Creating database roles..."

# go-auth role
# Note: creation_statements run against 'postgres' DB (Vault's connection).
# GRANT ALL PRIVILEGES ON DATABASE gives CREATE privilege (allows schema creation).
# Schema-level grants are applied separately below via direct psql against each target DB.
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault write database/roles/go-auth-role \
  db_name=postgresql \
  creation_statements=\"CREATE USER \\\"{{name}}\\\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT ALL PRIVILEGES ON DATABASE auth TO \\\"{{name}}\\\";\" \
  default_ttl='1h' \
  max_ttl='24h'
"

# go-sprint role
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault write database/roles/go-sprint-role \
  db_name=postgresql \
  creation_statements=\"CREATE USER \\\"{{name}}\\\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT ALL PRIVILEGES ON DATABASE sprint_management TO \\\"{{name}}\\\";\" \
  default_ttl='1h' \
  max_ttl='24h'
"

# py-dnd role
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault write database/roles/py-dnd-role \
  db_name=postgresql \
  creation_statements=\"CREATE USER \\\"{{name}}\\\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT ALL PRIVILEGES ON DATABASE dnd TO \\\"{{name}}\\\";\" \
  default_ttl='1h' \
  max_ttl='24h'
"

# keycloak role
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault write database/roles/keycloak-role \
  db_name=postgresql \
  creation_statements=\"CREATE USER \\\"{{name}}\\\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT ALL PRIVILEGES ON DATABASE keycloak TO \\\"{{name}}\\\";\" \
  default_ttl='1h' \
  max_ttl='24h'
"

# Grant schema-level permissions inside each target database.
# Vault dynamic users get DATABASE-level ALL (includes CREATE for new schemas),
# but also need usage/create on existing schemas within those databases.
# These run as postgres superuser directly against each target DB.
echo "Granting schema-level permissions in target databases..."

# auth DB — uses public schema
kubectl exec -n ${PLATFORM_NAMESPACE} platform-postgresql-0 -- psql -U postgres -d auth -c "
  GRANT ALL ON SCHEMA public TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO PUBLIC;
" 2>/dev/null || true

# sprint_management DB — uses sprint_management schema (created by migration 000001)
# Pre-create the schema so Vault dynamic users can use it without needing CREATE SCHEMA
kubectl exec -n ${PLATFORM_NAMESPACE} platform-postgresql-0 -- psql -U postgres -d sprint_management -c "
  CREATE SCHEMA IF NOT EXISTS sprint_management;
  GRANT ALL ON SCHEMA sprint_management TO PUBLIC;
  GRANT ALL ON SCHEMA public TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA sprint_management GRANT ALL ON TABLES TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA sprint_management GRANT ALL ON SEQUENCES TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA sprint_management GRANT ALL ON FUNCTIONS TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO PUBLIC;
" 2>/dev/null || true

# dnd DB — uses public schema
kubectl exec -n ${PLATFORM_NAMESPACE} platform-postgresql-0 -- psql -U postgres -d dnd -c "
  GRANT ALL ON SCHEMA public TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO PUBLIC;
" 2>/dev/null || true

# keycloak DB — uses public schema
kubectl exec -n ${PLATFORM_NAMESPACE} platform-postgresql-0 -- psql -U postgres -d keycloak -c "
  GRANT ALL ON SCHEMA public TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO PUBLIC;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO PUBLIC;
" 2>/dev/null || true

# Create Vault policies for each application
echo "Creating Vault policies..."

# go-auth policy
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault policy write go-auth-policy -<<'EOF'
path \"database/creds/go-auth-role\" {
  capabilities = [\"read\"]
}
EOF
"

# go-sprint policy
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault policy write go-sprint-policy -<<'EOF'
path \"database/creds/go-sprint-role\" {
  capabilities = [\"read\"]
}
EOF
"

# py-dnd policy
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault policy write py-dnd-policy -<<'EOF'
path \"database/creds/py-dnd-role\" {
  capabilities = [\"read\"]
}
EOF
"

# keycloak policy
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault policy write keycloak-policy -<<'EOF'
path \"database/creds/keycloak-role\" {
  capabilities = [\"read\"]
}
path \"${ENV}/keycloak/admin\" {
  capabilities = [\"read\"]
}
EOF
"

# cloudflare policy
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault policy write cloudflare-policy -<<'EOF'
path \"${ENV}/cloudflare/tunnel\" {
  capabilities = [\"read\"]
}
EOF
"

# postgresql policy
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault policy write postgresql-policy -<<'EOF'
path \"${ENV}/postgres-root/creds\" {
  capabilities = [\"read\"]
}
EOF
"

# Enable KV v2 secrets engine for static secrets
echo "Enabling KV v2 secrets engine..."
kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
if ! vault secrets list | grep -q '^${ENV}/'; then
  vault secrets enable -path=${ENV} kv-v2
fi
"

# Create placeholder secrets (these should be replaced with real values)
echo "Creating placeholder secrets..."

kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault kv put ${ENV}/keycloak/admin \
  username=admin \
  password=changeme
"

kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault kv put ${ENV}/postgres-root/creds \
  password=changeme
"

kubectl exec -n ${VAULT_NAMESPACE} vault-0 -- sh -c "
export VAULT_ADDR='${VAULT_ADDR}'
export VAULT_TOKEN='${ROOT_TOKEN}'
vault kv put ${ENV}/cloudflare/tunnel \
  credentials='{\"AccountTag\":\"\",\"TunnelSecret\":\"\",\"TunnelID\":\"\"}'
"

echo "=== Vault configuration complete ==="
echo ""
echo "IMPORTANT: Update the following secrets with real values:"
echo "  - ${ENV}/keycloak/admin"
echo "  - ${ENV}/postgres-root/creds"
echo "  - ${ENV}/cloudflare/tunnel"
echo ""
echo "Test database credential generation (via port-forward):"
echo "  kubectl port-forward -n ${VAULT_NAMESPACE} svc/vault 8200:8200 &"
echo "  export VAULT_ADDR='http://127.0.0.1:8200'"
echo "  export VAULT_TOKEN='${ROOT_TOKEN}'"
echo "  vault read database/creds/go-auth-role"
echo "  vault read database/creds/go-sprint-role"
echo "  vault read database/creds/py-dnd-role"

