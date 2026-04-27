# Database Migration Guide

This document explains how database migrations work in the TTRPG Helm deployment infrastructure.

## Overview

Database migrations are automatically executed before application deployments using Kubernetes Jobs with Helm hooks. This ensures that the database schema is always up-to-date before the application starts.

## How It Works

### Helm Hooks

Migration jobs use Helm hooks to run at the right time:

- **Hook**: `pre-install,pre-upgrade` - Runs before the application is installed or upgraded
- **Hook Weight**: `-5` - Runs early in the deployment sequence (before application pods)
- **Delete Policy**: `before-hook-creation` - Cleans up old migration jobs before creating new ones

### Job Configuration

Each migration job is configured with:

- **Retry Logic**: `backoffLimit: 3` - Retries up to 3 times on failure
- **Cleanup**: `ttlSecondsAfterFinished: 86400` - Deletes completed jobs after 24 hours
- **Restart Policy**: `OnFailure` - Restarts the container if it fails
- **Blocking Behavior**: If the migration job fails, the application deployment is blocked

### Vault Integration

Migration jobs use Vault Agent Injector to retrieve database credentials:

1. Vault Agent sidecar injects credentials into `/vault/secrets/database`
2. Migration script sources the credentials
3. Builds `DATABASE_URL` from the injected credentials
4. Runs migrations with dynamic credentials

## Application-Specific Migrations

### go-auth

**Migration Tool**: golang-migrate

**Command**: `/app/migrate -action up`

**Migration Path**: `/app/migrations` (mounted from application image)

**Verification**: Runs `/app/migrate -action version` to verify success

**Requirements**:
- Application image must include the `migrate` binary at `/app/migrate`
- Migration files must be present in `/app/migrations`

### go-sprint

**Migration Tool**: golang-migrate

**Command**: `/app/migrate -action up`

**Migration Path**: `/app/migrations` (mounted from application image)

**Verification**: Runs `/app/migrate -action version` to verify success

**Requirements**:
- Application image must include the `migrate` binary at `/app/migrate`
- Migration files must be present in `/app/migrations`
- Uses the same migration structure as go-auth

### py-dnd

**Migration Tool**: Alembic

**Command**: `alembic upgrade head`

**Migration Path**: `/app/migrations` (mounted from application image)

**Verification**: Runs `alembic current` to verify success

**Requirements**:
- Application image must include Alembic and migration files
- `alembic.ini` must be configured correctly
- Migration versions must be in `/app/migrations/versions`

## Configuration

### Enabling/Disabling Migrations

Migrations can be enabled or disabled per application in values files:

```yaml
go-auth:
  migration:
    enabled: true  # Set to false to disable migrations
```

### Resource Configuration

Migration jobs have their own resource limits:

```yaml
go-auth:
  migration:
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "256Mi"
```

### Database Connection

Database connection settings can be customized:

```yaml
go-auth:
  migration:
    database:
      host: "postgresql.ttrpg-local.svc.cluster.local"
      port: "5432"
      name: "auth"  # Defaults to .Values.database.name
```

### Environment-Specific Configuration

Migration settings are configured per environment:

**Local** (`values-local.yaml`):
- Minimal resources (50m CPU, 64-128Mi memory)
- Enabled by default

**Dev** (`values-dev.yaml`):
- Moderate resources (100m CPU, 128-256Mi memory)
- Enabled by default

**Prod** (`values-prod.yaml`):
- Production resources (200m CPU, 256-512Mi memory)
- Enabled by default

## Idempotency

All migration tools are designed to be idempotent:

- **golang-migrate**: Tracks applied migrations in `schema_migrations` table
- **Alembic**: Tracks applied migrations in `alembic_version` table

Running migrations multiple times will:
1. Check the current schema version
2. Skip already-applied migrations
3. Apply only new migrations
4. Result in the same database state

## Error Handling

### Migration Failures

If a migration job fails:

1. **Detection**: Job exits with non-zero status
2. **Retry**: Kubernetes retries up to 3 times (backoffLimit)
3. **Blocking**: Application deployment is blocked via Helm hooks
4. **Recovery**: Manual intervention required

### Recovery Steps

1. Check migration job logs:
   ```bash
   kubectl logs -n ttrpg-local job/go-auth-migration
   ```

2. Identify the failure reason (syntax error, constraint violation, etc.)

3. Fix the migration in the source repository

4. Rebuild and push the application image

5. Re-run the Helm deployment:
   ```bash
   helm upgrade ttrpg-local charts/ttrpg-umbrella -f charts/ttrpg-umbrella/values-local.yaml
   ```

### Common Issues

**Issue**: Migration job can't connect to database
- **Cause**: Database not ready or Vault credentials not available
- **Solution**: Ensure PostgreSQL and Vault are running and healthy

**Issue**: Migration syntax error
- **Cause**: Invalid SQL in migration file
- **Solution**: Fix the migration file and rebuild the image

**Issue**: Migration constraint violation
- **Cause**: Data doesn't meet new constraints
- **Solution**: Add data migration step or adjust constraints

**Issue**: Migration timeout
- **Cause**: Large data migration taking too long
- **Solution**: Increase job timeout or split into smaller migrations

## Verification

### Check Migration Status

After deployment, verify migrations ran successfully:

```bash
# Check job status
kubectl get jobs -n ttrpg-local | grep migration

# Check job logs
kubectl logs -n ttrpg-local job/go-auth-migration
kubectl logs -n ttrpg-local job/go-sprint-migration
kubectl logs -n ttrpg-local job/py-dnd-migration

# Verify database schema version (go-auth/go-sprint)
kubectl exec -n ttrpg-local deploy/go-auth -- /app/migrate -action version

# Verify database schema version (py-dnd)
kubectl exec -n ttrpg-local deploy/py-dnd -- alembic current
```

### Manual Migration Verification

Connect to the database and check migration tables:

```bash
# Port forward to PostgreSQL
kubectl port-forward -n ttrpg-local svc/postgresql 5432:5432

# Connect and check migrations (golang-migrate)
psql -h localhost -U <user> -d auth -c "SELECT * FROM schema_migrations;"

# Connect and check migrations (Alembic)
psql -h localhost -U <user> -d dnd -c "SELECT * FROM alembic_version;"
```

## Best Practices

### Writing Migrations

1. **Make migrations reversible**: Always provide down migrations
2. **Test migrations**: Test on a copy of production data
3. **Keep migrations small**: One logical change per migration
4. **Use transactions**: Wrap migrations in transactions when possible
5. **Document changes**: Add comments explaining complex migrations

### Deployment Strategy

1. **Test in local first**: Always test migrations locally
2. **Deploy to dev**: Verify migrations work in dev environment
3. **Backup before prod**: Always backup production database before deploying
4. **Monitor closely**: Watch migration job logs during production deployment
5. **Have rollback plan**: Know how to rollback if migrations fail

### Security

1. **Use Vault credentials**: Never hardcode database credentials
2. **Limit permissions**: Migration jobs should have minimal required permissions
3. **Audit migrations**: Review all migrations before deployment
4. **Encrypt backups**: Always encrypt database backups

## Troubleshooting

### Debug Mode

To debug migration issues, you can run migrations manually:

```bash
# Get a shell in the migration job pod (if it's still running)
kubectl exec -it -n ttrpg-local job/go-auth-migration -- /bin/sh

# Or run a debug pod with the same image
kubectl run -it --rm debug --image=ghcr.io/your-org/go-auth:latest -n ttrpg-local -- /bin/sh

# Inside the pod, source Vault secrets and run migrations manually
source /vault/secrets/database
export DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgresql:5432/auth"
/app/migrate -action up
```

### Disable Migrations Temporarily

If you need to deploy without running migrations:

```bash
helm upgrade ttrpg-local charts/ttrpg-umbrella \
  -f charts/ttrpg-umbrella/values-local.yaml \
  --set go-auth.migration.enabled=false \
  --set go-sprint.migration.enabled=false \
  --set py-dnd.migration.enabled=false
```

### Force Migration Re-run

To force migrations to run again:

```bash
# Delete the migration job
kubectl delete job -n ttrpg-local go-auth-migration

# Re-run Helm upgrade
helm upgrade ttrpg-local charts/ttrpg-umbrella -f charts/ttrpg-umbrella/values-local.yaml
```

## References

- [golang-migrate Documentation](https://github.com/golang-migrate/migrate)
- [Alembic Documentation](https://alembic.sqlalchemy.org/)
- [Helm Hooks Documentation](https://helm.sh/docs/topics/charts_hooks/)
- [Kubernetes Jobs Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
