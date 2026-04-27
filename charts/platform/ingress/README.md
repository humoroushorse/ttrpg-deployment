# Ingress Chart

This chart deploys the nginx-ingress controller with path-based routing and Keycloak integration for the TTRPG application suite.

## Features

- **Nginx Ingress Controller**: Full deployment with admission webhooks
- **Path-Based Routing**: Routes traffic to different services based on URL path
- **Keycloak Integration**: Realm-specific authentication for different projects
- **TLS Support**: Automatic certificate management via cert-manager
- **Environment-Specific Configuration**: Different settings for local, dev, and prod

## Architecture

### Routing Rules

The ingress implements the following routing:

| Path | Service | Port | Realm |
|------|---------|------|-------|
| `/ttrpg/auth/*` | go-auth | 8081 | - |
| `/ttrpg/dnd/api/v1/*` | py-dnd | 8001 | dnd |
| `/ttrpg/dnd/*` | ui-dnd | 4200 | dnd |
| `/ttrpg/sprint-management/api/v1/*` | go-sprint | 8003 | sprint-management |
| `/ttrpg/sprint-management/*` | ui-sprint-management | 4204 | sprint-management |

### Keycloak Authentication

When enabled (dev/prod), the ingress validates tokens with Keycloak:

- **D&D paths** use the `dnd` realm
- **Sprint Management paths** use the `sprint-management` realm
- **Auth paths** bypass authentication (used for login)

The realm is set per-path using nginx configuration snippets:
```yaml
nginx.ingress.kubernetes.io/configuration-snippet: |
  set $realm "dnd";
```

## Configuration

### Environment-Specific Settings

**Local**:
- Service Type: LoadBalancer (direct access)
- TLS: Disabled
- Keycloak Auth: Disabled
- Replicas: 1

**Dev**:
- Service Type: ClusterIP (Cloudflare Tunnel origin)
- TLS: Enabled (Let's Encrypt Staging)
- Keycloak Auth: Enabled
- Replicas: 2

**Prod**:
- Service Type: ClusterIP (Cloudflare Tunnel origin)
- TLS: Enabled (Let's Encrypt Production)
- Keycloak Auth: Enabled
- Replicas: 3

### Values

Key configuration values:

```yaml
ingress:
  enabled: true
  className: "nginx"
  
  controller:
    enabled: true
    replicaCount: 1
    service:
      type: LoadBalancer
      ports:
        http: 80
        https: 443
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
  
  tls:
    enabled: false
    secretName: "ttrpg-tls"
  
  keycloak:
    enabled: false

routes:
  auth:
    enabled: true
    path: "/ttrpg/auth"
    service: "go-auth"
    port: 8081
  
  dndApi:
    enabled: true
    path: "/ttrpg/dnd/api/v1"
    service: "py-dnd"
    port: 8001
    realm: "dnd"
  
  # ... other routes
```

## Components

### Ingress Controller

The chart deploys a full nginx-ingress controller with:

- **Deployment**: Controller pods with health checks
- **Service**: LoadBalancer or ClusterIP based on environment
- **ConfigMap**: Controller configuration
- **RBAC**: ServiceAccount, ClusterRole, ClusterRoleBinding, Role, RoleBinding
- **IngressClass**: Defines the "nginx" ingress class

### Admission Webhooks

Validates Ingress resources before creation:

- **ValidatingWebhookConfiguration**: Webhook registration
- **Jobs**: Create and patch webhook certificates
- **Service**: Webhook endpoint
- **RBAC**: Permissions for webhook operations

### Ingress Resources

Three Ingress resources for different authentication requirements:

1. **ttrpg-ingress**: Main ingress without authentication (local)
2. **ttrpg-ingress-dnd**: D&D paths with dnd realm authentication
3. **ttrpg-ingress-sprint**: Sprint paths with sprint-management realm authentication

## Usage

### Local Development

```bash
# Deploy with local values
helm install ttrpg charts/ttrpg-umbrella -f charts/ttrpg-umbrella/values-local.yaml

# Access services
curl http://localhost:8080/ttrpg/auth/health
curl http://localhost:8080/ttrpg/dnd/
curl http://localhost:8080/ttrpg/sprint-management/
```

### Dev/Prod Deployment

```bash
# Deploy to dev
helm install ttrpg charts/ttrpg-umbrella -f charts/ttrpg-umbrella/values-dev.yaml

# Deploy to prod
helm install ttrpg charts/ttrpg-umbrella -f charts/ttrpg-umbrella/values-prod.yaml
```

### Testing Routing

```bash
# Test auth service
curl http://localhost:8080/ttrpg/auth/health

# Test D&D API
curl http://localhost:8080/ttrpg/dnd/api/v1/characters

# Test D&D UI
curl http://localhost:8080/ttrpg/dnd/

# Test Sprint API
curl http://localhost:8080/ttrpg/sprint-management/api/v1/projects

# Test Sprint UI
curl http://localhost:8080/ttrpg/sprint-management/
```

### Verifying Keycloak Integration

When Keycloak authentication is enabled:

```bash
# Without token - should return 401
curl http://dev.mysite.com/ttrpg/dnd/api/v1/characters

# With valid token
curl -H "Authorization: Bearer $TOKEN" http://dev.mysite.com/ttrpg/dnd/api/v1/characters
```

## Troubleshooting

### Ingress Controller Not Starting

Check controller logs:
```bash
kubectl logs -n ttrpg-local deployment/ingress-nginx-controller
```

Common issues:
- Webhook certificate not created (check job logs)
- Port conflicts (check if port 80/443 already in use)
- RBAC permissions (check ClusterRole/RoleBinding)

### 404 Errors

Check ingress configuration:
```bash
kubectl get ingress -n ttrpg-local
kubectl describe ingress ttrpg-ingress -n ttrpg-local
```

Verify service endpoints:
```bash
kubectl get endpoints -n ttrpg-local
```

### Path Rewriting Issues

Check nginx logs:
```bash
kubectl logs -n ttrpg-local deployment/ingress-nginx-controller | grep "rewrite"
```

Verify rewrite annotation is applied:
```bash
kubectl get ingress ttrpg-ingress -n ttrpg-local -o yaml | grep rewrite
```

### Keycloak Authentication Failures

Check auth-url annotation:
```bash
kubectl get ingress ttrpg-ingress-dnd -n ttrpg-dev -o yaml | grep auth-url
```

Verify Keycloak is accessible:
```bash
kubectl exec -n ttrpg-dev deployment/ingress-nginx-controller -- curl http://keycloak.ttrpg-dev.svc.cluster.local:8080/realms/dnd
```

## Security

### TLS Configuration

TLS is managed by cert-manager:

```yaml
tls:
  enabled: true
  secretName: "ttrpg-tls"
```

The certificate is automatically provisioned based on the issuer:
- Local: Self-signed
- Dev: Let's Encrypt Staging
- Prod: Let's Encrypt Production

### Security Context

The controller runs with restricted security context:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 101
  fsGroup: 101
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE
  seccompProfile:
    type: RuntimeDefault
```

### Network Policies

When network policies are enabled, the ingress controller can:
- Accept traffic from external sources (LoadBalancer/Cloudflare)
- Forward traffic to application services
- Access Keycloak for authentication

## Monitoring

### Metrics

The ingress controller exposes Prometheus metrics on port 10254:

```bash
kubectl port-forward -n ttrpg-local deployment/ingress-nginx-controller 10254:10254
curl http://localhost:10254/metrics
```

### Health Checks

Health endpoints:
- Liveness: `http://localhost:10254/healthz`
- Readiness: `http://localhost:10254/healthz`

### Logs

View controller logs:
```bash
kubectl logs -n ttrpg-local deployment/ingress-nginx-controller -f
```

Log format includes:
- Request path
- Response status
- Upstream service
- Response time
- Request ID

## Requirements Validation

This chart implements the following requirements:

- **9.1**: Single Ingress resource routes all traffic by project path prefix
- **9.2**: Routes `/ttrpg/dnd` to ui-dnd and py-dnd API
- **9.3**: Routes `/ttrpg/sprint-management` to ui-sprint-management and go-sprint API
- **9.4**: Routes API requests to `/ttrpg/{project}/api/v1/*` to backend services
- **9.5**: Routes UI requests to `/ttrpg/{project}/*` to frontend services
- **9.6**: Integrates with Keycloak for token validation at ingress level
- **9.7**: Uses appropriate Keycloak realm for each project path
- **9.8**: Routes `/ttrpg/auth/*` to go-auth service
- **9.9**: Network policies restrict pod-to-pod communication (when enabled)
- **9.10**: Uses path-based routing with localhost for local environment
- **9.11**: Supports TLS termination with self-signed certificates for local

## References

- [Nginx Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Keycloak Integration Guide](https://www.keycloak.org/docs/latest/securing_apps/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
