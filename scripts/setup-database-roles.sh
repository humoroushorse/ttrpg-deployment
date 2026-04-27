#!/bin/bash
# Setup database roles in Vault for dynamic credential generation
# This script configures Vault database secrets engine with roles for each application
# Usage: ./setup-database-roles.sh [ENV]
# ENV: local, dev, or prod (default: local)

set -e

ENV="${1:-local}"
APP_NAMESPACE="ttrpg-${ENV}"
VAULT_NAMESPACE="vault"

echo "=== Setting up Vault database roles for environment: ${ENV} ==="

# Check if Vault is available
if ! kubectl get pod -n ${VAULT_NAMESPACE} -l app.kubernetes.io/name=vault &>/dev/null; then
  echo "ERROR: Vault is not deployed. Please deploy Vault first."
  exit 1
fi

# Port forward to Vault
echo "Setting up port forward to Vault..."
kubectl port-forward -n ${VAULT_NAMESPACE} svc/vault 8200:8200 &
VAULT_PF_PID=$!
sleep 3

export VAULT_ADDR="http://localhost:8200"

# Check if Vault is unsealed
if ! vault status &>/dev/null; then
  echo "ERROR: Vault is sealed or not accessible. Please unseal Vault first."
  kill ${VAULT_PF_PID} 2>/dev/null || true
  exit 1
fi

echo "Configuring PostgreSQL database secrets engine..."

# Configure database connection
# The connection URL uses Vault's template syntax for username and password
vault write database/config/postgresql \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgresql.${APP_NAMESPACE}.svc.cluster.local:5432/postgres?sslmode=disable" \
  allowed_roles="go-auth-role,go-sprint-role,py-dnd-role,keycloak-role" \
  username="vault_admin" \
  password="TEMPORARY_PASSWORD_WILL_BE_ROTATED" \
  password_policy="unicode-password-policy" \
  username_template="{{.RoleName}}_{{random 8}}"

echo "Enabling root credential rotation..."
# This will cause Vault to immediately rotate the vault_admin password
vault write -force database/rotate-root/postgresql

echo "Creating database role for go-auth..."
vault write database/roles/go-auth-role \
  db_name=postgresql \
  creation_statements="CREATE USER \"{{name}}\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT CONNECT ON DATABASE auth TO \"{{name}}\"; \
    GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\"; \
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

echo "Creating database role for go-sprint..."
vault write database/roles/go-sprint-role \
  db_name=postgresql \
  creation_statements="CREATE USER \"{{name}}\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT CONNECT ON DATABASE sprint_management TO \"{{name}}\"; \
    GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\"; \
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

echo "Creating database role for py-dnd..."
vault write database/roles/py-dnd-role \
  db_name=postgresql \
  creation_statements="CREATE USER \"{{name}}\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT CONNECT ON DATABASE dnd TO \"{{name}}\"; \
    GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\"; \
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

echo "Creating database role for keycloak..."
vault write database/roles/keycloak-role \
  db_name=postgresql \
  creation_statements="CREATE USER \"{{name}}\" WITH PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT CONNECT ON DATABASE keycloak TO \"{{name}}\"; \
    GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\"; \
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

echo "Creating Vault policies for applications..."

# Policy for go-auth
vault policy write go-auth-policy - <<EOF
path "${ENV}/database/creds/go-auth-role" {
  capabilities = ["read"]
}
EOF

# Policy for go-sprint
vault policy write go-sprint-policy - <<EOF
path "${ENV}/database/creds/go-sprint-role" {
  capabilities = ["read"]
}
EOF

# Policy for py-dnd
vault policy write py-dnd-policy - <<EOF
path "${ENV}/database/creds/py-dnd-role" {
  capabilities = ["read"]
}
EOF

# Policy for keycloak
vault policy write keycloak-policy - <<EOF
path "${ENV}/database/creds/keycloak-role" {
  capabilities = ["read"]
}
EOF

echo "Testing credential generation..."
echo "Generating test credentials for go-auth..."
vault read database/creds/go-auth-role

echo ""
echo "=== Vault database roles setup complete ==="
echo ""
echo "Summary:"
echo "- PostgreSQL database secrets engine configured"
echo "- Root credentials rotated (vault_admin password changed by Vault)"
echo "- Database roles created: go-auth-role, go-sprint-role, py-dnd-role, keycloak-role"
echo "- Vault policies created for each application"
echo "- Default TTL: 1 hour, Max TTL: 24 hours"
echo ""
echo "Applications can now request dynamic database credentials from Vault."
echo "Credentials will be automatically rotated before expiration."

# Cleanup port forward
kill ${VAULT_PF_PID} 2>/dev/null || true
