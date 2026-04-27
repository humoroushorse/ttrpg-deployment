-- PostgreSQL Database Initialization Script
-- This script creates databases and the Vault admin user
-- It is mounted as a ConfigMap and executed automatically by PostgreSQL on first startup

-- Create databases for each application
CREATE DATABASE auth;
CREATE DATABASE sprint_management;
CREATE DATABASE dnd;
CREATE DATABASE keycloak;

-- Create Vault admin user with superuser privileges
-- This user will be used by Vault to create dynamic database credentials
-- The password will be rotated automatically by Vault when rotate_root_credentials is enabled
CREATE USER vault_admin WITH SUPERUSER CREATEDB CREATEROLE REPLICATION;

-- Grant all privileges on databases to vault_admin
GRANT ALL PRIVILEGES ON DATABASE auth TO vault_admin;
GRANT ALL PRIVILEGES ON DATABASE sprint_management TO vault_admin;
GRANT ALL PRIVILEGES ON DATABASE dnd TO vault_admin;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO vault_admin;

-- Connect to each database and enable necessary extensions
\c auth
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

\c sprint_management
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

\c dnd
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

\c keycloak
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Return to postgres database
\c postgres

-- Log completion
SELECT 'Database initialization completed successfully' AS status;
