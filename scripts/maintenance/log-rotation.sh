#!/bin/bash
# MEV Foundation Log Rotation Script
# Manages log files for all services with automated cleanup

set -e

# Configuration
LOG_DIR="/data/blockchain/nodes/logs"
CONFIG_DIR="/data/blockchain/nodes/configs"
BACKUP_DIR="/data/blockchain/nodes/backups/logs"
RETENTION_DAYS=30
MAX_LOG_SIZE="100M"

# Service log configurations
declare -A SERVICES=(
    ["reth"]="/data/blockchain/storage/reth/logs"
    ["lighthouse"]="/data/blockchain/storage/lighthouse/logs"
    ["mev-boost"]="/data/blockchain/nodes/logs/mev-boost"
    ["rbuilder"]="/data/blockchain/nodes/logs/rbuilder"
    ["docker"]="/data/blockchain/nodes/logs/docker"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize directories
mkdir -p "$LOG_DIR" "$BACKUP_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_DIR/log-rotation.log"
}

rotate_service_logs() {
    local service=$1
    local service_dir=${SERVICES[$service]}
    
    if [ ! -d "$service_dir" ]; then
        log "${YELLOW}⚠️  No log directory for $service: $service_dir${NC}"
        return 0
    fi
    
    log "🔄 Rotating logs for $service..."
    
    # Find and rotate large log files
    find "$service_dir" -name "*.log" -type f -size +"$MAX_LOG_SIZE" | while read -r logfile; do
        if [ -f "$logfile" ]; then
            # Create backup
            local timestamp=$(date '+%Y%m%d-%H%M%S')
            local basename=$(basename "$logfile" .log)
            local backup_file="$BACKUP_DIR/${basename}-${timestamp}.log.gz"
            
            # Compress and move
            gzip -c "$logfile" > "$backup_file"
            
            # Truncate original log file
            > "$logfile"
            
            log "${GREEN}✅ Rotated: $(basename "$logfile") -> $(basename "$backup_file")${NC}"
        fi
    done
    
    # Remove old log files
    find "$BACKUP_DIR" -name "${service}-*.log.gz" -type f -mtime +$RETENTION_DAYS -delete
    log "${BLUE}🗑️  Cleaned old logs for $service (older than $RETENTION_DAYS days)${NC}"
}

rotate_docker_logs() {
    log "🔄 Rotating Docker container logs..."
    
    # Rotate RETH logs
    if docker ps --format "table {{.Names}}" | grep -q "reth-ethereum-mev"; then
        local reth_logs=$(docker inspect reth-ethereum-mev | jq -r '.[0].LogPath')
        if [ -f "$reth_logs" ] && [ $(stat -f%s "$reth_logs") -gt $((100 * 1024 * 1024)) ]; then
            docker restart reth-ethereum-mev
            log "${GREEN}✅ Restarted RETH to rotate logs${NC}"
        fi
    fi
    
    # Rotate Lighthouse logs
    if docker ps --format "table {{.Names}}" | grep -q "lighthouse-mev-foundation"; then
        local lighthouse_logs=$(docker inspect lighthouse-mev-foundation | jq -r '.[0].LogPath')
        if [ -f "$lighthouse_logs" ] && [ $(stat -f%s "$lighthouse_logs") -gt $((100 * 1024 * 1024)) ]; then
            docker restart lighthouse-mev-foundation
            log "${GREEN}✅ Restarted Lighthouse to rotate logs${NC}"
        fi
    fi
}

cleanup_temp_files() {
    log "🧹 Cleaning up temporary files..."
    
    # Clean Docker temp files
    docker system prune -f > /dev/null 2>&1
    log "${GREEN}✅ Cleaned Docker temporary files${NC}"
    
    # Clean system temp files
    find /tmp -name "*.tmp" -mtime +7 -delete 2>/dev/null || true
    find /var/tmp -name "*.tmp" -mtime +7 -delete 2>/dev/null || true
    log "${GREEN}✅ Cleaned system temporary files${NC}"
}

backup_configs() {
    log "💾 Backing up configurations..."
    
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    local config_backup="$BACKUP_DIR/configs-${timestamp}.tar.gz"
    
    if [ -d "$CONFIG_DIR" ]; then
        tar -czf "$config_backup" -C "$(dirname "$CONFIG_DIR") "$(basename "$CONFIG_DIR")"
        log "${GREEN}✅ Backed up configurations to: $(basename "$config_backup")${NC}"
    fi
}

check_disk_space() {
    log "📊 Checking disk space..."
    
    local available=$(df -h /data | tail -1 | awk '{print $4}')
    local used_percent=$(df -h /data | tail -1 | awk '{print $5}' | sed 's/%//')
    
    log "Available space: $available, Used: ${used_percent}%"
    
    if [ "${used_percent%?}" -gt 80 ]; then
        log "${RED}⚠️  High disk usage: ${used_percent}% used${NC}"
    fi
}

generate_log_report() {
    log "📋 Generating log rotation report..."
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file="$LOG_DIR/log-rotation-report-$(date '+%Y%m%d-%H%M%S').json"
    
    # Collect log statistics
    local total_logs=0
    local total_size=0
    
    for service in "${!SERVICES[@]}"; do
        local service_dir=${SERVICES[$service]}
        if [ -d "$service_dir" ]; then
            local count=$(find "$service_dir" -name "*.log" -type f | wc -l)
            local size=$(du -sb "$service_dir" 2>/dev/null | cut -f1 || echo 0)
            total_logs=$((total_logs + count))
            total_size=$((total_size + size))
        fi
    done
    
    # Generate JSON report
    jq -n \
      --arg timestamp "$timestamp" \
      --arg total_logs "$total_logs" \
      --arg total_size "$total_size" \
      --arg retention_days "$RETENTION_DAYS" \
      '{
        timestamp: $timestamp,
        summary: {
          total_logs: $total_logs,
          total_size_bytes: $total_size,
          total_size_mb: ($total_size / 1024 / 1024 | floor),
          retention_days: $retention_days
        },
        services: {}
      }' > "$report_file"
    
    log "${GREEN}📊 Log rotation report saved to: $(basename "$report_file")${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}🔄 MEV Foundation Log Rotation${NC}"
    echo -e "${BLUE}=========================${NC}"
    echo ""
    
    local start_time=$(date +%s)
    
    # Pre-rotation checks
    check_disk_space
    
    # Rotate logs for each service
    for service in "${!SERVICES[@]}"; do
        rotate_service_logs "$service"
    done
    
    # Rotate Docker logs
    rotate_docker_logs
    
    # Cleanup operations
    cleanup_temp_files
    
    # Backup configurations
    backup_configs
    
    # Generate report
    generate_log_report
    
    # Post-rotation checks
    check_disk_space
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo -e "${GREEN}✅ Log rotation completed in ${duration}s${NC}"
    log "Log rotation completed successfully in ${duration} seconds"
}

# Handle command line arguments
case "${1:-full}" in
    "reth")
        rotate_service_logs "reth"
        ;;
    "lighthouse")
        rotate_service_logs "lighthouse"
        ;;
    "mev-boost")
        rotate_service_logs "mev-boost"
        ;;
    "rbuilder")
        rotate_service_logs "rbuilder"
        ;;
    "docker")
        rotate_docker_logs
        ;;
    "cleanup")
        cleanup_temp_files
        ;;
    "configs")
        backup_configs
        ;;
    "report")
        generate_log_report
        ;;
    "full"|*)
        main
        ;;
esac
