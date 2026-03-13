#!/bin/bash
# MEV Foundation Backup Manager
# Enterprise-grade backup and recovery procedures

set -euo pipefail

# Configuration
BACKUP_DIR="/data/blockchain/backups"
RETENTION_DAYS=30
MAX_BACKUPS=10
COMPRESSION_LEVEL=6
HEALTH_CHECK_TIMEOUT=300

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${2}$1${NC}$3"
}

error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}" >&2
}

# Validate backup directory
validate_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log "Creating backup directory: $BACKUP_DIR"
        sudo mkdir -p "$BACKUP_DIR"
    fi
    
    if [ ! -w "$BACKUP_DIR" ]; then
        error "Backup directory is not writable: $BACKUP_DIR"
    fi
    success "Backup directory validated: $BACKUP_DIR"
}

# Check disk space
check_disk_space() {
    local required_space=$1
    local available_space=$(df "$BACKUP_DIR" | awk 'NR==1 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [ $available_gb -lt $required_space ]; then
        warning "Low disk space: ${available_gb}GB available, ${required_space}GB required"
        return 1
    fi
    
    success "Sufficient disk space: ${available_gb}GB available"
    return 0
}

# Create backup
create_backup() {
    local backup_name=$1
    local service=$2
    local backup_type=$3
    local source_path=$4
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/${backup_name}_${timestamp}_${backup_type}.tar.gz"
    
    log "Creating backup: $backup_file"
    
    case $backup_type in
        "config")
            tar -czf "$backup_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
            ;;
        "data")
            tar -czf "$backup_file" -C "$(dirname "$source_path")" "$(basename "$source_path")" --exclude="*.tmp"
            ;;
        "logs")
            tar -czf "$backup_file" -C "$(dirname "$source_path")" "$(basename "$source_path")" --exclude="*.log"
            ;;
        "full")
            tar -czf "$backup_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
            ;;
        *)
            tar -czf "$backup_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "Backup created: $backup_file"
        log "Backup size: $(du -h "$backup_file" | cut -f1)"
        return 0
    else
        error "Failed to create backup: $backup_file"
        return 1
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file=$1
    local backup_type=$2
    
    log "Verifying backup integrity: $backup_file"
    
    case $backup_type in
        "config"|"data"|"logs")
            if [ -f "$backup_file" ]; then
                tar -tzf "$backup_file" --list --exclude="*"
                success "Backup integrity verified: $backup_file"
                return 0
            fi
            ;;
        *)
            if [ -f "$backup_file" ]; then
                tar -tf "$backup_file" --list > /dev/null 2>/dev/null
                success "Backup integrity verified: $backup_file"
                return 0
            fi
            ;;
    esac
    
    error "Backup verification failed: $backup_file"
    return 1
}

# List available backups
list_backups() {
    log "Available backups:"
    ls -la "$BACKUP_DIR"/*.tar.gz" | tail -10
}

# Restore from backup
restore_backup() {
    local backup_file=$1
    local target_path=$2
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    log "Restoring from: $backup_file"
    
    case $backup_file in
        *"config"*)
            tar -xzf "$backup_file" -C /
            ;;
        *"data"*)
            tar -xzf "$backup_file" -C /
            ;;
        *)
            tar -xzf "$backup_file" -C /
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "Backup restored successfully"
        log "Restored to: $(tar -tf "$backup_file" | head -1 | cut -d/ -f1)"
        return 0
    else
        error "Failed to restore backup: $backup_file"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups (older than $RETENTION_DAYS days)..."
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete -print
    log "Old backups cleaned up"
}

# Automated backup scheduling
schedule_backups() {
    log "Setting up automated backups..."
    
    # Add to crontab (daily at 2 AM)
    (crontab -l | echo "0 2 * * * /data/blockchain/nodes/maintenance/create-backup.sh >> /var/log/cron.log) 2>/dev/null || true
    
    # Add to crontab (weekly on Sunday at 3 AM for full backup)
    (crontab -l | echo "0 3 * * * /data/blockchain/nodes/maintenance/create-backup.sh >> /var/log/cron.log) 2>/dev/null || true)
    
    # Add log rotation (daily at midnight)
    (crontab -l | echo "0 0 * * * /data/blockchain/nodes/maintenance/rotate-logs.sh >> /var/log/cron.log) 2>/dev/null || true)
    
    success "Automated backups scheduled"
    log "Cron jobs updated"
}

# Main backup function
main() {
    case "${1:-start}" in
        "validate")
            validate_backup_dir
            check_disk_space 50
            ;;
        "create")
            create_backup "$2" "$3" "$4"
            verify_backup "$2" "$3"
            ;;
        "restore")
            restore_backup "$2" "$3"
            ;;
        "list")
            list_backups
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "schedule")
            schedule_backups
            ;;
        *)
            echo "Usage: $0 {validate|create|restore|list|cleanup|schedule} [backup_name] [service_type] [source_path]"
            echo "Example: $0 create reth-data config /etc/reth /configs/reth"
            echo "Example: $0 create mev-stack monitoring /data/mev /configs/mev"
            echo "Example: $0 restore reth-data /data/reth /configs/reth"
            ;;
    esac
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
