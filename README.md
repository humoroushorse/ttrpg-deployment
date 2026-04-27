# TTRPG Kubernetes Deployment Infrastructure

Production-ready Kubernetes deployment infrastructure for the TTRPG application suite using Helm charts, HashiCorp Vault for secrets management, and Cloudflare Tunnels for external access.

## Quick Start

```shell
# Teardown and recreate cluster
make teardown ENV=local

# Remove packaged charts for local dev (optional, for debugging)
make clean-charts

# Build and load all application images
make build-images ENV=local VERSION=latest

# Deploy infrastructure (Vault, PostgreSQL, Keycloak, NATS, Ingress)
make deploy-infra ENV=local VERSION=latest

# Initialize and unseal Vault
make init-vault ENV=local

# Configure Vault database secrets engine
make configure-vault ENV=local

# Deploy all application services with migrations
make deploy-apps ENV=local VERSION=latest

# Verify deployment
make verify ENV=local











# 0. (Optional) Remove packaged charts for debugging
make clean-charts

# 1. Clean slate
make teardown ENV=local

# 2. Build images
make build-images ENV=local VERSION=latest

# 3. Deploy Vault (security namespace)
make deploy-vault ENV=local

# 4. Deploy Platform (platform namespace)
make deploy-platform ENV=local

# 5. Setup Keycloak: creates ttrpg, sprint-management realms
make configure-keycloak ENV=local

# 6. Initialize Vault
make init-vault ENV=local

# 7. Configure Vault
make configure-vault ENV=local

# 8. Deploy Apps (apps namespace)
make deploy-apps ENV=local VERSION=latest

# 9. Verify
make verify ENV=local
```

**One-Command Deployment:**
```shell
make deploy-clean ENV=local VERSION=latest
```

**Access Your Services:**
- Main Ingress: http://localhost:8080/ttrpg/
- Sprint Management UI: http://localhost:8080/ttrpg/sprint-management/
- Sprint API: http://localhost:8080/ttrpg/sprint-management/api/v1/
- D&D UI: http://localhost:8080/ttrpg/dnd/

kubectl port-forward -n security svc/vault 8200:8200
- Vault UI: http://localhost:8200
- login (token) - root
kubectl port-forward -n platform svc/platform-keycloak 8180:8080
- Keycloak: http://localhost:8180
- login - admin/admin


- Main Ingress: http://localhost:8080/
- Sprint Management UI: http://localhost:8080/sprint/
- Sprint API: http://localhost:8080/sprint/api/v1/
- D&D UI: http://localhost:8080/ttrpg/dnd/
- Vault UI: http://localhost:8200
- Keycloak: http://localhost:8180


### Prerequisites

Ensure you have the following tools installed:

- **kubectl** (v1.28+): Kubernetes CLI
- **helm** (v3.12+): Kubernetes package manager
- **vault** (v1.15+): HashiCorp Vault CLI
- **k3d** (v5.6+): k3s in Docker for local development
- **skaffold** (v2.8+): Local development automation
- **docker**: Container runtime

**Installation (macOS)**:
```bash
brew install kubectl helm vault k3d skaffold docker
```

**Installation (Linux)**:
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# vault
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault

# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# skaffold
curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
sudo install skaffold /usr/local/bin/
```

### Cluster Creation

Create a local k3d cluster with registry:

```bash
make create-cluster
```

This creates:
- k3d cluster named `ttrpg-local`
- Local Docker registry on port 5000
- LoadBalancer on ports 8080 (HTTP) and 8443 (HTTPS)
- 2 agent nodes for testing

### Deployment

Deploy the full stack to local environment:

```bash
# Deploy all components
make deploy-local

# Initialize Vault
make vault-init ENV=local

# Unseal Vault (if needed)
make vault-unseal ENV=local

# Configure Vault secrets engines
make vault-configure ENV=local

# Verify deployment
make verify ENV=local
```

**One-Command Quick Start**:
```bash
make quickstart
```

This runs all the above steps automatically.

### Access Services

Once deployed, access services at:

- **Ingress**: http://localhost:8080/ttrpg/
- **Vault UI**: http://localhost:8200
- **Keycloak**: http://localhost:8180

**Application URLs**:
- D&D UI: http://localhost:8080/ttrpg/dnd/
- D&D API: http://localhost:8080/ttrpg/dnd/api/v1/
- Sprint Management UI: http://localhost:8080/ttrpg/sprint-management/
- Sprint Management API: http://localhost:8080/ttrpg/sprint-management/api/v1/
- Auth Service: http://localhost:8080/ttrpg/auth/

## Architecture Overview

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Cloudflare Tunnel (prod/dev)             │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                    Ingress Controller                        │
│              (nginx, path-based routing)                     │
└─────┬──────────┬──────────┬──────────┬──────────────────────┘
      │          │          │          │
┌─────▼────┐ ┌──▼──────┐ ┌─▼────────┐ ┌▼──────────────┐
│ go-auth  │ │go-sprint│ │  py-dnd  │ │  UI Services  │
└─────┬────┘ └──┬──────┘ └─┬────────┘ └───────────────┘
      │         │           │
      └─────────┴───────────┴──────────┐
                                       │
                    ┌──────────────────▼──────────────────┐
                    │         PostgreSQL                   │
                    │  (auth, sprint_management, dnd DBs)  │
                    └──────────────────┬──────────────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │        HashiCorp Vault              │
                    │   (dynamic database credentials)     │
                    └─────────────────────────────────────┘
```

### Namespace Organization

- **ttrpg-local**: Local development environment (includes Vault)
- **ttrpg-dev**: Development environment (includes Vault)
- **ttrpg-prod**: Production environment (uses external Vault)

### Key Features

- **Dynamic Secrets**: Vault generates unique database credentials per application with automatic rotation
- **Multi-Environment**: Deploy to local, dev, or prod with environment-specific configurations
- **Path-Based Routing**: Single ingress routes traffic by project path prefix
- **Keycloak Integration**: Token validation at ingress level with realm-specific routing
- **Cloudflare Tunnel**: Secure external access without opening firewall ports (dev/prod)
- **High Availability**: Multiple replicas, PodDisruptionBudgets, and automated failover (prod)
- **Security**: Pod Security Standards, Sealed Secrets, cert-manager for TLS

## Common Operations

### Deploy Operations

```bash
# Deploy to specific environment
make deploy ENV=local VERSION=v1.2.3

# Deploy single application
make deploy-app APP=go-auth ENV=dev VERSION=v1.2.3

# Deploy ephemeral environment (random name)
make deploy-ephemeral

# Deploy with custom values
helm upgrade --install ttrpg-local charts/ttrpg-umbrella \
  --namespace ttrpg-local \
  --create-namespace \
  --values charts/ttrpg-umbrella/values-local.yaml \
  --set global.version=v1.2.3
```

### Update Operations

```bash
# Update all applications to new version
make deploy ENV=dev VERSION=v1.3.0

# Update single application
make deploy-app APP=go-sprint ENV=dev VERSION=v1.3.0

# Update configuration only (no version change)
helm upgrade ttrpg-dev charts/ttrpg-umbrella \
  --namespace ttrpg-dev \
  --values charts/ttrpg-umbrella/values-dev.yaml \
  --reuse-values
```

### Rollback Operations

```bash
# List releases
helm list -n ttrpg-dev

# Show release history
helm history ttrpg-dev -n ttrpg-dev

# Rollback to previous version
helm rollback ttrpg-dev -n ttrpg-dev

# Rollback to specific revision
helm rollback ttrpg-dev 3 -n ttrpg-dev
```

### Vault Operations

```bash
# Initialize Vault (first time only)
make vault-init ENV=local

# Unseal Vault
make vault-unseal ENV=local

# Configure secrets engines and policies
make vault-configure ENV=local

# Rotate database credentials for specific app
make vault-rotate-db ENV=prod APP=go-auth

# Backup Vault data
make vault-backup ENV=prod

# Restore Vault from backup
make vault-restore ENV=prod BACKUP=vault-backup-20260210.tar.gz
```

### Verification and Debugging

```bash
# Verify deployment health
make verify ENV=local

# Check pod status
kubectl get pods -n ttrpg-local

# View pod logs
kubectl logs -n ttrpg-local deploy/go-auth -f

# Describe pod for events
kubectl describe pod -n ttrpg-local <pod-name>

# Port forward to service
kubectl port-forward -n ttrpg-local svc/go-auth 8081:8081

# Execute command in pod
kubectl exec -n ttrpg-local deploy/go-auth -- env | grep POSTGRES

# Check Vault status
kubectl exec -n vault vault-0 -- vault status
```

### Migration Operations

```bash
# Check migration status
make migration-status ENV=local

# View migration logs
make migration-logs ENV=local APP=go-auth

# Retry failed migration
make migration-retry ENV=local APP=go-auth

# Verify all migrations completed
make verify-migrations ENV=local
```

### Skaffold Development Workflow

```bash
# Start development mode (auto-rebuild on changes)
make skaffold-dev

# Start debug mode
make skaffold-debug

# Develop single application
make skaffold-app APP=go-auth

# Stop Skaffold
make skaffold-delete
```

See the scripts directory for detailed Skaffold usage.

### Cleanup Operations

```bash
# Destroy specific environment
make destroy ENV=test-abc123

# Destroy local cluster
make destroy-cluster

# Clean generated files
make clean
```

## Troubleshooting

### Common Issues

#### Pods Not Starting

**Symptom**: Pods stuck in `Pending` or `Init` state

**Diagnosis**:
```bash
kubectl get pods -n ttrpg-local
kubectl describe pod -n ttrpg-local <pod-name>
```

**Common Causes**:
- Vault is sealed or unavailable
- Insufficient resources (check resource quotas)
- Image pull failures
- PVC not bound

**Solutions**:
```bash
# Check Vault status
kubectl exec -n vault vault-0 -- vault status

# Unseal Vault if needed
make vault-unseal ENV=local

# Check resource quotas
kubectl describe resourcequota -n ttrpg-local

# Check PVC status
kubectl get pvc -n ttrpg-local
```

#### Vault Sealed

**Symptom**: Applications can't start, Vault status shows "Sealed: true"

**Solution**:
```bash
make vault-unseal ENV=local
```

For production, ensure unseal keys are stored securely in Sealed Secrets.

#### Ingress 404 Errors

**Symptom**: Accessing http://localhost:8080/ttrpg/dnd/ returns 404

**Diagnosis**:
```bash
# Check ingress configuration
kubectl get ingress -n ttrpg-local -o yaml

# Check service endpoints
kubectl get endpoints -n ttrpg-local

# Check ingress controller logs
kubectl logs -n ttrpg-local -l app.kubernetes.io/name=ingress-nginx
```

**Common Causes**:
- Service not ready
- Incorrect path rewrite rules
- Backend service not running

#### Database Connection Failures

**Symptom**: Application logs show "connection refused" or "authentication failed"

**Diagnosis**:
```bash
# Check PostgreSQL pod
kubectl get pods -n ttrpg-local -l app=postgresql

# Check PostgreSQL logs
kubectl logs -n ttrpg-local -l app=postgresql

# Test connection from application pod
kubectl exec -n ttrpg-local deploy/go-auth -- \
  psql -h postgresql -U <username> -d auth -c "SELECT 1"
```

**Common Causes**:
- PostgreSQL not ready
- Vault credentials expired
- Database not initialized
- Network policy blocking connection

**Solutions**:
```bash
# Check Vault credential generation
kubectl exec -n vault vault-0 -- \
  vault read local/database/creds/go-auth-role

# Restart application to get new credentials
kubectl rollout restart -n ttrpg-local deploy/go-auth
```

#### Migration Job Failures

**Symptom**: Application pods not starting, migration job shows failed status

**Diagnosis**:
```bash
make migration-status ENV=local APP=go-auth
make migration-logs ENV=local APP=go-auth
```

**Solutions**:
```bash
# Retry migration
make migration-retry ENV=local APP=go-auth

# If migration is stuck, delete job manually
kubectl delete job -n ttrpg-local -l app.kubernetes.io/name=go-auth,app.kubernetes.io/component=migration
```

### Debugging Commands

```bash
# Get all resources in namespace
kubectl get all -n ttrpg-local

# Check events
kubectl get events -n ttrpg-local --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n ttrpg-local
kubectl top nodes

# View Helm values
helm get values ttrpg-local -n ttrpg-local

# View rendered manifests
helm get manifest ttrpg-local -n ttrpg-local

# Dry run deployment
helm upgrade --install ttrpg-local charts/ttrpg-umbrella \
  --namespace ttrpg-local \
  --values charts/ttrpg-umbrella/values-local.yaml \
  --dry-run --debug
```

### Getting Help

For more detailed troubleshooting, check the Makefile targets and application logs.

## Project Structure

```
ttrpg-deployment/
├── charts/
│   ├── ttrpg-umbrella/          # Parent Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml          # Default values
│   │   ├── values-local.yaml    # Local environment overrides
│   │   ├── values-dev.yaml      # Dev environment overrides
│   │   ├── values-prod.yaml     # Prod environment overrides
│   │   ├── templates/           # Kubernetes manifests
│   │   └── charts/              # Application subcharts
│   │       ├── vault/
│   │       ├── postgresql/
│   │       ├── keycloak/
│   │       ├── nats/
│   │       ├── ingress/
│   │       ├── cloudflare-tunnel/
│   │       ├── go-auth/
│   │       ├── go-sprint/
│   │       ├── py-dnd/
│   │       ├── ui-dnd/
│   │       └── ui-sprint-management/
│   └── shared/                  # Shared Helm templates
│       └── templates/
│           ├── _vault-annotations.tpl
│           ├── _labels.tpl
│           └── _resources.tpl
├── scripts/                     # Automation scripts
│   ├── init-vault.sh
│   ├── unseal-vault.sh
│   ├── vault-configure.sh
│   ├── setup-database-roles.sh
│   ├── setup-keycloak.sh
│   ├── backup-vault.sh
│   ├── restore-vault.sh
│   └── bootstrap-sealed-secrets.sh
├── skaffold.yaml               # Skaffold configuration
├── Makefile                    # Automation targets
└── README.md                   # This file
```

## Version Management

The deployment system supports flexible version management:

```yaml
# Global default version (applies to all apps)
global:
  version: "v1.2.3"

# Per-application version overrides
go-auth:
  version: "v1.3.0"  # Overrides global version

go-sprint:
  version: ""  # Empty = use global version
```

**Version Precedence** (highest to lowest):
1. Command-line: `--set go-auth.version=v1.3.0`
2. Application-specific: `go-auth.version` in values
3. Global default: `global.version` in values
4. Chart default: `latest`

**Examples**:
```bash
# Deploy all apps with same version
make deploy ENV=dev VERSION=v1.2.3

# Deploy specific app with different version
make deploy-app APP=go-auth ENV=dev VERSION=v1.3.0

# Use versions from values file
make deploy ENV=dev
```

## Security

### Secrets Management

- All secrets stored in HashiCorp Vault
- Dynamic database credentials with 1-hour TTL
- Automatic credential rotation before expiration
- No plain text secrets in Git or Kubernetes manifests

### Network Security

- NetworkPolicies restrict pod-to-pod communication
- Ingress is the only external entry point
- TLS termination at ingress with cert-manager
- Pod Security Standards enforced (restricted for apps, baseline for infrastructure)

### Access Control

- RBAC for Kubernetes API access
- Vault policies enforce least privilege
- Separate service accounts per application
- No shared credentials between environments

## Contributing

### Adding New Applications

1. Create Helm chart in `charts/ttrpg-umbrella/charts/new-app/`
2. Add Vault database role in `scripts/vault-configure.sh`
3. Add Keycloak client in `scripts/setup-keycloak.sh`
4. Add ingress routing rules in `charts/ttrpg-umbrella/charts/ingress/templates/ingress.yaml`
5. Update umbrella chart `Chart.yaml` dependencies
6. Deploy: `make deploy-app APP=new-app ENV=dev`

### Testing Changes

```bash
# Test locally
make create-cluster
make deploy-local
make verify ENV=local

# Test with Skaffold
make skaffold-dev

# Dry run for other environments
helm upgrade --install ttrpg-dev charts/ttrpg-umbrella \
  --namespace ttrpg-dev \
  --values charts/ttrpg-umbrella/values-dev.yaml \
  --dry-run --debug
```

## License

[Your License Here]

## Support

For issues and questions:
- Review Helm chart documentation
- Check application logs: `kubectl logs -n ttrpg-local deploy/<app-name>`
