# Vault Management Scripts

This directory contains scripts for managing HashiCorp Vault in the TTRPG deployment.

## Prerequisites

- `kubectl` configured with access to your Kubernetes cluster
- `vault` CLI installed ([installation guide](https://www.vaultproject.io/downloads))
- `jq` for JSON processing
- `psql` for PostgreSQL operations (setup-database-roles.sh)
- `gpg` for backup encryption (optional)

## Scripts Overview

### 1. init-vault.sh
Initializes Vault and configures Kubernetes auth method.

**Usage:**
```bash
./init-vault.sh [ENV]
```

**What it does:**
- Checks if Vault pod is running
- Initializes Vault with 5 key shares and 3 key threshold
- Saves unseal keys and root token to `vault-init-keys.json`
- Unseals Vault
- Enables and configures Kubernetes auth method
- Creates service accounts for all applications
- Creates Vault roles for each application

**Environment:** local (default), dev, or prod

**Output:** `vault-init-keys.json` - **STORE THIS SECURELY!**

### 2. unseal-vault.sh
Unseals Vault using stored keys.

**Usage:**
```bash
./unseal-vault.sh [ENV]
```

**What it does:**
- Checks if Vault is sealed
- Retrieves unseal keys from sealed secret or `vault-init-keys.json`
- Unseals Vault with 3 keys
- Verifies Vault is unsealed

**Key Sources (in order of preference):**
1. Kubernetes sealed secret: `vault-unseal-keys`
2. Local file: `vault-init-keys.json`

### 3. vault-configure.sh
Configures Vault with database secrets engine and policies.

**Usage:**
```bash
./vault-configure.sh [ENV]
```

**What it does:**
- Creates Unicode password policy (32 chars, Latin/Greek/Cyrillic/symbols)
- Enables database secrets engine
- Configures PostgreSQL connection
- Rotates root credentials (Vault takes over `vault_admin` password)
- Creates database roles for each application:
  - `go-auth-role` → auth database
  - `go-sprint-role` → sprint_management database
  - `py-dnd-role` → dnd database
  - `keycloak-role` → keycloak database
- Creates Vault policies for least-privilege access
- Enables KV v2 secrets engine for static secrets
- Creates placeholder secrets for Keycloak, PostgreSQL, Cloudflare

**Credential TTL:**
- Default: 1 hour
- Maximum: 24 hours
- Automatic rotation before expiration

### 4. setup-database-roles.sh
Sets up PostgreSQL roles and permissions for Vault.

**Usage:**
```bash
./setup-database-roles.sh [ENV]
```

**What it does:**
- Creates `vault_admin` superuser in PostgreSQL
- Grants permissions on all databases (auth, sprint_management, dnd, keycloak)
- Configures default privileges for future tables/sequences

**Run this BEFORE vault-configure.sh**

### 5. backup-vault.sh
Creates a Raft snapshot backup of Vault data.

**Usage:**
```bash
./backup-vault.sh [ENV] [BACKUP_DIR]
```

**What it does:**
- Takes Raft snapshot of Vault data
- Optionally encrypts with GPG (AES256)
- Stores backup with timestamp
- Cleans up old backups (7 days for dev, 30 days for prod)

**Backup Location:** `./backups/vault-backup-{ENV}-{TIMESTAMP}.snap[.gpg]`

**Encryption:** Automatic if GPG is installed

### 6. restore-vault.sh
Restores Vault from a Raft snapshot backup.

**Usage:**
```bash
./restore-vault.sh [ENV] [BACKUP_FILE]
```

**What it does:**
- Decrypts backup if encrypted
- Restores Vault from snapshot
- Prompts for confirmation before restore

**WARNING:** This replaces all current Vault data!

### 7. bootstrap-cloudflare-tunnel.sh
Creates a Cloudflare Tunnel and stores credentials in Vault.

**Usage:**
```bash
./bootstrap-cloudflare-tunnel.sh <environment> <tunnel-name> <domain>
```

**Example:**
```bash
./bootstrap-cloudflare-tunnel.sh dev ttrpg-dev dev.mysite.com
```

**What it does:**
- Creates a new Cloudflare Tunnel (or uses existing)
- Retrieves tunnel credentials
- Stores credentials in Vault at `{env}/cloudflare/tunnel`
- Creates Kubernetes secret with tunnel ID
- Optionally creates DNS CNAME record

**Prerequisites:**
- `cloudflared` CLI installed
- `CLOUDFLARE_API_TOKEN` environment variable set
- Cloudflare API token with Tunnel permissions
- Vault CLI authenticated
- (Optional) `CLOUDFLARE_ZONE_ID` for automatic DNS creation

**Output:**
- Vault secret at `{env}/cloudflare/tunnel`
- Kubernetes secret `cloudflare-tunnel` in namespace `ttrpg-{env}`
- Tunnel ID and configuration details

## Workflow

### Initial Setup (First Time)

```bash
# 1. Deploy Vault via Helm
helm install ttrpg ./charts/ttrpg-umbrella -f values-local.yaml

# 2. Wait for Vault pod to be ready
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=300s

# 3. Initialize Vault
./scripts/init-vault.sh local

# 4. Setup PostgreSQL (after PostgreSQL is deployed)
./scripts/setup-database-roles.sh local

# 5. Configure Vault secrets engines
./scripts/vault-configure.sh local

# 6. Test credential generation
vault read database/creds/go-auth-role
```

### Cloudflare Tunnel Setup (Dev/Prod)

```bash
# 1. Set Cloudflare API token
export CLOUDFLARE_API_TOKEN="your-api-token"
export CLOUDFLARE_ZONE_ID="your-zone-id"  # Optional, for automatic DNS

# 2. Bootstrap tunnel
./scripts/bootstrap-cloudflare-tunnel.sh dev ttrpg-dev dev.mysite.com

# 3. Deploy with tunnel enabled
helm upgrade --install ttrpg ./charts/ttrpg-umbrella \
  -f values-dev.yaml \
  --set cloudflare.enabled=true \
  --set cloudflare.tunnel.id=<tunnel-id-from-output> \
  --set cloudflare.tunnel.domain=dev.mysite.com \
  --namespace ttrpg-dev
```

### Daily Operations

**Unseal Vault (if sealed):**
```bash
./scripts/unseal-vault.sh prod
```

**Backup Vault:**
```bash
./scripts/backup-vault.sh prod ./backups
```

**Restore Vault:**
```bash
./scripts/restore-vault.sh prod ./backups/vault-backup-prod-20260209-143022.snap.gpg
```

### Environment-Specific Notes

**Local:**
- Auto-unseal enabled (no manual unsealing needed)
- Minimal security for development convenience
- Single Vault replica

**Dev:**
- Manual unseal required
- Sealed secrets for unseal keys
- Single Vault replica
- 7-day backup retention

**Prod:**
- Manual unseal required
- Sealed secrets for unseal keys
- 3 Vault replicas with Raft HA
- 30-day backup retention
- Automated backups via CronJob

## Security Best Practices

### Unseal Keys
- **NEVER commit `vault-init-keys.json` to Git**
- Store unseal keys in multiple secure locations
- Use sealed secrets for Kubernetes storage
- Consider using a hardware security module (HSM) for prod

### Root Token
- Use root token only for initial setup
- Create admin policies for day-to-day operations
- Rotate root token periodically
- Revoke root token when not needed

### Backups
- Encrypt all backups with GPG
- Store backups in multiple locations
- Test restore procedures regularly
- Keep backups for compliance requirements

### Credential Rotation
- Vault automatically rotates database credentials
- Root PostgreSQL password managed by Vault
- Application credentials expire after TTL
- Monitor Vault audit logs for access patterns

## Troubleshooting

### Vault is sealed
```bash
./scripts/unseal-vault.sh [ENV]
```

### Can't connect to Vault
```bash
# Check pod status
kubectl get pods -n vault

# Check logs
kubectl logs -n vault vault-0

# Port forward manually
kubectl port-forward -n vault svc/vault 8200:8200
export VAULT_ADDR='http://127.0.0.1:8200'
vault status
```

### Database connection failed
```bash
# Check PostgreSQL is running
kubectl get pods -n ttrpg-[ENV]

# Verify vault_admin user exists
./scripts/setup-database-roles.sh [ENV]

# Reconfigure Vault
./scripts/vault-configure.sh [ENV]
```

### Lost unseal keys
If you lose unseal keys, you cannot unseal Vault. You must:
1. Restore from backup (if you have one)
2. Or reinitialize Vault (losing all data)

**Prevention:** Always store unseal keys securely in multiple locations!

## References

- [Vault Documentation](https://www.vaultproject.io/docs)
- [Vault on Kubernetes](https://www.vaultproject.io/docs/platform/k8s)
- [Database Secrets Engine](https://www.vaultproject.io/docs/secrets/databases/postgresql)
- [Raft Storage](https://www.vaultproject.io/docs/configuration/storage/raft)
- [Vault Agent Injector](https://www.vaultproject.io/docs/platform/k8s/injector)
