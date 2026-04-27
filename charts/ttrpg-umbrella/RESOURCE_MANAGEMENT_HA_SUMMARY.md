# Resource Management and HA Features Implementation Summary

This document summarizes the implementation of resource management and high availability features for the Kubernetes Helm deployment infrastructure.

## Implemented Features

### 1. ResourceQuota Template
**Location**: `charts/ttrpg-umbrella/templates/resourcequota.yaml`

Creates namespace-level resource quotas to prevent resource exhaustion:
- Limits CPU requests/limits
- Limits memory requests/limits
- Limits number of PersistentVolumeClaims

**Environment-Specific Configuration**:
- **Local**: 1 CPU request, 2Gi memory, 2 CPU limit, 4Gi memory limit
- **Dev**: 4 CPU request, 8Gi memory, 8 CPU limit, 16Gi memory limit (default)
- **Prod**: 16 CPU request, 32Gi memory, 32 CPU limit, 64Gi memory limit

### 2. LimitRange Template
**Location**: `charts/ttrpg-umbrella/templates/limitrange.yaml`

Sets default resource requests/limits for containers and PVCs:
- Default CPU and memory for containers without explicit limits
- Minimum and maximum constraints
- PVC storage limits

**Environment-Specific Configuration**:
- **Local**: Lower defaults (25m CPU, 32Mi memory)
- **Dev**: Moderate defaults (50m CPU, 64Mi memory)
- **Prod**: Higher defaults (100m CPU, 128Mi memory)

### 3. PodDisruptionBudget Templates
**Location**: Each application chart's `templates/poddisruptionbudget.yaml`

Ensures minimum availability during voluntary disruptions (node drains, updates):
- Single replica: `minAvailable: 1`
- Multiple replicas: `minAvailable: 50%` (configurable)

**Implemented for**:
- go-auth
- go-sprint
- py-dnd
- ui-dnd
- ui-sprint-management

**Configuration**:
```yaml
podDisruptionBudget:
  enabled: false  # true in prod
  minAvailable: "50%"  # or specific number
```

### 4. HorizontalPodAutoscaler Templates
**Location**: Each application chart's `templates/horizontalpodautoscaler.yaml`

Automatically scales pods based on CPU/memory utilization:
- Target CPU: 70% (configurable)
- Target Memory: 80% (configurable)
- Min replicas: 2 (configurable)
- Max replicas: 10 (configurable)
- Smart scaling behavior with stabilization windows

**Implemented for**:
- go-auth
- go-sprint
- py-dnd
- ui-dnd
- ui-sprint-management

**Configuration**:
```yaml
autoscaling:
  enabled: false  # true in prod
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

### 5. Rolling Update Strategy
**Location**: `charts/shared/templates/_deploymentstrategy.tpl`

Implements zero-downtime rolling updates:
- Strategy: `RollingUpdate`
- `maxSurge: 1` - allows one extra pod during updates
- `maxUnavailable: 0` - ensures no pods are unavailable during updates

**Applied to all application deployments**:
- go-auth
- go-sprint
- py-dnd
- ui-dnd
- ui-sprint-management

### 6. Replica Count Configuration
**Environment-Specific Replica Counts**:

**Local** (values-local.yaml):
- All applications: 1 replica
- Focus on minimal resource usage

**Dev** (values-dev.yaml):
- Backend services: 1-2 replicas
- Frontend services: 1 replica
- Balance between testing and resources

**Prod** (values-prod.yaml):
- Backend services (go-auth, go-sprint, py-dnd): 3 replicas
- Frontend services (ui-dnd, ui-sprint-management): 2 replicas
- Infrastructure services (Vault, PostgreSQL, NATS, Keycloak): 2-3 replicas
- Full HA configuration

## Configuration Examples

### Enable PDB and HPA for Production

In `values-prod.yaml`:
```yaml
go-auth:
  replicaCount: 3
  podDisruptionBudget:
    enabled: true
    minAvailable: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
```

### Disable for Local Development

In `values-local.yaml`:
```yaml
go-auth:
  replicaCount: 1
  podDisruptionBudget:
    enabled: false
  autoscaling:
    enabled: false
```

### Override at Deploy Time

```bash
# Deploy with custom replica count
helm install ttrpg charts/ttrpg-umbrella \
  --values values-prod.yaml \
  --set go-auth.replicaCount=5

# Enable autoscaling for specific app
helm install ttrpg charts/ttrpg-umbrella \
  --values values-dev.yaml \
  --set go-auth.autoscaling.enabled=true \
  --set go-auth.autoscaling.minReplicas=2 \
  --set go-auth.autoscaling.maxReplicas=5
```

## Verification

### Check ResourceQuota
```bash
kubectl get resourcequota -n ttrpg-prod
kubectl describe resourcequota -n ttrpg-prod
```

### Check LimitRange
```bash
kubectl get limitrange -n ttrpg-prod
kubectl describe limitrange -n ttrpg-prod
```

### Check PodDisruptionBudgets
```bash
kubectl get pdb -n ttrpg-prod
kubectl describe pdb go-auth -n ttrpg-prod
```

### Check HorizontalPodAutoscalers
```bash
kubectl get hpa -n ttrpg-prod
kubectl describe hpa go-auth -n ttrpg-prod
```

### Verify Rolling Update Strategy
```bash
kubectl get deployment go-auth -n ttrpg-prod -o yaml | grep -A 5 strategy
```

## Benefits

### Resource Management
- **Prevents resource exhaustion**: ResourceQuota ensures no single namespace consumes all cluster resources
- **Consistent defaults**: LimitRange provides sensible defaults for pods without explicit limits
- **Cost control**: Helps manage cloud costs by limiting resource usage

### High Availability
- **Zero-downtime updates**: Rolling update strategy ensures continuous availability
- **Automatic scaling**: HPA adjusts capacity based on actual load
- **Disruption protection**: PDB prevents too many pods from being unavailable simultaneously
- **Resilience**: Multiple replicas protect against node failures

### Operational Excellence
- **Environment-appropriate configuration**: Different settings for local/dev/prod
- **Flexible overrides**: Can adjust settings at deploy time
- **Kubernetes-native**: Uses standard Kubernetes resources and patterns

## Requirements Validated

This implementation validates the following requirements from the design document:

- **Requirement 20.1**: ResourceQuota objects created for each namespace
- **Requirement 20.2**: ResourceQuota limits CPU, memory, and storage
- **Requirement 20.3**: LimitRange objects set default resource limits
- **Requirement 20.4**: System prevents new pod creation when limits exceeded
- **Requirement 20.5**: Resource configuration tunable per environment
- **Requirement 21.1**: Multiple replicas for stateless applications in prod
- **Requirement 21.2**: PodDisruptionBudgets ensure minimum availability
- **Requirement 21.3**: HorizontalPodAutoscaler configured for auto-scaling
- **Requirement 21.4**: StatefulSet resources use persistent volumes
- **Requirement 21.5**: Rolling update strategy with configurable parameters

## Next Steps

To fully utilize these features:

1. **Enable metrics-server** (required for HPA):
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

2. **Monitor HPA behavior**:
   ```bash
   kubectl get hpa -n ttrpg-prod --watch
   ```

3. **Test rolling updates**:
   ```bash
   helm upgrade ttrpg charts/ttrpg-umbrella \
     --values values-prod.yaml \
     --set go-auth.image.tag=v1.2.3
   ```

4. **Verify PDB during node drain**:
   ```bash
   kubectl drain <node-name> --ignore-daemonsets
   kubectl get pods -n ttrpg-prod --watch
   ```

## Files Modified

### New Templates Created
- `charts/ttrpg-umbrella/templates/resourcequota.yaml`
- `charts/ttrpg-umbrella/templates/limitrange.yaml`
- `charts/shared/templates/_deploymentstrategy.tpl`
- `charts/shared/templates/_poddisruptionbudget.tpl`
- `charts/shared/templates/_horizontalpodautoscaler.tpl`

### Application Chart Templates Added
For each application (go-auth, go-sprint, py-dnd, ui-dnd, ui-sprint-management):
- `templates/poddisruptionbudget.yaml`
- `templates/horizontalpodautoscaler.yaml`

### Application Chart Deployments Updated
For each application:
- `templates/deployment.yaml` - Added rolling update strategy

### Values Files Updated
For each application chart:
- `values.yaml` - Added podDisruptionBudget and autoscaling sections

### Environment Values Updated
- `values-prod.yaml` - Enabled PDB and HPA for all applications
- `values-local.yaml` - Kept PDB and HPA disabled
- `values-dev.yaml` - (if exists) Configure as needed

## Summary Document
- `RESOURCE_MANAGEMENT_HA_SUMMARY.md` - This document
