#!/bin/bash
set -e

# Vault Restore Script
# This script restores a Vault Raft snapshot from an encrypted backup

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="${ENV:-local}"
BACKUP_FILE="${BACKUP_FILE:-}"
BACKUP_DIR="${BACKUP_DIR:-/vault-backups}"
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
FORCE="${FORCE:-false}"

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

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Restore Vault from an encrypted backup.

Options:
  -e, --env ENV              Environment (local, dev, prod) [default: local]
  -f, --file BACKUP_FILE     Path to backup tarball (required)
  -d, --backup-dir DIR       Backup directory [default: /vault-backups]
  -a, --vault-addr ADDR      Vault address [default: http://vault.vault.svc.cluster.local:8200]
  -t, --vault-token TOKEN    Vault token (required)
  --force                    Force restore without confirmation
  -h, --help                 Show this help message

Examples:
  $0 -e prod -f /vault-backups/vault-backup-prod-20260210_120000.tar.gz -t \$VAULT_TOKEN
  $0 --env dev --file backup.tar.gz --vault-token \$VAULT_TOKEN --force

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--env)
                ENV="$2"
                shift 2
                ;;
            -f|--file)
                BACKUP_FILE="$2"
                shift 2
                ;;
            -d|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -a|--vault-addr)
                VAULT_ADDR="$2"
                shift 2
                ;;
            -t|--vault-token)
                VAULT_TOKEN="$2"
                shift 2
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
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
        log_error "VAULT_TOKEN not provided. Use -t or --vault-token option."
        exit 1
    fi
    
    if [ -z "$BACKUP_FILE" ]; then
        log_error "BACKUP_FILE not provided. Use -f or --file option."
        exit 1
    fi
    
    if [ ! -f "$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Confirm restore operation
confirm_restore() {
    if [ "$FORCE" = "true" ]; then
        return 0
    fi
    
    log_warn "WARNING: This will restore Vault from backup and may overwrite existing data!"
    log_warn "Environment: $ENV"
    log_warn "Backup file: $BACKUP_FILE"
    log_warn "Vault address: $VAULT_ADDR"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi
}

# Extract backup tarball
extract_backup() {
    log_info "Extracting backup tarball..."
    
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    if tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"; then
        log_info "Backup extracted to: $TEMP_DIR"
        EXTRACT_DIR="$TEMP_DIR"
    else
        log_error "Failed to extract backup tarball"
        exit 1
    fi
    
    # Find the snapshot directory
    SNAPSHOT_DIR=$(find "$TEMP_DIR" -type d -name "[0-9]*_[0-9]*" | head -n1)
    
    if [ -z "$SNAPSHOT_DIR" ]; then
        log_error "Could not find snapshot directory in backup"
        exit 1
    fi
    
    log_info "Found snapshot directory: $SNAPSHOT_DIR"
}

# Decrypt snapshot
decrypt_snapshot() {
    log_info "Decrypting snapshot..."
    
    ENCRYPTED_FILE="${SNAPSHOT_DIR}/vault-snapshot.snap.gpg"
    DECRYPTED_FILE="${SNAPSHOT_DIR}/vault-snapshot.snap"
    
    if [ ! -f "$ENCRYPTED_FILE" ]; then
        log_error "Encrypted snapshot not found: $ENCRYPTED_FILE"
        exit 1
    fi
    
    if gpg --decrypt --output "$DECRYPTED_FILE" "$ENCRYPTED_FILE"; then
        log_info "Snapshot decrypted successfully"
    else
        log_error "Failed to decrypt snapshot. Check GPG keys."
        exit 1
    fi
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
        log_error "Vault is sealed. Please unseal Vault before restoring."
        exit 1
    fi
    
    log_info "Vault is accessible and unsealed"
}

# Restore snapshot
restore_snapshot() {
    log_info "Restoring Vault snapshot..."
    
    DECRYPTED_FILE="${SNAPSHOT_DIR}/vault-snapshot.snap"
    
    if [ ! -f "$DECRYPTED_FILE" ]; then
        log_error "Decrypted snapshot not found: $DECRYPTED_FILE"
        exit 1
    fi
    
    # Force restore to overwrite existing data
    if vault operator raft snapshot restore -force "$DECRYPTED_FILE"; then
        log_info "Snapshot restored successfully"
    else
        log_error "Failed to restore Vault snapshot"
        exit 1
    fi
}

# Verify restore
verify_restore() {
    log_info "Verifying restore..."
    
    # Wait for Vault to stabilize
    sleep 5
    
    if vault status &> /dev/null; then
        log_info "Vault is responding after restore"
    else
        log_warn "Vault may need to be restarted or unsealed"
    fi
    
    # Display metadata
    METADATA_FILE="${SNAPSHOT_DIR}/metadata.json"
    if [ -f "$METADATA_FILE" ]; then
        log_info "Backup metadata:"
        cat "$METADATA_FILE"
    fi
}

# Main execution
main() {
    log_info "Starting Vault restore for environment: $ENV"
    
    parse_args "$@"
    check_prerequisites
    confirm_restore
    extract_backup
    decrypt_snapshot
    check_vault_status
    restore_snapshot
    verify_restore
    
    log_info "Vault restore completed successfully"
    log_warn "Please verify Vault functionality and unseal if necessary"
}

# Run main function
main "$@"
