# Application Helm Charts Implementation Summary

## Overview

This document summarizes the implementation of application Helm charts with Vault Agent Injector integration for the TTRPG platform.

## Created Charts

The following application charts have been created:

1. **go-auth** - Authentication service (Go)
2. **go-sprint** - Sprint management service (Go)
3. **py-dnd** - D&D service (Python/FastAPI)
4. **ui-dnd** - D&D frontend (Angular/nginx)
5. **ui-sprint-management** - Sprint management frontend (Angular/nginx)

## Chart Structure

Each chart includes the following files:

```
charts/ttrpg-umbrella/charts/{app-name}/
├── Chart.yaml                    # Chart metadata and dependencies
├── values.yaml                   # Default configuration values
└── templates/
    ├── _helpers.tpl              # Template helper functions
    ├── configmap.yaml            # Application configuration
    ├── deployment.yaml           # Deployment with Vault integration
    ├── service.yaml              # ClusterIP service
    └── serviceaccount.yaml       # Service account for Vault auth
```

## Key Features Implemented

### 1. Vault Agent Injector Integration

**Backend Services (go-auth, go-sprint, py-dnd):**
- Vault annotations automatically inject database credentials
- Credentials are sourced from `{env}/database/creds/{app}-role`
- Environment variables exported: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`
- Command wrapper sources Vault secrets before starting application

**Frontend Services (ui-dnd, ui-sprint-management):**
- No Vault integration (frontends don't need database access)
- Configuration via ConfigMap only

### 2. Version Management

Version precedence (highest to lowest):
1. `--set image.tag=X.Y.Z` (command-line override)
2. `image.tag` in values.yaml
3. `version` in values.yaml
4. `global.version` from parent chart
5. `"latest"` (default fallback)

Example:
```bash
# Use global version
helm install app charts/go-auth --set global.version=v1.0.0

# Override with specific version
helm install app charts/go-auth --set image.tag=v2.0.0
```

### 3. Image Pull Policy

**Local/Dev Environment:**
- `pullPolicy: IfNotPresent` - Use cached images for faster iteration

**Production Environment:**
- `pullPolicy: Always` - Always pull latest image for security

### 4. Health Checks

**Backend Services:**
- Liveness probe: `/health` endpoint, 30s initial delay
- Readiness probe: `/ready` endpoint, 5s initial delay

**Frontend Services:**
- Liveness probe: `/` endpoint, 10s initial delay
- Readiness probe: `/` endpoint, 5s initial delay

### 5. Resource Limits

**Backend Services (local):**
- Requests: 100m CPU, 128Mi memory
- Limits: 500m CPU, 512Mi memory

**Backend Services (prod):**
- Requests: 200m CPU, 256Mi memory
- Limits: 1000m CPU, 1Gi memory

**Frontend Services (local):**
- Requests: 50m CPU, 64Mi memory
- Limits: 200m CPU, 256Mi memory

**Frontend Services (prod):**
- Requests: 100m CPU, 128Mi memory
- Limits: 500m CPU, 512Mi memory

### 6. Security Context

All applications run with restricted security context:
- `runAsNonRoot: true`
- `runAsUser: 1000` (backends) or `101` (nginx frontends)
- `fsGroup: 1000` or `101`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- `capabilities.drop: [ALL]`
- `seccompProfile.type: RuntimeDefault`

Writable volumes provided:
- `/tmp` - Temporary files
- `/app/cache` - Application cache (backends)
- `/var/cache/nginx` - Nginx cache (frontends)
- `/var/run` - Runtime files (frontends)

### 7. Service Configuration

Each application exposes a ClusterIP service:
- **go-auth**: Port 8081
- **go-sprint**: Port 8003
- **py-dnd**: Port 8001
- **ui-dnd**: Port 4200
- **ui-sprint-management**: Port 4204

### 8. Application-Specific Configuration

**Go Applications (go-auth, go-sprint):**
- Binary: `/app/server`
- Command wrapper sources Vault secrets
- ConfigMap includes NATS URL for event streaming

**Python Application (py-dnd):**
- Command: `python -m uvicorn py_dnd.main:app --host 0.0.0.0 --port 8001`
- Higher memory limits (256Mi request, 1Gi limit)
- Command wrapper sources Vault secrets

**Frontend Applications (ui-dnd, ui-sprint-management):**
- Nginx-based serving
- No Vault integration
- API endpoints configured via ConfigMap
- Lower resource requirements

## Validation

All charts have been validated using Helm:

```bash
# Lint charts
helm lint charts/ttrpg-umbrella/charts/go-auth
helm lint charts/ttrpg-umbrella/charts/go-sprint
helm lint charts/ttrpg-umbrella/charts/py-dnd
helm lint charts/ttrpg-umbrella/charts/ui-dnd
helm lint charts/ttrpg-umbrella/charts/ui-sprint-management

# Test template rendering
helm template test-release charts/ttrpg-umbrella/charts/go-auth --set environment=local

# Verify Vault annotations
helm template test-release charts/ttrpg-umbrella/charts/go-auth --set environment=local | grep vault.hashicorp.com

# Verify version precedence
helm template test-release charts/ttrpg-umbrella/charts/go-auth --set global.version=v1.0.0 --set image.tag=v2.0.0 | grep image:
```

## Example Vault Annotations Output

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "go-auth"
  vault.hashicorp.com/agent-inject-secret-database: "local/database/creds/go-auth-role"
  vault.hashicorp.com/agent-inject-template-database: |
    {{- with secret "local/database/creds/go-auth-role" -}}
    export POSTGRES_USER="{{ .Data.username }}"
    export POSTGRES_PASSWORD="{{ .Data.password }}"
    export POSTGRES_HOST="postgresql.ttrpg-local.svc.cluster.local"
    export POSTGRES_PORT="5432"
    export POSTGRES_DB="auth"
    {{- end }}
```

## Dependencies

All application charts depend on the shared library chart:

```yaml
dependencies:
  - name: shared
    version: "*"
    repository: "file://../../../shared"
```

The shared chart provides:
- Common helper templates (`app.fullname`, `app.labels`, etc.)
- Vault annotation templates
- Image tag resolution logic
- Namespace generation

## Usage Examples

### Deploy with default values
```bash
helm install go-auth charts/ttrpg-umbrella/charts/go-auth
```

### Deploy with specific version
```bash
helm install go-auth charts/ttrpg-umbrella/charts/go-auth \
  --set global.version=v1.2.3 \
  --set environment=prod
```

### Deploy with custom resources
```bash
helm install go-auth charts/ttrpg-umbrella/charts/go-auth \
  --set resources.requests.cpu=200m \
  --set resources.requests.memory=256Mi
```

### Deploy with multiple replicas
```bash
helm install go-auth charts/ttrpg-umbrella/charts/go-auth \
  --set replicaCount=3 \
  --set environment=prod
```

## Next Steps

These application charts will be integrated into the umbrella chart in future tasks:
- Task 5: Ingress configuration with path-based routing
- Task 10: Version management and release automation
- Task 13: Skaffold integration for local development
- Task 14: Makefile automation for deployment

## Requirements Satisfied

This implementation satisfies the following requirements from the design document:

- **5.1**: Application charts created with proper structure
- **5.2**: Vault Agent Injector annotations configured
- **5.3**: Database credentials injected via Vault
- **5.4**: Service resources configured with appropriate ports
- **5.5**: Health checks implemented (liveness and readiness probes)
- **5.6**: Resource limits configured for local and prod environments
- **15.1**: Version precedence implemented (image.tag > version > global.version)
- **15.2**: Image pull policy configured per environment
- **15.3**: Security contexts configured with restricted permissions
- **15.4**: Writable volumes provided for read-only root filesystem
- **15.5**: Service accounts created for Vault authentication
