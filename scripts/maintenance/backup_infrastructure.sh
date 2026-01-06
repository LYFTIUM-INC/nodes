#!/bin/bash
# MEV Foundation Infrastructure Backup Script
# Comprehensive backup solution for critical infrastructure components

set -euo pipefail

# Configuration
INFRASTRUCTURE_ROOT="/data/blockchain/nodes"
BACKUP_ROOT="/data/blockchain/backups"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
BACKUP_DIR="$BACKUP_ROOT/infrastructure_backup_$TIMESTAMP"
RETENTION_DAYS=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Backup functions
backup_configurations() {
    log "Creating configuration backup..."
    
    mkdir -p "$BACKUP_DIR/configs"
    
    # Backup JWT secrets
    if [ -d "$INFRASTRUCTURE_ROOT/configs/jwt" ]; then
        cp -r "$INFRASTRUCTURE_ROOT/configs/jwt" "$BACKUP_DIR/configs/"
        log "✅ JWT configurations backed up"
    fi
    
    # Backup MEV configurations
    if [ -d "$INFRASTRUCTURE_ROOT/configs/mev" ]; then
        cp -r "$INFRASTRUCTURE_ROOT/configs/mev" "$BACKUP_DIR/configs/"
        log "✅ MEV configurations backed up"
    fi
    
    # Backup systemd services
    if [ -d "$INFRASTRUCTURE_ROOT/configs/systemd" ]; then
        cp -r "$INFRASTRUCTURE_ROOT/configs/systemd" "$BACKUP_DIR/configs/"
        log "✅ Systemd configurations backed up"
    fi
    
    # Backup security configurations
    if [ -d "$INFRASTRUCTURE_ROOT/configs/security" ]; then
        cp -r "$INFRASTRUCTURE_ROOT/configs/security" "$BACKUP_DIR/configs/"
        log "✅ Security configurations backed up"
    fi
}

backup_docker_compose() {
    log "Creating Docker compose backup..."
    
    mkdir -p "$BACKUP_DIR/docker"
    
    # Export Docker configurations
    if docker network ls | grep -q "mev_foundation_network"; then
        docker network inspect mev_foundation_network > "$BACKUP_DIR/docker/mev_foundation_network.json"
        log "✅ Docker network configuration exported"
    fi
    
    # Export container configurations
    for container in reth-ethereum-mev lighthouse-mev-foundation mev-boost-foundation rbuilder-foundation; do
        if docker ps -a --format "{{.Names}}" | grep -q "$container"; then
            docker inspect "$container" > "$BACKUP_DIR/docker/${container}_config.json"
            log "✅ Container configuration exported: $container"
        fi
    done
}

backup_scripts() {
    log "Creating scripts backup..."
    
    mkdir -p "$BACKUP_DIR/scripts"
    
    # Backup all scripts
    if [ -d "$INFRASTRUCTURE_ROOT/scripts" ]; then
        cp -r "$INFRASTRUCTURE_ROOT/scripts" "$BACKUP_DIR/"
        log "✅ Scripts directory backed up"
    fi
}

backup_documentation() {
    log "Creating documentation backup..."
    
    mkdir -p "$BACKUP_DIR/docs"
    
    # Backup documentation
    if [ -d "$INFRASTRUCTURE_ROOT/docs" ]; then
        cp -r "$INFRASTRUCTURE_ROOT/docs" "$BACKUP_DIR/docs/"
        log "✅ Documentation backed up"
    fi
    
    if [ -d "$INFRASTRUCTURE_ROOT/documentation" ]; then
        cp -r "$INFRASTRUCTURE_ROOT/documentation" "$BACKUP_DIR/docs/"
        log "✅ Additional documentation backed up"
    fi
}

create_backup_manifest() {
    log "Creating backup manifest..."
    
    cat > "$BACKUP_DIR/backup_manifest.txt" << MANIFEST
MEV Foundation Infrastructure Backup Manifest
========================================
Backup Date: $(date)
Backup Directory: $BACKUP_DIR
Infrastructure Root: $INFRASTRUCTURE_ROOT

Backup Contents:
$(du -sh "$BACKUP_DIR"/* | sort -hr)

Backup Verification:
- JWT secrets: $([ -d "$BACKUP_DIR/configs/jwt" ] && echo "✅ Present" || echo "❌ Missing")
- MEV configs: $([ -d "$BACKUP_DIR/configs/mev" ] && echo "✅ Present" || echo "❌ Missing")
- Systemd configs: $([ -d "$BACKUP_DIR/configs/systemd" ] && echo "✅ Present" || echo "❌ Missing")
- Scripts: $([ -d "$BACKUP_DIR/scripts" ] && echo "✅ Present" || echo "❌ Missing")
- Documentation: $([ -d "$BACKUP_DIR/docs" ] && echo "✅ Present" || echo "❌ Missing")
- Docker configs: $([ -d "$BACKUP_DIR/docker" ] && echo "✅ Present" || echo "❌ Missing")

Restore Instructions:
1. Stop all services: docker stop $(docker ps -q)
2. Extract backup: tar -xzf infrastructure_backup_$TIMESTAMP.tar.gz
3. Restore configurations: cp -r configs/* $INFRASTRUCTURE_ROOT/configs/
4. Restore scripts: cp -r scripts/* $INFRASTRUCTURE_ROOT/scripts/
5. Restart services: docker-compose up -d

Retention Policy:
- Backups older than $RETENTION_DAYS days will be automatically removed
- Keep at least 7 most recent backups
- Monitor disk space usage regularly
MANIFEST

    log "✅ Backup manifest created"
}

compress_backup() {
    log "Compressing backup archive..."
    
    cd "$BACKUP_ROOT"
    tar -czf "infrastructure_backup_$TIMESTAMP.tar.gz" "infrastructure_backup_$TIMESTAMP"
    
    # Verify compression
    if [ -f "infrastructure_backup_$TIMESTAMP.tar.gz" ]; then
        local size=$(du -h "infrastructure_backup_$TIMESTAMP.tar.gz" | cut -f1)
        log "✅ Backup compressed successfully (Size: $size)"
        
        # Remove uncompressed directory
        rm -rf "$BACKUP_DIR"
        
        # Create symlink to latest backup
        ln -sf "infrastructure_backup_$TIMESTAMP.tar.gz" "$BACKUP_ROOT/latest_backup.tar.gz"
        
        echo -e "${GREEN}✅ Backup completed: $BACKUP_ROOT/infrastructure_backup_$TIMESTAMP.tar.gz${NC}"
    else
        echo -e "${RED}❌ Backup compression failed${NC}"
        return 1
    fi
}

cleanup_old_backups() {
    log "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
    
    local deleted_count=0
    while IFS= read -r -d '' backup; do
        local backup_date=$(echo "$backup" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | head -1)
        
        if [ -n "$backup_date" ]; then
            local backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo "0")
            local current_timestamp=$(date +%s)
            local age_days=$(( (current_timestamp - backup_timestamp) / 86400 ))
            
            if [ "$age_days" -gt "$RETENTION_DAYS" ]; then
                rm -f "$backup"
                log "Removed old backup: $(basename "$backup") ($age_days days old)"
                ((deleted_count++))
            fi
        fi
    done < <(find "$BACKUP_ROOT" -name "infrastructure_backup_*.tar.gz" -type f -print0)
    
    if [ "$deleted_count" -gt 0 ]; then
        log "✅ Cleaned up $deleted_count old backup(s)"
    else
        log "✅ No old backups to clean up"
    fi
}

# Main backup function
main() {
    echo -e "${BLUE}=== MEV Foundation Infrastructure Backup ===${NC}"
    echo -e "${BLUE}Timestamp: $(date)${NC}"
    echo

    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    local backup_start=$(date +%s)
    local failed_operations=0

    log "Starting infrastructure backup process..."

    # Perform backup operations
    echo -e "\n${YELLOW}Step 1: Backing up configurations...${NC}"
    backup_configurations || ((failed_operations++))

    echo -e "\n${YELLOW}Step 2: Backing up Docker configurations...${NC}"
    backup_docker_compose || ((failed_operations++))

    echo -e "\n${YELLOW}Step 3: Backing up scripts...${NC}"
    backup_scripts || ((failed_operations++))

    echo -e "\n${YELLOW}Step 4: Backing up documentation...${NC}"
    backup_documentation || ((failed_operations++))

    echo -e "\n${YELLOW}Step 5: Creating backup manifest...${NC}"
    create_backup_manifest

    echo -e "\n${YELLOW}Step 6: Compressing backup...${NC}"
    compress_backup || ((failed_operations++))

    echo -e "\n${YELLOW}Step 7: Cleaning up old backups...${NC}"
    cleanup_old_backups

    # Summary
    local backup_end=$(date +%s)
    local backup_duration=$((backup_end - backup_start))

    echo -e "\n${BLUE}=== Backup Summary ===${NC}"
    echo -e "Backup Duration: ${backup_duration} seconds"
    echo -e "Backup Location: $BACKUP_ROOT/infrastructure_backup_$TIMESTAMP.tar.gz"
    echo -e "Failed Operations: $failed_operations"

    if [ "$failed_operations" -eq 0 ]; then
        echo -e "${GREEN}✅ Backup completed successfully!${NC}"
        log "SUCCESS: Infrastructure backup completed successfully"
        exit 0
    else
        echo -e "${RED}❌ Backup completed with $failed_operations error(s)!${NC}"
        log "ERROR: Infrastructure backup completed with $failed_operations errors"
        exit 1
    fi
}

# Script execution
main "$@"
