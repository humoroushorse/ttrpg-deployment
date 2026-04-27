# Keycloak Helm Chart

This Helm chart deploys Keycloak authentication and authorization server for the TTRPG application suite.

## Overview

Keycloak provides:
- Authentication and authorization for all TTRPG applications
- Separate realms for each project (dnd, sprint-management)
- OAuth2/OIDC protocol support with PKCE
- Integration with PostgreSQL for persistence
- Vault integration for secrets management

## Architecture

```
┌─────────────────────────────────────────┐
│         Keycloak Deployment             │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │   Vault Agent Sidecar             │ │
│  │   - Admin credentials             │ │
│  │   - Database credentials          │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │   Keycloak Container              │ │
│  │   - Port 8080                     │ │
│  │   - PostgreSQL backend            │ │
│  │   - Multiple realms               │ │
│  └───────────────────────────────────┘ │
└─────────────────────────────────────────┘
           │                    │
           │                    │
           ▼                    ▼
    ┌──────────┐         ┌──────────┐
    │  Vault   │         │PostgreSQL│
    │  Secrets │         │ Database │
    └──────────┘         └──────────┘
```

## Configuration

### Vault Integration

Keycloak retrieves secrets from Vault:

1. **Admin Credentials**: `{env}/keycloak/admin`
   - `KEYCLOAK_ADMIN`: Admin username
   - `KEYCLOAK_ADMIN_PASSWORD`: Admin password

2. **Database Credentials**: `{env}/database/creds/keycloak-role`
   - `DB_USERNAME`: Dynamic database username
   - `DB_PASSWORD`: Dynamic database password

### Realms

Two realms are configured via the `setup-keycloak.sh` script:

#### D&D Realm
- **Name**: `dnd`
- **Client**: `dnd-client`
- **Type**: Public client with PKCE
- **Redirect URIs**: `https://{domain}/ttrpg/dnd/*`
- **Used by**: py-dnd backend, ui-dnd frontend

#### Sprint Management Realm
- **Name**: `sprint-management`
- **Client**: `sprint-client`
- **Type**: Public client with PKCE
- **Redirect URIs**: `https://{domain}/ttrpg/sprint-management/*`
- **Used by**: go-sprint backend, ui-sprint-management frontend

### Token Configuration

Default token lifespans:
- Access token: 5 minutes (300s)
- Refresh token: 30 minutes (1800s)
- SSO session: 10 hours (36000s)
- Offline session: 30 days (2592000s)

## Values

### Basic Configuration

```yaml
# Enable/disable Keycloak
enabled: true

# Number of replicas
replicaCount: 1

# Image configuration
image:
  repository: keycloak/keycloak
  tag: "26.5"
  pullPolicy: IfNotPresent

# Service configuration
service:
  type: ClusterIP
  port: 8080
```

### Environment-Specific Values

**Local**:
```yaml
environment: local
replicaCount: 1
keycloak:
  hostname: localhost
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

**Dev**:
```yaml
environment: dev
replicaCount: 1
keycloak:
  hostname: dev.mysite.com
resources:
  requests:
    cpu: 200m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

**Prod**:
```yaml
environment: prod
replicaCount: 2
keycloak:
  hostname: mysite.com
resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 8Gi
```

## Deployment

### Prerequisites

1. PostgreSQL must be deployed with `keycloak` database
2. Vault must be configured with:
   - Admin credentials at `{env}/keycloak/admin`
   - Database role `keycloak-role` configured

### Deploy Keycloak

```bash
# Deploy with umbrella chart
helm install ttrpg charts/ttrpg-umbrella \
  --namespace ttrpg-local \
  --create-namespace \
  --values charts/ttrpg-umbrella/values-local.yaml

# Or deploy standalone
helm install keycloak charts/ttrpg-umbrella/charts/keycloak \
  --namespace ttrpg-local \
  --create-namespace \
  --set environment=local
```

### Configure Realms

After Keycloak is deployed and ready, run the setup script:

```bash
# Set environment and domain
export ENV=local
export DOMAIN=localhost

# Run setup script
./scripts/setup-keycloak.sh
```

The script will:
1. Wait for Keycloak to be ready
2. Retrieve admin credentials from Vault
3. Create realms (if they don't exist)
4. Create clients (if they don't exist)

## Verification

### Check Deployment

```bash
# Check pod status
kubectl get pods -n ttrpg-local -l app.kubernetes.io/name=keycloak

# Check logs
kubectl logs -n ttrpg-local -l app.kubernetes.io/name=keycloak -f

# Check health
kubectl exec -n ttrpg-local deploy/keycloak -- \
  curl -sf http://localhost:8080/health/ready
```

### Access Admin Console

```bash
# Port forward to local machine
kubectl port-forward -n ttrpg-local svc/keycloak 8180:8080

# Open browser to http://localhost:8180
# Login with admin credentials from Vault
```

### Test Realm Configuration

```bash
# Get realm info
curl -sf http://localhost:8180/realms/dnd | jq .

# Get client info
curl -sf http://localhost:8180/realms/dnd/.well-known/openid-configuration | jq .
```

## Troubleshooting

### Pod Not Starting

Check Vault integration:
```bash
# Check Vault annotations
kubectl describe pod -n ttrpg-local -l app.kubernetes.io/name=keycloak

# Check Vault agent logs
kubectl logs -n ttrpg-local -l app.kubernetes.io/name=keycloak -c vault-agent
```

### Database Connection Issues

Check database credentials:
```bash
# Exec into pod
kubectl exec -it -n ttrpg-local deploy/keycloak -- sh

# Check environment variables
source /vault/secrets/database
echo $DB_USERNAME
echo $DB_PASSWORD

# Test database connection
psql -h postgresql.ttrpg-local.svc.cluster.local -U $DB_USERNAME -d keycloak -c "SELECT 1"
```

### Realm Creation Failed

Check setup script logs:
```bash
# Run setup script with verbose output
bash -x ./scripts/setup-keycloak.sh
```

Common issues:
- Keycloak not ready: Wait longer or check health endpoint
- Admin credentials missing: Verify Vault configuration
- Realm already exists: Script is idempotent, this is normal

## Security

### Secrets Management

All secrets are managed by Vault:
- Admin credentials are never stored in Git
- Database credentials are dynamically generated
- Credentials are rotated automatically by Vault

### Network Security

- Keycloak is only accessible within the cluster (ClusterIP)
- External access is through ingress with TLS
- Pod security standards enforced (restricted)

### Authentication

- Admin console requires authentication
- Realms use OAuth2/OIDC with PKCE
- Brute force protection enabled
- Password reset available

## Integration with Applications

### Backend Applications

Backend applications validate tokens at the application level:

```go
// Example: Go application
import "github.com/coreos/go-oidc/v3/oidc"

provider, _ := oidc.NewProvider(ctx, "http://keycloak.ttrpg-local.svc.cluster.local:8080/realms/dnd")
verifier := provider.Verifier(&oidc.Config{ClientID: "dnd-client"})
token, _ := verifier.Verify(ctx, rawToken)
```

### Frontend Applications

Frontend applications use OAuth2 PKCE flow:

```typescript
// Example: Angular application
import { OAuthService } from 'angular-oauth2-oidc';

this.oauthService.configure({
  issuer: 'http://localhost:8180/realms/dnd',
  clientId: 'dnd-client',
  redirectUri: window.location.origin + '/ttrpg/dnd/',
  responseType: 'code',
  scope: 'openid profile email',
  usePkce: true
});
```

### Ingress Integration

Ingress validates tokens before routing to applications:

```yaml
annotations:
  nginx.ingress.kubernetes.io/auth-url: "http://keycloak.ttrpg-local.svc.cluster.local:8080/realms/$realm/protocol/openid-connect/auth"
  nginx.ingress.kubernetes.io/configuration-snippet: |
    set $realm "dnd";
```

## Maintenance

### Backup

Keycloak data is stored in PostgreSQL, so database backups include Keycloak configuration.

### Updates

To update Keycloak version:

```bash
# Update image tag in values
helm upgrade ttrpg charts/ttrpg-umbrella \
  --namespace ttrpg-local \
  --set keycloak.image.tag=26.5 \
  --reuse-values
```

### Scaling

To scale Keycloak for high availability:

```bash
# Increase replicas
helm upgrade ttrpg charts/ttrpg-umbrella \
  --namespace ttrpg-prod \
  --set keycloak.replicaCount=3 \
  --reuse-values
```

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak Admin REST API](https://www.keycloak.org/docs-api/latest/rest-api/)
- [OAuth2 PKCE Flow](https://oauth.net/2/pkce/)
- [Vault Agent Injector](https://www.vaultproject.io/docs/platform/k8s/injector)
