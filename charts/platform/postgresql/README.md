# PostgreSQL Helm Chart

This Helm chart deploys PostgreSQL with Vault integration for dynamic credential generation.

## Features

- **Two Deployment Modes**:
  - **StatefulSet Mode** (default): Simple single-instance deployment for local/dev
  - **Operator Mode**: High-availability deployment using PostgreSQL operators for production

- **Vault Integration**: Dynamic database credential generation with automatic rotation
- **Automatic Initialization**: Creates databases and vault_admin user on first startup
- **Unicode Password Support**: Supports Unicode passwords for enhanced security
- **Multiple Databases**: Creates separate databases for each application (auth, sprint_management, dnd, keycloak)

## Deployment Modes

### StatefulSet Mode (Default)

Simple deployment suitable for local development and testing:

```yaml
mode: statefulset
statefulset:
  replicas: 1
  storage:
    size: 10Gi
```

**Characteristics**:
- Single PostgreSQL instance
- Persistent volume for data storage
- Automatic database initialization via ConfigMap
- Suitable for local/dev environments

### Operator Mode (Production)

High-availability deployment using PostgreSQL operators:

```yaml
mode: operator
operator:
  type: zalando  # or "cloudnativepg"
  zalando:
    numberOfInstances: 2
    enableConnectionPooler: true
```

**Characteristics**:
- Multiple PostgreSQL instances (2+)
- Streaming replication
- Automated failover
- Connection pooling (PgBouncer)
- Automated backups
- Suitable for production environments

#### Supported Operators

1. **Zalando PostgreSQL Operator**
   - Mature and battle-tested
   - Built-in connection pooling
   - Logical backups
   - Patroni for HA

2. **CloudNativePG**
   - Cloud-native design
   - Built-in monitoring
   - Backup to S3-compatible storage
   - PgBouncer integration

## Vault Integration

### Database Secrets Engine

The chart integrates with Vault's database secrets engine to provide dynamic credentials:

1. **Connection Configuration**: Vault connects to PostgreSQL using the `vault_admin` user
2. **Dynamic Credentials**: Applications request credentials from Vault, which creates temporary database users
3. **Automatic Rotation**: Credentials are automatically rotated before expiration
4. **Root Rotation**: Vault automatically rotates the `vault_admin` password

### Credential Flow

```
Application Pod → Vault Agent → Vault → PostgreSQL
                     ↓
              Dynamic User Created
              (TTL: 1 hour, Max: 24 hours)
```

### Configuration

The Vault database secrets engine is configured with:

```hcl
connection_url = "postgresql://{{username}}:{{password}}@postgresql.ttrpg-{env}.svc.cluster.local:5432/postgres"
username = "vault_admin"
password_policy = "unicode-password-policy"
rotate_root_credentials = true
```

### Application Roles

Each application has a dedicated Vault role with scoped permissions:

- **go-auth-role**: Access to `auth` database
- **go-sprint-role**: Access to `sprint_management` database
- **py-dnd-role**: Access to `dnd` database
- **keycloak-role**: Access to `keycloak` database

## Database Initialization

On first startup, PostgreSQL executes the initialization script that:

1. Creates databases: `auth`, `sprint_management`, `dnd`, `keycloak`
2. Creates `vault_admin` user with SUPERUSER privileges
3. Grants all privileges on databases to `vault_admin`
4. Enables extensions: `uuid-ossp`, `pgcrypto`

## Values Configuration

### Global Values

```yaml
global:
  environment: local  # local, dev, prod
```

### PostgreSQL Values

```yaml
postgresql:
  enabled: true
  mode: statefulset  # or "operator"
  
  # StatefulSet configuration
  statefulset:
    replicas: 1
    storage:
      size: 10Gi
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 1Gi
  
  # Operator configuration
  operator:
    type: zalando  # or "cloudnativepg"
    zalando:
      numberOfInstances: 2
      enableConnectionPooler: true
```

## Usage

### Deploy with StatefulSet Mode

```bash
helm install ttrpg-umbrella ./charts/ttrpg-umbrella \
  --set postgresql.mode=statefulset \
  --set global.environment=local
```

### Deploy with Operator Mode

```bash
# Install PostgreSQL operator first
helm install postgres-operator postgres-operator-charts/postgres-operator

# Deploy PostgreSQL cluster
helm install ttrpg-umbrella ./charts/ttrpg-umbrella \
  --set postgresql.mode=operator \
  --set postgresql.operator.type=zalando \
  --set global.environment=prod
```

### Configure Vault Integration

After deploying PostgreSQL, configure Vault:

```bash
# Run the setup script
./scripts/setup-database-roles.sh prod

# This will:
# 1. Configure Vault database secrets engine
# 2. Rotate root credentials
# 3. Create application roles
# 4. Create Vault policies
```

## Accessing PostgreSQL

### From Within Cluster

Applications access PostgreSQL via the service:

```
postgresql.ttrpg-{environment}.svc.cluster.local:5432
```

### Port Forwarding (Local Development)

```bash
kubectl port-forward -n ttrpg-local svc/postgresql 5432:5432
psql -h localhost -U postgres -d auth
```

### With Operator Mode

When using operators, access via the pooler service for better performance:

```
postgresql-pooler.ttrpg-{environment}.svc.cluster.local:5432
```

## Monitoring

### Health Checks

The StatefulSet includes liveness and readiness probes:

```yaml
livenessProbe:
  exec:
    command: ["pg_isready", "-U", "postgres"]
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  exec:
    command: ["pg_isready", "-U", "postgres"]
  initialDelaySeconds: 5
  periodSeconds: 5
```

### Metrics (Operator Mode)

PostgreSQL operators expose Prometheus metrics:

- Connection counts
- Query performance
- Replication lag
- Database size

## Backup and Recovery

### StatefulSet Mode

Backups are handled via CronJobs (configured separately):

```bash
# Manual backup
kubectl exec -n ttrpg-local postgresql-0 -- \
  pg_dump -U postgres auth > auth-backup.sql
```

### Operator Mode

Operators provide automated backups:

- **Zalando**: Logical backups to S3
- **CloudNativePG**: WAL archiving and PITR

## Troubleshooting

### Pod Not Starting

Check logs:
```bash
kubectl logs -n ttrpg-local postgresql-0
```

Common issues:
- PVC not bound (check storage class)
- Insufficient resources
- Init script errors

### Vault Connection Issues

Verify Vault is accessible:
```bash
kubectl exec -n ttrpg-local postgresql-0 -- \
  nc -zv vault.vault.svc.cluster.local 8200
```

### Database Connection Refused

Check if PostgreSQL is ready:
```bash
kubectl exec -n ttrpg-local postgresql-0 -- pg_isready
```

## Migration from StatefulSet to Operator

To migrate from StatefulSet to Operator mode:

1. **Backup Data**:
   ```bash
   kubectl exec postgresql-0 -- pg_dumpall -U postgres > full-backup.sql
   ```

2. **Deploy Operator**:
   ```bash
   helm upgrade ttrpg-umbrella ./charts/ttrpg-umbrella \
     --set postgresql.mode=operator
   ```

3. **Restore Data**:
   ```bash
   kubectl exec postgresql-0 -- psql -U postgres < full-backup.sql
   ```

4. **Verify**:
   ```bash
   kubectl get postgresql -n ttrpg-prod
   ```

## Security Considerations

- **Vault Admin Password**: Automatically rotated by Vault
- **Application Credentials**: Short-lived (1 hour TTL)
- **Network Policies**: Restrict access to PostgreSQL service
- **TLS**: Enable SSL for production deployments
- **Unicode Passwords**: Enhanced entropy with Unicode character sets

## References

- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/)
- [Zalando PostgreSQL Operator](https://github.com/zalando/postgres-operator)
- [CloudNativePG](https://cloudnative-pg.io/)
- [Vault Database Secrets Engine](https://www.vaultproject.io/docs/secrets/databases/postgresql)
