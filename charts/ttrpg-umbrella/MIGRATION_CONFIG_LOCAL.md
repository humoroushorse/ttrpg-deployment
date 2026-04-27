# Migration Configuration for Local Environment

## Overview

This document describes the migration configuration enabled in `values-local.yaml` for the TTRPG platform's local development environment.

## Enabled Services

Database migrations are now enabled for all three backend services:

1. **go-auth** - Authentication service using golang-migrate
2. **go-sprint** - Sprint management service using golang-migrate  
3. **py-dnd** - D&D service using Alembic

## Configuration Details

### Common Settings

All services share these migration configuration patterns:

- **Enabled**: `migration.enabled: true` - Migrations run automatically before deployment
- **Image**: Uses the same Docker image as the application (e.g., `localhost:5000/go-auth`)
- **Pull Policy**: `IfNotPresent` - Uses locally built images
- **Database Host**: Empty string defaults to cluster-internal DNS (`postgresql.ttrpg-local.svc.cluster.local`)
- **Database Port**: `5432` (PostgreSQL default)
- **Retry Logic**: `backoffLimit: 3` - Retries up to 3 times on failure
- **Cleanup**: `ttlSecondsAfterFinished: 3600` - Deletes completed jobs after 1 hour

### Service-Specific Configuration

#### go-auth

```yaml
migration:
  enabled: true
  image:
    repository: "localhost:5000/go-auth"
    pullPolicy: "IfNotPresent"
  database:
    name: "auth"
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "250m"
      memory: "128Mi"
  env:
    - name: LOG_LEVEL
      value: "debug"
```

- **Database**: `auth`
- **Migration Tool**: golang-migrate
- **Command**: `/app/migrate -action up`

#### go-sprint

```yaml
migration:
  enabled: true
  image:
    repository: "localhost:5000/go-sprint"
    pullPolicy: "IfNotPresent"
  database:
    name: "sprint_management"
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "250m"
      memory: "128Mi"
  env:
    - name: LOG_LEVEL
      value: "debug"
```

- **Database**: `sprint_management`
- **Migration Tool**: golang-migrate
- **Command**: `/app/migrate -action up`

#### py-dnd

```yaml
migration:
  enabled: true
  image:
    repository: "localhost:5000/py-dnd"
    pullPolicy: "IfNotPresent"
  database:
    name: "dnd"
  resources:
    requests:
      cpu: "50m"
      memory: "128Mi"
    limits:
      cpu: "250m"
      memory: "256Mi"
  env:
    - name: LOG_LEVEL
      value: "DEBUG"
    - name: PYTHONUNBUFFERED
      value: "1"
```

- **Database**: `dnd`
- **Migration Tool**: Alembic
- **Command**: `alembic upgrade head`
- **Note**: Slightly higher memory allocation (128Mi request) for Python runtime

## Resource Allocation

Migration jobs use minimal resources suitable for local development:

### Go Services (go-auth, go-sprint)
- **CPU Request**: 50m (0.05 cores)
- **CPU Limit**: 250m (0.25 cores)
- **Memory Request**: 64Mi
- **Memory Limit**: 128Mi

### Python Service (py-dnd)
- **CPU Request**: 50m (0.05 cores)
- **CPU Limit**: 250m (0.25 cores)
- **Memory Request**: 128Mi (higher for Python)
- **Memory Limit**: 256Mi (higher for Python)

## Environment Variables

### Go Services
- `LOG_LEVEL=debug` - Enables detailed logging for troubleshooting

### Python Service
- `LOG_LEVEL=DEBUG` - Uppercase for loguru compatibility
- `PYTHONUNBUFFERED=1` - Ensures logs are flushed immediately for real-time viewing

## Deployment Behavior

### Execution Order

1. **Pre-Install/Pre-Upgrade Hook**: Migration jobs are triggered by Helm hooks
2. **Migration Execution**: Jobs run database migrations using Vault credentials
3. **Success Check**: Helm waits for migration jobs to complete successfully
4. **Application Deployment**: Application pods start only after migrations succeed
5. **Cleanup**: Completed migration jobs are deleted after 1 hour

### Failure Handling

If a migration fails:

1. **Retry**: Kubernetes retries up to 3 times (backoffLimit)
2. **Block**: Application deployment is blocked until migration succeeds
3. **Manual Intervention**: Operator must investigate and fix the issue
4. **Recovery**: Fix the migration, rebuild the image, and redeploy

## Verification Commands

### Check Migration Job Status

```bash
# List all migration jobs
kubectl get jobs -n ttrpg-local | grep migration

# Check specific migration job
kubectl get job go-auth-migration -n ttrpg-local
kubectl get job go-sprint-migration -n ttrpg-local
kubectl get job py-dnd-migration -n ttrpg-local
```

### View Migration Logs

```bash
# View logs for specific migration
kubectl logs job/go-auth-migration -n ttrpg-local
kubectl logs job/go-sprint-migration -n ttrpg-local
kubectl logs job/py-dnd-migration -n ttrpg-local
```

### Verify Database Schema Version

```bash
# For Go services (golang-migrate)
kubectl exec -n ttrpg-local deploy/go-auth -- /app/migrate -action version
kubectl exec -n ttrpg-local deploy/go-sprint -- /app/migrate -action version

# For Python service (Alembic)
kubectl exec -n ttrpg-local deploy/py-dnd -- alembic current
```

## Troubleshooting

### Migration Job Fails

1. Check job status: `kubectl describe job <service>-migration -n ttrpg-local`
2. View logs: `kubectl logs job/<service>-migration -n ttrpg-local`
3. Common issues:
   - Database not ready: Wait for PostgreSQL to be fully ready
   - Vault credentials not available: Ensure Vault is configured
   - Migration syntax error: Fix migration files and rebuild image
   - Database connection error: Check database host and credentials

### Migration Job Stuck

1. Check pod status: `kubectl get pods -n ttrpg-local | grep migration`
2. Describe pod: `kubectl describe pod <migration-pod> -n ttrpg-local`
3. Check events: `kubectl get events -n ttrpg-local --sort-by='.lastTimestamp'`

### Retry Failed Migration

```bash
# Delete the failed job
kubectl delete job <service>-migration -n ttrpg-local

# Redeploy the service (triggers new migration job)
helm upgrade ttrpg ./charts/ttrpg-umbrella -f values-local.yaml -n ttrpg-local
```

## Requirements Validation

This configuration satisfies the following requirements from the deployment-completion spec:

- **Requirement 2.1**: py-dnd migration job executes Alembic migrations before application starts
- **Requirement 2.2**: go-sprint migration job executes golang-migrate migrations before application starts
- **Requirement 2.3**: go-auth migration job executes golang-migrate migrations before application starts

## Next Steps

1. **Build Images**: Ensure application Docker images include migration files
2. **Test Locally**: Deploy to local cluster and verify migrations run successfully
3. **Monitor Logs**: Watch migration job logs during deployment
4. **Verify Schema**: Check database schema versions after deployment

## References

- [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) - Comprehensive migration documentation
- [MIGRATION_IMPLEMENTATION_SUMMARY.md](./MIGRATION_IMPLEMENTATION_SUMMARY.md) - Implementation details
- [values-local.yaml](./values-local.yaml) - Complete local environment configuration
