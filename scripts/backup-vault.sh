#!/bin/bash
set -e

# Vault Backup Script
# This script creates a Raft snapshot of Vault, encrypts it with GPG, and stores it to a PVC

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="${ENV:-local}"
BACKUP_DIR="${BACKUP_DIR:-/vault-backups}"
GPG_RECIPIENT="${GPG_RECIPIENT:-vault-backup@ttrpg.local}"
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v vault &> /dev/null; then
        log_error "vault CLI not found. Please install Vault CLI."
        exit 1
    fi
    
    if ! command -v gpg &> /dev/null; then
        log_error "gpg not found. Please install GPG."
        exit 1
    fi
    
    if [ -z "$VAULT_TOKEN" ]; then
        log_error "VAULT_TOKEN environment variable not set."
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Check Vault status
check_vault_status() {
    log_info "Checking Vault status..."
    
    export VAULT_ADDR
    export VAULT_TOKEN
    
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        exit 1
    fi
    
    if vault status | grep -q "Sealed.*true"; then
        log_error "Vault is sealed. Please unseal Vault before backing up."
        exit 1
    fi
    
    log_info "Vault is accessible and unsealed"
}

# Create backup directory
create_backup_dir() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="${BACKUP_DIR}/${ENV}/${TIMESTAMP}"
    
    log_info "Creating backup directory: $BACKUP_PATH"
    mkdir -p "$BACKUP_PATH"
}

# Create Raft snapshot
create_snapshot() {
    log_info "Creating Vault Raft snapshot..."
    
    SNAPSHOT_FILE="${BACKUP_PATH}/vault-snapshot.snap"
    
    if vault operator raft snapshot save "$SNAPSHOT_FILE"; then
        log_info "Snapshot created successfully: $SNAPSHOT_FILE"
    else
        log_error "Failed to create Vault snapshot"
        exit 1
    fi
}

# Encrypt snapshot
encrypt_snapshot() {
    log_info "Encrypting snapshot with GPG..."
    
    SNAPSHOT_FILE="${BACKUP_PATH}/vault-snapshot.snap"
    ENCRYPTED_FILE="${BACKUP_PATH}/vault-snapshot.snap.gpg"
    
    if gpg --encrypt --recipient "$GPG_RECIPIENT" --output "$ENCRYPTED_FILE" "$SNAPSHOT_FILE"; then
        log_info "Snapshot encrypted successfully: $ENCRYPTED_FILE"
        # Remove unencrypted snapshot
        rm -f "$SNAPSHOT_FILE"
    else
        log_error "Failed to encrypt snapshot"
        exit 1
    fi
}

# Create metadata file
create_metadata() {
    log_info "Creating backup metadata..."
    
    METADATA_FILE="${BACKUP_PATH}/metadata.json"
    
    cat > "$METADATA_FILE" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "environment": "${ENV}",
  "vault_address": "${VAULT_ADDR}",
  "backup_type": "raft_snapshot",
  "encrypted": true,
  "gpg_recipient": "${GPG_RECIPIENT}",
  "vault_version": "$(vault version | head -n1)"
}
EOF
    
    log_info "Metadata created: $METADATA_FILE"
}

# Create tarball
create_tarball() {
    log_info "Creating backup tarball..."
    
    TARBALL_NAME="vault-backup-${ENV}-${TIMESTAMP}.tar.gz"
    TARBALL_PATH="${BACKUP_DIR}/${TARBALL_NAME}"
    
    tar -czf "$TARBALL_PATH" -C "${BACKUP_DIR}/${ENV}" "$TIMESTAMP"
    
    if [ $? -eq 0 ]; then
        log_info "Tarball created: $TARBALL_PATH"
        # Remove temporary directory
        rm -rf "${BACKUP_PATH}"
    else
        log_error "Failed to create tarball"
        exit 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    RETENTION_DAYS="${RETENTION_DAYS:-30}"
    
    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."
    
    find "${BACKUP_DIR}" -name "vault-backup-${ENV}-*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete
    
    log_info "Cleanup completed"
}

# Main execution
main() {
    log_info "Starting Vault backup for environment: $ENV"
    
    check_prerequisites
    check_vault_status
    create_backup_dir
    create_snapshot
    encrypt_snapshot
    create_metadata
    create_tarball
    cleanup_old_backups
    
    log_info "Vault backup completed successfully"
    log_info "Backup file: ${BACKUP_DIR}/vault-backup-${ENV}-${TIMESTAMP}.tar.gz"
}

# Run main function
main "$@"
