# TTRPG Helm Charts

This directory contains Helm charts for deploying the TTRPG application suite to Kubernetes.

## Structure

```
charts/
├── shared/                      # Shared template library
│   └── templates/
│       ├── _helpers.tpl        # Common helper functions
│       ├── _labels.tpl         # Kebab-case label generation
│       └── _vault-annotations.tpl  # Vault Agent Injector templates
│
└── ttrpg-umbrella/             # Parent umbrella chart
    ├── Chart.yaml              # Chart metadata and dependencies
    ├── values.yaml             # Default values
    ├── values-local.yaml       # Local environment overrides
    ├── values-dev.yaml         # Development environment overrides
    ├── values-prod.yaml        # Production environment overrides
    ├── templates/              # Umbrella chart templates
    │   ├── _helpers.tpl        # Umbrella-specific helpers
    │   ├── namespace.yaml      # Namespace definitions
    │   └── NOTES.txt           # Post-install notes
    └── charts/                 # Subcharts (to be implemented)
        ├── vault/
        ├── postgresql/
        ├── keycloak/
        ├── nats/
        ├── ingress/
        ├── cloudflare-tunnel/
        ├── go-auth/
        ├── go-sprint/
        ├── py-dnd/
        ├── ui-dnd/
        └── ui-sprint-management/
```

## Shared Templates

The `shared/` directory contains reusable template functions that can be imported by any chart:

### _helpers.tpl
- `app.name` - Get the application name
- `app.fullname` - Get the full qualified application name
- `app.chart` - Get chart name and version
- `app.labels` - Generate common labels
- `app.selectorLabels` - Generate selector labels
- `app.serviceAccountName` - Get service account name
- `app.imageTag` - Get image tag with precedence logic
- `app.namespace` - Get application namespace

### _vault-annotations.tpl
- `vault.annotations` - Database credential annotations
- `vault.customAnnotations` - Custom secret annotations
- `vault.keycloakAnnotations` - Keycloak admin credential annotations
- `vault.cloudflareAnnotations` - Cloudflare Tunnel credential annotations
- `vault.postgresRootAnnotations` - PostgreSQL root credential annotations

### _labels.tpl
- `labels.standard` - Generate standardized labels
- `labels.resourceName` - Convert to kebab-case
- `labels.environment` - Environment-specific labels
- `labels.component` - Component labels
- `labels.tier` - Tier labels
- `labels.validateKebabCase` - Validate kebab-case format

## Values Files

### values.yaml (Default)
Base configuration with sensible defaults for all environments. Uses `latest` version tag and minimal resources.

### values-local.yaml
Optimized for local k3d/k3s development:
- Minimal resource requests/limits
- Vault auto-unseal enabled
- Cloudflare Tunnel disabled
- Single replica for all services
- `IfNotPresent` image pull policy
- Baseline pod security standard

### values-dev.yaml
Development environment configuration:
- Moderate resources
- Cloudflare Tunnel enabled
- Sealed Vault (manual unseal)
- Let's Encrypt staging certificates
- `Always` image pull policy
- Restricted pod security standard
- 7-day backup retention

### values-prod.yaml
Production environment configuration:
- High availability (multiple replicas)
- PostgreSQL Operator for HA database
- Vault HA with Raft storage
- Let's Encrypt production certificates
- Horizontal Pod Autoscaling
- Full monitoring stack
- 30-day backup retention
- Network policies enabled
- Restricted pod security standard

## Version Management

Version precedence (highest to lowest):
1. Command-line `--set` flag
2. Application-specific `{app}.version` in values
3. Global `global.version` in values
4. Default `"latest"`

Example:
```bash
# Use global version for all apps
helm install ttrpg ./charts/ttrpg-umbrella --set global.version=v1.2.3

# Override specific app version
helm install ttrpg ./charts/ttrpg-umbrella \
  --set global.version=v1.2.3 \
  --set go-auth.version=v1.2.4

# Use environment-specific defaults
helm install ttrpg ./charts/ttrpg-umbrella -f values-prod.yaml
```

## Naming Conventions

All resource names and labels use **kebab-case** (lowercase with hyphens):
- Application names: `go-auth`, `go-sprint`, `py-dnd`, `ui-dnd`, `ui-sprint-management`
- Namespaces: `ttrpg-local`, `ttrpg-dev`, `ttrpg-prod`, `vault`
- Resource names: `go-auth-deployment`, `postgresql-service`
- Label values: `environment: local`, `component: backend`

The `labels.validateKebabCase` template function enforces this convention.

## Vault Integration

All applications use Vault Agent Injector for dynamic secret injection:

1. Annotations are added to pod templates via `vault.annotations` helper
2. Vault Agent sidecar automatically injects secrets
3. Secrets are mounted to `/vault/secrets/`
4. Applications source secrets before starting

Example usage in application chart:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "app.fullname" . }}
spec:
  template:
    metadata:
      annotations:
        {{- include "vault.annotations" . | nindent 8 }}
    spec:
      containers:
      - name: app
        command: ["/bin/sh", "-c"]
        args:
        - |
          source /vault/secrets/database
          exec /app/myapp
```

## Security Features

### Pod Security Standards
- Application namespaces: `restricted` (prod/dev) or `baseline` (local)
- Infrastructure namespaces: `baseline`
- Enforced via namespace labels

### Security Contexts
All applications include:
- `runAsNonRoot: true`
- `runAsUser: 1000` (or 101 for nginx)
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- `capabilities.drop: [ALL]`
- `seccompProfile.type: RuntimeDefault`

### Sealed Secrets
Bootstrap secrets (Vault unseal keys, Cloudflare tokens) are encrypted using Sealed Secrets and can be safely stored in Git.

### Certificate Management
- Local: Self-signed certificates via cert-manager
- Dev: Let's Encrypt staging
- Prod: Let's Encrypt production

## Resource Management

### Resource Quotas
Per-namespace limits on CPU, memory, and storage:
- Local: 2 CPU, 4Gi memory
- Dev: 4 CPU, 8Gi memory
- Prod: 16 CPU, 32Gi memory

### Limit Ranges
Default resource requests/limits for containers to prevent resource exhaustion.

### Pod Disruption Budgets
Ensure minimum availability during voluntary disruptions (prod only).

### Horizontal Pod Autoscaling
Automatic scaling based on CPU/memory utilization (prod only).

## Next Steps

1. Implement subchart templates for each application
2. Create initialization scripts for Vault configuration
3. Implement database migration jobs
4. Create Skaffold configuration for local development
5. Write Makefile automation
6. Add monitoring and backup configurations

## Usage

```bash
# Install with default values (local)
helm install ttrpg ./charts/ttrpg-umbrella

# Install for dev environment
helm install ttrpg ./charts/ttrpg-umbrella -f values-dev.yaml

# Install for prod with specific version
helm install ttrpg ./charts/ttrpg-umbrella \
  -f values-prod.yaml \
  --set global.version=v1.0.0

# Upgrade deployment
helm upgrade ttrpg ./charts/ttrpg-umbrella -f values-prod.yaml

# Uninstall
helm uninstall ttrpg
```

## References

- [Helm Documentation](https://helm.sh/docs/)
- [Vault Agent Injector](https://www.vaultproject.io/docs/platform/k8s/injector)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [cert-manager](https://cert-manager.io/)
