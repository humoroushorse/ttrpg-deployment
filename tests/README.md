# Deployment Tests

This directory contains property-based tests for the TTRPG deployment system.

## Overview

Property-based tests validate universal correctness properties that should hold across all valid executions of the deployment system. Each test runs a minimum of 100 iterations to ensure comprehensive coverage through randomization.

## Test Files

### test_vault_config.sh

Tests for Vault configuration correctness properties:

- **Property 1: Cluster-Internal DNS Usage** - Validates that Vault database configuration uses cluster-internal DNS names (*.svc.cluster.local) rather than localhost or external addresses
- **Property 2: Dynamic Credential Generation** - Validates that Vault can generate valid database credentials for all configured roles

### test_migration_jobs.sh

Tests for database migration job correctness properties:

- **Property 3: Migration Precedes Application** - Validates that migration jobs complete successfully before application pods transition to Ready state
- **Property 4: Failed Migrations Block Deployment** - Validates that failed migration jobs prevent application pods from reaching Running state
- **Property 5: Successful Migrations Enable Deployment** - Validates that successful migration jobs allow application pods to reach Ready state

### test_deployment_automation.sh

Tests for deployment automation correctness properties:

- **Property 6: Clean Teardown** - Validates that after teardown phase completes, no pods or resources from the previous deployment remain in the cluster
- **Property 7: Infrastructure Deployment Ordering** - Validates that PostgreSQL reaches Ready state before Vault, and Vault reaches Ready state before application services

## Running Tests

### Prerequisites

- Kubernetes cluster with Vault deployed
- kubectl configured to access the cluster
- vault-init-keys.json file in the deployment directory
- jq installed for JSON parsing

### Run All Tests

```bash
cd ttrpg-deployment

# Run Vault configuration tests
./tests/test_vault_config.sh [ENV]

# Run migration job tests
./tests/test_migration_jobs.sh [ENV]

# Run deployment automation tests
./tests/test_deployment_automation.sh [ENV]

# Or use Makefile targets
make test-vault-properties ENV=local
make test-migration-properties ENV=local
make test-deployment-properties ENV=local
```

Where `ENV` is one of: local, dev, prod (default: local)

### Example

```bash
# Run tests for local environment
./tests/test_vault_config.sh local

# Run tests for production environment
./tests/test_vault_config.sh prod
```

## Test Output

Tests provide colored output:
- 🟡 Yellow: Informational messages
- 🟢 Green: Passed tests
- 🔴 Red: Failed tests

Each test reports:
- Number of iterations run
- Number of failures
- Specific failure details

## Exit Codes

- 0: All tests passed
- 1: One or more tests failed

## Integration with CI/CD

These tests can be integrated into deployment pipelines:

```bash
# In Makefile or CI script
make deploy-local
./tests/test_vault_config.sh local || exit 1
```

## Adding New Tests

To add a new property test:

1. Create a new test function following the naming pattern `test_<property_name>`
2. Implement the property check with MIN_ITERATIONS loops
3. Use the helper functions: `run_test`, `pass_test`, `fail_test`
4. Add the test to the `main()` function
5. Document the property in this README

## Property Test Guidelines

- Each test should validate a universal property (holds for all valid inputs)
- Run at least MIN_ITERATIONS (100) iterations per test
- Use randomization where appropriate to explore the input space
- Clean up resources created during testing (e.g., revoke Vault leases)
- Provide clear failure messages with counterexamples
