# Versioning and Release Management

This document explains the versioning strategy for the TTRPG Helm deployment.

## Overview

The TTRPG Helm chart supports flexible version management with multiple levels of precedence, allowing you to:
- Deploy all applications with a single version
- Override versions for specific applications
- Pin versions for production stability
- Use floating tags for development

## Version Types

### Chart Version
The Helm chart itself has its own version (defined in `Chart.yaml`):
- **Current version**: `0.1.0`
- **Purpose**: Tracks changes to chart templates, values schema, and dependencies
- **Versioning**: Follows semantic versioning (MAJOR.MINOR.PATCH)
  - **MAJOR**: Breaking changes to chart structure or values schema
  - **MINOR**: New features, new subcharts, backward-compatible changes
  - **PATCH**: Bug fixes, documentation updates

### Application Versions
Application container images have their own versions:
- **Format**: Semantic versioning (vX.Y.Z or X.Y.Z)
- **Special tags**: `latest`, `dev`, `staging`, `main`, `master`
- **Examples**: `v1.2.3`, `1.2.3`, `latest`, `dev`

## Version Precedence

When determining which image tag to use for an application, the system follows this precedence (highest to lowest):

1. **Command-line override**: `--set {app}.image.tag=vX.Y.Z`
2. **Application-specific version**: `{app}.version` in values file
3. **Global default version**: `global.version` in values file
4. **Fallback**: `"latest"`

### Examples

#### Example 1: Deploy all apps with v1.2.3
```bash
helm install ttrpg ./charts/ttrpg-umbrella \
  --set global.version=v1.2.3
```

All applications will use `v1.2.3`.

#### Example 2: Deploy go-auth with v1.3.0, others with v1.2.3
```bash
helm install ttrpg ./charts/ttrpg-umbrella \
  --set global.version=v1.2.3 \
  --set go-auth.version=v1.3.0
```

- `go-auth` will use `v1.3.0`
- All other apps will use `v1.2.3`

#### Example 3: Override at deploy time
```bash
helm install ttrpg ./charts/ttrpg-umbrella \
  -f values-prod.yaml \
  --set go-auth.image.tag=v1.3.1
```

- `go-auth` will use `v1.3.1` (highest precedence)
- Other apps will use the version from `values-prod.yaml` (typically pinned)

#### Example 4: Mixed versions in values file
```yaml
# values-custom.yaml
global:
  version: "v1.2.3"

go-auth:
  version: "v1.3.0"  # Override for this app

go-sprint:
  version: ""  # Uses global.version (v1.2.3)

py-dnd:
  image:
    tag: "v1.1.0"  # Highest precedence for this app
```

```bash
helm install ttrpg ./charts/ttrpg-umbrella -f values-custom.yaml
```

Result:
- `go-auth`: `v1.3.0` (application-specific version)
- `go-sprint`: `v1.2.3` (global version)
- `py-dnd`: `v1.1.0` (image tag override)
- `ui-dnd`: `v1.2.3` (global version)
- `ui-sprint-management`: `v1.2.3` (global version)

## Environment-Specific Strategies

### Local Development (`values-local.yaml`)
```yaml
global:
  version: "latest"
```

**Strategy**: Use `latest` tag for automatic updates during development.

**Benefits**:
- Always get the newest code
- No need to specify versions
- Fast iteration

**Drawbacks**:
- Less reproducible
- May pull breaking changes

### Development Environment (`values-dev.yaml`)
```yaml
global:
  version: "dev"
```

**Strategy**: Use `dev` tag or floating tags for testing.

**Benefits**:
- Test latest changes before production
- Can override with specific versions for testing
- Flexible for experimentation

**Use cases**:
- Integration testing
- QA validation
- Staging deployments

### Production Environment (`values-prod.yaml`)
```yaml
global:
  version: "v1.0.0"
```

**Strategy**: Always use pinned semantic versions.

**Benefits**:
- Reproducible deployments
- Controlled rollouts
- Easy rollbacks
- Audit trail

**Best practices**:
- Never use `latest` in production
- Always use semantic versions (e.g., `v1.2.3`)
- Update version explicitly for each release
- Test in dev before promoting to prod

## Semantic Versioning

All application versions must follow semantic versioning format:

### Valid Formats
- `vX.Y.Z` (e.g., `v1.2.3`) - preferred
- `X.Y.Z` (e.g., `1.2.3`)
- `vX.Y.Z-prerelease` (e.g., `v1.2.3-beta.1`)
- `vX.Y.Z+metadata` (e.g., `v1.2.3+20240209`)
- Special tags: `latest`, `dev`, `staging`, `main`, `master`

### Invalid Formats
- `v1.2` (missing patch version)
- `1` (missing minor and patch)
- `release-1.2.3` (invalid prefix)
- `1.2.3.4` (too many version parts)

### Validation

The chart automatically validates all version values at deployment time. If an invalid version is detected, the deployment will fail with a clear error message:

```
Error: Invalid version format: v1.2. Must be semantic version (vX.Y.Z or X.Y.Z) or special tag (latest, dev, staging)
```

## Deployment Workflows

### Deploying a New Release

1. **Build and tag images**:
   ```bash
   docker build -t ghcr.io/your-org/go-auth:v1.2.3 ./go_auth
   docker push ghcr.io/your-org/go-auth:v1.2.3
   ```

2. **Update values file** (for prod):
   ```yaml
   # values-prod.yaml
   global:
     version: "v1.2.3"
   ```

3. **Deploy**:
   ```bash
   helm upgrade ttrpg ./charts/ttrpg-umbrella \
     -f values-prod.yaml \
     --namespace ttrpg-prod
   ```

### Rolling Back

```bash
# Rollback to previous release
helm rollback ttrpg --namespace ttrpg-prod

# Or deploy specific version
helm upgrade ttrpg ./charts/ttrpg-umbrella \
  -f values-prod.yaml \
  --set global.version=v1.2.2 \
  --namespace ttrpg-prod
```

### Canary Deployment

Deploy new version to a subset of applications:

```bash
helm upgrade ttrpg ./charts/ttrpg-umbrella \
  -f values-prod.yaml \
  --set global.version=v1.2.2 \
  --set go-auth.version=v1.2.3 \
  --namespace ttrpg-prod
```

Monitor `go-auth` with the new version. If successful, promote to all apps:

```bash
helm upgrade ttrpg ./charts/ttrpg-umbrella \
  -f values-prod.yaml \
  --set global.version=v1.2.3 \
  --namespace ttrpg-prod
```

### Blue-Green Deployment

1. Deploy new version to separate namespace:
   ```bash
   helm install ttrpg-green ./charts/ttrpg-umbrella \
     -f values-prod.yaml \
     --set global.version=v1.2.3 \
     --set environment=prod-green \
     --namespace ttrpg-prod-green
   ```

2. Test the green environment

3. Switch traffic (update ingress or load balancer)

4. Remove blue environment:
   ```bash
   helm uninstall ttrpg --namespace ttrpg-prod
   ```

## Best Practices

### For Development
- Use `latest` or `dev` tags for rapid iteration
- Use `IfNotPresent` pull policy to avoid unnecessary pulls
- Override versions at command-line for testing specific versions

### For Production
- Always use pinned semantic versions
- Use `Always` pull policy to ensure correct image
- Update versions explicitly in values files
- Test in dev environment before promoting to prod
- Maintain a changelog of version updates
- Use Git tags to track chart and application versions together

### For CI/CD
- Build images with semantic version tags
- Tag images with both version and `latest`/`dev`
- Use `--set global.version=$CI_COMMIT_TAG` in pipelines
- Validate versions before deployment
- Store deployment manifests for audit trail

### Version Management
- Keep chart version separate from application versions
- Increment chart version when changing templates
- Use application versions for code changes
- Document breaking changes in chart CHANGELOG
- Use pre-release versions for testing (e.g., `v1.2.3-beta.1`)

## Troubleshooting

### Wrong Image Version Deployed

**Problem**: Application is using unexpected image version.

**Solution**: Check version precedence:
1. Check if `image.tag` is set (highest precedence)
2. Check if application-specific `version` is set
3. Check `global.version`
4. Default is `latest`

Use `helm get values` to see actual values:
```bash
helm get values ttrpg --namespace ttrpg-prod
```

### Version Validation Fails

**Problem**: Deployment fails with "Invalid version format" error.

**Solution**: Ensure version follows semantic versioning:
- Use `vX.Y.Z` or `X.Y.Z` format
- Or use special tags: `latest`, `dev`, `staging`

### Image Pull Errors

**Problem**: Kubernetes cannot pull image with specified version.

**Solution**:
1. Verify image exists in registry:
   ```bash
   docker pull ghcr.io/your-org/go-auth:v1.2.3
   ```
2. Check image pull secrets are configured
3. Verify version tag matches exactly (case-sensitive)

### Inconsistent Versions Across Apps

**Problem**: Different applications running different versions unintentionally.

**Solution**:
1. Use `global.version` for coordinated releases
2. Only set application-specific versions when intentional
3. Use `helm get values` to audit current versions
4. Clear any `image.tag` overrides in values files

## References

- [Semantic Versioning](https://semver.org/)
- [Helm Values Files](https://helm.sh/docs/chart_template_guide/values_files/)
- [Kubernetes Image Pull Policy](https://kubernetes.io/docs/concepts/containers/images/#image-pull-policy)
