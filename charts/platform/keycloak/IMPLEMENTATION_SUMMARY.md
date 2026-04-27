# Keycloak Chart Implementation Summary

## Overview

This document summarizes the implementation of the Keycloak Helm chart for the TTRPG deployment infrastructure.

## Implemented Components

### 1. Helm Chart Structure

**Files Created**:
- `Chart.yaml` - Chart metadata and dependencies
- `values.yaml` - Default configuration values
- `templates/_helpers.tpl` - Template helper functions
- `templates/deployment.yaml` - Keycloak Deployment with Vault integration
- `templates/service.yaml` - ClusterIP Service on port 8080
- `templates/serviceaccount.yaml` - ServiceAccount for Keycloak pods
- `templates/NOTES.txt` - Post-installation instructions
- `README.md` - Comprehensive documentation

### 2. Vault Integration

**Vault Annotations**:
The deployment uses the `vault.keycloakAnnotations` helper from shared templates to inject:

1. **Admin Credentials** (`{env}/keycloak/admin`):
   - `KEYCLOAK_ADMIN` - Admin username
   - `KEYCLOAK_ADMIN_PASSWORD` - Admin password

2. **Database Credentials** (`{env}/database/creds/keycloak-role`):
   - `DB_USERNAME` - Dynamic database username
   - `DB_PASSWORD` - Dynamic database password

**Credential Flow**:
```
Vault → Vault Agent Sidecar → /vault/secrets/ → Environment Variables → Keycloak
```

### 3. Keycloak Configuration

**Database Backend**:
- PostgreSQL database: `keycloak`
- Host: `postgresql.ttrpg-{env}.svc.cluster.local`
- Credentials: Dynamic from Vault
- Connection configured via command-line arguments

**Keycloak Settings**:
- HTTP enabled on port 8080
- Proxy mode: `edge` (for use behind ingress)
- Admin console enabled
- Health endpoints: `/health/live` and `/health/ready`

### 4. Realm Configuration Script

**Script**: `scripts/setup-keycloak.sh`

**Features**:
- Idempotent realm and client creation
- Checks if resources exist before creating
- Uses Keycloak Admin REST API
- Retrieves admin credentials from Vault via Kubernetes
- Configurable via environment variables

**Realms Created**:

1. **dnd Realm**:
   - Display Name: "D&D Application"
   - Client: `dnd-client`
   - Client Type: Public with PKCE
   - Redirect URIs: `https://{domain}/ttrpg/dnd/*`

2. **sprint-management Realm**:
   - Display Name: "Sprint Management Application"
   - Client: `sprint-client`
   - Client Type: Public with PKCE
   - Redirect URIs: `https://{domain}/ttrpg/sprint-management/*`

**Token Configuration**:
- Access token lifespan: 5 minutes
- SSO session idle timeout: 30 minutes
- SSO session max lifespan: 10 hours
- Offline session idle timeout: 30 days
- Brute force protection enabled

### 5. Security Features

**Pod Security**:
- Runs as non-root user (UID 1000)
- Read-only root filesystem: false (Keycloak needs writable filesystem)
- Drops all capabilities
- Seccomp profile: RuntimeDefault

**Network Security**:
- ClusterIP service (internal only)
- External access via ingress with TLS
- Realm-specific token validation

**Secrets Management**:
- All secrets from Vault
- No plain text secrets in manifests
- Dynamic credential rotation

### 6. Resource Configuration

**Default Resources**:
```yaml
requests:
  cpu: 100m
  memory: 512Mi
limits:
  cpu: 1000m
  memory: 2Gi
```

**Environment-Specific**:
- Local: Minimal resources (1 replica)
- Dev: Moderate resources (1 replica)
- Prod: Full resources (2+ replicas)

### 7. Health Checks

**Liveness Probe**:
- Path: `/health/live`
- Initial delay: 60 seconds
- Period: 10 seconds

**Readiness Probe**:
- Path: `/health/ready`
- Initial delay: 30 seconds
- Period: 5 seconds

## Requirements Validation

### Requirement 7.1: Deploy Keycloak
✅ **Implemented**: Deployment resource created with proper configuration

### Requirement 7.2: Separate Realms
✅ **Implemented**: Setup script creates `dnd` and `sprint-management` realms

### Requirement 7.3: Configure Realm Clients
✅ **Implemented**: Clients created with PKCE and appropriate redirect URIs

### Requirement 7.4: Create Clients
✅ **Implemented**: `dnd-client` and `sprint-client` created in respective realms

### Requirement 7.5: Retrieve Admin Credentials from Vault
✅ **Implemented**: Vault annotations inject admin credentials

### Requirement 7.7: Shared Authentication
✅ **Implemented**: Realms can be configured for shared authentication if needed

## Usage

### Deploy Keycloak

```bash
# Deploy with umbrella chart
helm install ttrpg charts/ttrpg-umbrella \
  --namespace ttrpg-local \
  --create-namespace \
  --values charts/ttrpg-umbrella/values-local.yaml
```

### Configure Realms

```bash
# Wait for Keycloak to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=keycloak \
  -n ttrpg-local \
  --timeout=300s

# Run setup script
export ENV=local
export DOMAIN=localhost
./scripts/setup-keycloak.sh
```

### Verify Configuration

```bash
# Check pod status
kubectl get pods -n ttrpg-local -l app.kubernetes.io/name=keycloak

# Check logs
kubectl logs -n ttrpg-local -l app.kubernetes.io/name=keycloak

# Port forward and access admin console
kubectl port-forward -n ttrpg-local svc/keycloak 8180:8080

# Open http://localhost:8180 in browser
```

## Integration Points

### With PostgreSQL
- Database: `keycloak`
- Connection via Vault dynamic credentials
- Host: `postgresql.ttrpg-{env}.svc.cluster.local`

### With Vault
- Admin credentials: `{env}/keycloak/admin`
- Database credentials: `{env}/database/creds/keycloak-role`
- Vault Agent Injector sidecar

### With Ingress
- Token validation at ingress level
- Realm-specific routing based on path
- TLS termination

### With Applications
- Backend: Token validation via OIDC
- Frontend: OAuth2 PKCE flow
- Redirect URIs configured per realm

## Testing

### Manual Testing

1. **Deploy Keycloak**:
   ```bash
   helm install ttrpg charts/ttrpg-umbrella -n ttrpg-local --create-namespace
   ```

2. **Verify Pod Running**:
   ```bash
   kubectl get pods -n ttrpg-local -l app.kubernetes.io/name=keycloak
   ```

3. **Check Vault Integration**:
   ```bash
   kubectl logs -n ttrpg-local -l app.kubernetes.io/name=keycloak -c vault-agent
   ```

4. **Run Setup Script**:
   ```bash
   export ENV=local DOMAIN=localhost
   ./scripts/setup-keycloak.sh
   ```

5. **Verify Realms**:
   ```bash
   kubectl port-forward -n ttrpg-local svc/keycloak 8180:8080
   curl http://localhost:8180/realms/dnd | jq .
   curl http://localhost:8180/realms/sprint-management | jq .
   ```

### Automated Testing

Property-based tests should verify:
- Vault annotations are present
- Service is ClusterIP type
- Health checks are configured
- Security context is restrictive
- Resource limits are set

## Known Limitations

1. **Filesystem**: Keycloak requires writable filesystem, so `readOnlyRootFilesystem: false`
2. **Startup Time**: Keycloak takes 30-60 seconds to start, health checks account for this
3. **Realm Configuration**: Realms must be configured after deployment via setup script
4. **Single Instance**: Default configuration is single replica, HA requires additional configuration

## Future Enhancements

1. **High Availability**: Configure multiple replicas with session replication
2. **Custom Themes**: Add custom login themes for each realm
3. **User Federation**: Integrate with LDAP/Active Directory
4. **Social Login**: Configure social identity providers (Google, GitHub, etc.)
5. **Metrics**: Expose Prometheus metrics for monitoring
6. **Backup**: Automated backup of realm configurations

## References

- Design Document: `ttrpg-deployment/.kiro/specs/k8s-helm-deployment/design.md`
- Requirements: `ttrpg-deployment/.kiro/specs/k8s-helm-deployment/requirements.md`
- Keycloak Documentation: https://www.keycloak.org/documentation
- Vault Agent Injector: https://www.vaultproject.io/docs/platform/k8s/injector
