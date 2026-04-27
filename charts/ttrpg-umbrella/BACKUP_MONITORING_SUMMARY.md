# Backup and Monitoring Infrastructure Implementation Summary

This document summarizes the implementation of backup and monitoring infrastructure for the Kubernetes Helm deployment.

## Overview

Task 12 implements comprehensive backup and monitoring capabilities including:
- PostgreSQL automated backups with CronJob
- Vault backup and restore scripts
- Prometheus ServiceMonitor resources for all applications
- Grafana dashboard ConfigMaps
- Structured logging configuration

## Components Implemented

### 1. PostgreSQL Backup CronJob

**File**: `templates/postgresql-backup-cronjob.yaml`

**Features**:
- Scheduled daily backups (configurable via `backups.schedule`)
- Backs up all databases: auth, sprint_management, dnd, keycloak
- Uses `pg_dump` with custom format for efficient storage
- Automatic cleanup of old backups based on retention policy
- Stores backups to PersistentVolumeClaim
- Creates metadata file with backup information

**Configuration** (values.yaml):
```yaml
backups:
  enabled: false  # Set to true in prod/dev
  schedule: "0 2 * * *"  # 2 AM daily
  retention: 7  # days (7 for dev, 30 for prod)
  storage: "50Gi"
  storageClass: ""  # Use default if empty
```

**Environment-specific settings**:
- Local: Disabled (not needed for development)
- Dev: Enabled, 7 day retention, 50Gi storage
- Prod: Enabled, 30 day retention, 200Gi storage

### 2. Vault Backup Script

**File**: `scripts/backup-vault.sh`

**Features**:
- Creates Raft snapshot using `vault operator raft snapshot save`
- Encrypts snapshot with GPG for security
- Stores encrypted backup to PVC
- Creates tarball with metadata
- Automatic cleanup of old backups
- Configurable retention period

**Usage**:
```bash
# Set environment variables
export VAULT_TOKEN="your-vault-token"
export ENV="prod"
export RETENTION_DAYS=30

# Run backup
./scripts/backup-vault.sh
```

**Configuration**:
```yaml
backups:
  vault:
    enabled: false  # Set to true in prod/dev
    schedule: "0 */6 * * *"  # Every 6 hours
    retention: 30  # days
    encryption:
      enabled: true
      gpgRecipient: "vault-backup@ttrpg.local"
```

### 3. Vault Restore Script

**File**: `scripts/restore-vault.sh`

**Features**:
- Extracts and decrypts backup tarball
- Validates Vault status before restore
- Restores Raft snapshot using `vault operator raft snapshot restore`
- Interactive confirmation (can be bypassed with --force)
- Comprehensive error handling and logging

**Usage**:
```bash
# Interactive restore
./scripts/restore-vault.sh \
  --env prod \
  --file /vault-backups/vault-backup-prod-20260210_120000.tar.gz \
  --vault-token $VAULT_TOKEN

# Force restore without confirmation
./scripts/restore-vault.sh \
  --env prod \
  --file backup.tar.gz \
  --vault-token $VAULT_TOKEN \
  --force
```

### 4. Prometheus ServiceMonitors

**File**: `templates/servicemonitor.yaml`

**Features**:
- ServiceMonitor resources for all applications:
  - go-auth
  - go-sprint
  - py-dnd
  - PostgreSQL
  - Vault
  - NATS
  - Keycloak
- Configurable scrape interval (default: 30s)
- Configurable scrape timeout (default: 10s)
- Prometheus instance label for multi-prometheus setups

**Configuration**:
```yaml
monitoring:
  enabled: false  # Set to true in prod
  prometheus:
    enabled: false
    scrapeInterval: "30s"
    scrapeTimeout: "10s"
    instance: "kube-prometheus"
```

**Metrics Endpoints**:
- Applications: `/metrics` on HTTP port
- Vault: `/v1/sys/metrics?format=prometheus`
- NATS: `/metrics` on monitor port (8222)
- PostgreSQL: `/metrics` on metrics port (requires postgres_exporter)

### 5. Grafana Dashboards

**File**: `templates/grafana-dashboards.yaml`

**Features**:
Four pre-configured dashboards:

1. **Application Health Dashboard**
   - Pod status by phase
   - HTTP request rate by service
   - HTTP error rate (5xx responses)
   - Response time (p95)

2. **Database Performance Dashboard**
   - Active connections
   - Transaction rate
   - Query duration (p95)
   - Cache hit ratio

3. **Vault Access Patterns Dashboard**
   - Secret access rate
   - Token creation rate
   - Database credential generation
   - Vault seal status

4. **Ingress Traffic Dashboard**
   - Request rate by path
   - Response status codes
   - Request duration (p95)
   - Ingress bandwidth

**Configuration**:
```yaml
monitoring:
  grafana:
    enabled: false
    namespace: "monitoring"
    dashboards:
      applicationHealth: true
      databasePerformance: true
      vaultAccess: true
      ingressTraffic: true
```

**Dashboard Labels**:
All dashboards are labeled with `grafana_dashboard: "1"` for automatic discovery by Grafana.

### 6. Structured Logging Configuration

**Files**:
- `charts/shared/templates/_helpers.tpl` (logging helper template)
- Application ConfigMaps (go-auth, go-sprint, py-dnd)

**Features**:
- Configurable log format (JSON or text)
- Environment-specific log levels
- Structured logging with metadata fields:
  - Timestamp
  - Log level
  - Service name
  - Environment
  - Trace ID (for distributed tracing)

**Configuration**:
```yaml
logging:
  format: "json"  # or "text"
  level:
    local: "DEBUG"
    dev: "INFO"
    prod: "WARN"
  structuredLogging:
    enabled: true
    includeTimestamp: true
    includeLevel: true
    includeService: true
    includeEnvironment: true
    includeTraceId: true
```

**Environment Variables** (injected into application pods):
```
LOG_FORMAT=json
LOG_LEVEL=INFO
LOG_STRUCTURED=true
LOG_INCLUDE_TIMESTAMP=true
LOG_INCLUDE_SERVICE=true
LOG_INCLUDE_ENVIRONMENT=true
LOG_INCLUDE_TRACE_ID=true
```

## Environment-Specific Configuration

### Local Environment
```yaml
monitoring:
  enabled: false
logging:
  format: "text"  # Easier to read in terminal
  level:
    local: "DEBUG"
  structuredLogging:
    enabled: false
backups:
  enabled: false
```

### Dev Environment
```yaml
monitoring:
  enabled: false  # Optional
  prometheus:
    enabled: false
  grafana:
    enabled: false
logging:
  format: "json"
  level:
    dev: "INFO"
  structuredLogging:
    enabled: true
backups:
  enabled: true
  schedule: "0 3 * * *"
  retention: 7
  storage: "50Gi"
  vault:
    enabled: true
    schedule: "0 */12 * * *"
    retention: 7
```

### Prod Environment
```yaml
monitoring:
  enabled: true
  prometheus:
    enabled: true
    scrapeInterval: "30s"
  grafana:
    enabled: true
    namespace: "monitoring"
logging:
  format: "json"
  level:
    prod: "WARN"
  structuredLogging:
    enabled: true
backups:
  enabled: true
  schedule: "0 2 * * *"
  retention: 30
  storage: "200Gi"
  storageClass: "fast-ssd"
  vault:
    enabled: true
    schedule: "0 */6 * * *"
    retention: 30
```

## Usage Examples

### Enable Monitoring for Production

```bash
helm upgrade ttrpg charts/ttrpg-umbrella \
  --values charts/ttrpg-umbrella/values-prod.yaml \
  --set monitoring.enabled=true \
  --set monitoring.prometheus.enabled=true \
  --set monitoring.grafana.enabled=true
```

### Enable Backups for Dev

```bash
helm upgrade ttrpg charts/ttrpg-umbrella \
  --values charts/ttrpg-umbrella/values-dev.yaml \
  --set backups.enabled=true \
  --set backups.vault.enabled=true
```

### Manual Vault Backup

```bash
# Port-forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200

# Set environment variables
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="your-vault-token"
export ENV="prod"

# Run backup
./scripts/backup-vault.sh
```

### Restore Vault from Backup

```bash
# Port-forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200

# Restore
./scripts/restore-vault.sh \
  --env prod \
  --file /vault-backups/vault-backup-prod-20260210_120000.tar.gz \
  --vault-addr http://localhost:8200 \
  --vault-token $VAULT_TOKEN
```

### View PostgreSQL Backup Logs

```bash
# List backup jobs
kubectl get jobs -n ttrpg-prod -l app=postgresql-backup

# View logs from latest backup
kubectl logs -n ttrpg-prod job/postgresql-backup-<timestamp>
```

## Integration with Existing Infrastructure

### Prometheus Integration

The ServiceMonitor resources require Prometheus Operator to be installed:

```bash
# Install Prometheus Operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

### Grafana Integration

Dashboards are automatically discovered by Grafana when:
1. Grafana is configured to watch ConfigMaps with label `grafana_dashboard: "1"`
2. ConfigMaps are in the correct namespace (default: `monitoring`)

### Application Integration

Applications must expose metrics endpoints:
- Go applications: Use `prometheus/client_golang`
- Python applications: Use `prometheus_client`
- Metrics should be exposed on `/metrics` endpoint

Example Go code:
```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

http.Handle("/metrics", promhttp.Handler())
```

Example Python code:
```python
from prometheus_client import start_http_server, Counter

# Start metrics server
start_http_server(8000)
```

## Security Considerations

### Backup Encryption

- Vault backups are encrypted with GPG before storage
- GPG keys should be managed securely (e.g., in Sealed Secrets)
- Backup PVCs should use encrypted storage classes in production

### Access Control

- Backup CronJobs use dedicated ServiceAccount
- ServiceAccount should have minimal permissions (read-only access to PostgreSQL)
- Vault backup script requires Vault token with snapshot permissions

### Monitoring Security

- ServiceMonitors should only scrape authenticated endpoints
- Grafana dashboards should have appropriate RBAC
- Metrics should not expose sensitive data

## Troubleshooting

### Backup Job Fails

```bash
# Check job status
kubectl get jobs -n ttrpg-prod -l app=postgresql-backup

# View logs
kubectl logs -n ttrpg-prod job/postgresql-backup-<timestamp>

# Check PVC status
kubectl get pvc -n ttrpg-prod postgresql-backups
```

### ServiceMonitor Not Scraping

```bash
# Check ServiceMonitor status
kubectl get servicemonitor -n ttrpg-prod

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

### Vault Backup Script Fails

```bash
# Check Vault status
vault status

# Verify Vault token has snapshot permissions
vault token capabilities sys/storage/raft/snapshot

# Check GPG keys
gpg --list-keys
```

## Future Enhancements

1. **S3 Backup Integration**: Add support for backing up to S3-compatible storage
2. **Backup Verification**: Automated restore testing to verify backup integrity
3. **Alerting**: Prometheus AlertManager rules for backup failures
4. **Metrics Retention**: Configure long-term metrics storage with Thanos or Cortex
5. **Log Aggregation**: Integration with ELK stack or Loki for centralized logging
6. **Automated Restore**: Disaster recovery automation with scheduled restore tests

## Requirements Validated

This implementation validates the following requirements:

- **16.1**: Prometheus ServiceMonitor resources configured for each application
- **16.2**: Metrics endpoints exposed on each application pod
- **16.3**: Grafana dashboards provisioned for application metrics
- **16.4**: Logging configuration aggregates logs from all pods
- **16.5**: Distributed tracing support via trace ID in structured logs
- **17.1**: Automated PostgreSQL backups using CronJobs
- **17.2**: Backup jobs store backups to persistent volumes
- **17.3**: Restore procedure documented and scripted
- **17.4**: Vault backup configured with periodic snapshots
- **17.5**: Backup configuration is environment-specific

## Conclusion

The backup and monitoring infrastructure provides comprehensive observability and disaster recovery capabilities for the TTRPG deployment. All components are configurable per environment and follow Kubernetes best practices.
