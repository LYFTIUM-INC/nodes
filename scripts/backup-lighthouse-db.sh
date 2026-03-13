#!/bin/bash
# Lighthouse Database Backup Script
# Creates weekly backups of Lighthouse beacon chain database
# Usage: ./backup-lighthouse-db.sh [backup_dir]

set -euo pipefail

# Configuration
LIGHTHOUSE_DIR="/data/blockchain/nodes/consensus/lighthouse/beacon"
DEFAULT_BACKUP_DIR="/data/blockchain/nodes/consensus/lighthouse/backups"
BACKUP_DIR="${1:-$DEFAULT_BACKUP_DIR}"
MAX_BACKUPS=4  # Keep 4 weeks of backups
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Check if Lighthouse is running
if systemctl is-active --quiet lighthouse-beacon.service; then
    log_warn "Lighthouse service is running - creating hot backup"
    log_info "Note: For best results, stop service before backup"
else
    log_info "Lighthouse service is stopped - safe to backup"
fi

# Check database exists
if [[ ! -d "${LIGHTHOUSE_DIR}/chain_db" ]]; then
    log_error "Lighthouse database not found at ${LIGHTHOUSE_DIR}/chain_db"
    exit 1
fi

# Calculate database size
DB_SIZE=$(du -sh "${LIGHTHOUSE_DIR}" 2>/dev/null | awk '{print $1}')
log_info "Database size: ${DB_SIZE}"

# Create backup
BACKUP_NAME="lighthouse-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

log_info "Creating backup: ${BACKUP_NAME}"
log_info "Source: ${LIGHTHOUSE_DIR}"
log_info "Destination: ${BACKUP_PATH}"

# Use tar with compression for efficient storage
if tar -czf "${BACKUP_PATH}.tar.gz" \
    -C "${LIGHTHOUSE_DIR}" \
    --exclude='*.log' \
    --exclude='locks' \
    chain_db blobs_db freezer_db 2>/dev/null; then
    
    BACKUP_SIZE=$(du -sh "${BACKUP_PATH}.tar.gz" | awk '{print $1}')
    log_info "✅ Backup created successfully"
    log_info "Backup size: ${BACKUP_SIZE}"
    
    # Create metadata file
    cat > "${BACKUP_PATH}.meta" <<EOF
backup_timestamp=${TIMESTAMP}
backup_date=$(date)
database_size=${DB_SIZE}
backup_size=${BACKUP_SIZE}
lighthouse_version=$(lighthouse --version 2>&1 | head -1)
current_slot=$(curl -s http://localhost:5052/eth/v1/beacon/headers/head 2>/dev/null | jq -r '.data.header.message.slot' 2>/dev/null || echo "unknown")
service_status=$(systemctl is-active lighthouse-beacon.service 2>/dev/null || echo "unknown")
EOF
    
    log_info "Metadata saved to ${BACKUP_PATH}.meta"
else
    log_error "Backup failed"
    exit 1
fi

# Cleanup old backups
log_info "Cleaning up old backups (keeping last ${MAX_BACKUPS})"
cd "${BACKUP_DIR}"
ls -t lighthouse-backup-*.tar.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while read old_backup; do
    log_info "Removing old backup: ${old_backup}"
    rm -f "${old_backup}"
    rm -f "${old_backup%.tar.gz}.meta"
done

# List current backups
log_info "Current backups:"
ls -lh lighthouse-backup-*.tar.gz 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}' || log_info "  No backups found"

log_info "✅ Backup completed successfully"
exit 0
