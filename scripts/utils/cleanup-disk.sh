#!/bin/bash
# Disk Cleanup Script for Blockchain Infrastructure
# Automatically manages disk space by cleaning logs, temporary files, and optimizing storage

set -euo pipefail

# Configuration
LOG_FILE="/data/blockchain/nodes/logs/disk-cleanup.log"
DISK_WARNING_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=90
LOG_RETENTION_DAYS=30
BACKUP_RETENTION_DAYS=7
TEMP_FILE_AGE_HOURS=24

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Get disk usage for a path
get_disk_usage() {
    local path=$1
    df "$path" | tail -1 | awk '{print $5}' | sed 's/%//'
}

# Get disk usage in human readable format
get_disk_info() {
    local path=$1
    df -h "$path" | tail -1 | awk '{print $2, $3, $4, $5}'
}

# Clean old log files
clean_logs() {
    local retention_days=${1:-$LOG_RETENTION_DAYS}
    local cleaned_size=0
    
    log "INFO" "Cleaning log files older than $retention_days days"
    
    # Blockchain node logs
    local log_dirs=(
        "/data/blockchain/nodes/logs"
        "/var/log/docker"
        "/var/log/syslog*"
        "/data/blockchain/storage/*/logs"
    )
    
    for log_pattern in "${log_dirs[@]}"; do
        if compgen -G "$log_pattern" > /dev/null; then
            for log_dir in $log_pattern; do
                if [ -d "$log_dir" ]; then
                    log "INFO" "Cleaning logs in $log_dir"
                    
                    # Find and remove old log files
                    find "$log_dir" -name "*.log" -type f -mtime +$retention_days -print0 | while IFS= read -r -d '' file; do
                        local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                        rm -f "$file" && cleaned_size=$((cleaned_size + size))
                        log "DEBUG" "Removed old log file: $file"
                    done
                    
                    # Compress recent log files
                    find "$log_dir" -name "*.log" -type f -mtime +1 -mtime -$retention_days -print0 | while IFS= read -r -d '' file; do
                        if [[ ! "$file" == *.gz ]]; then
                            gzip "$file" && log "DEBUG" "Compressed log file: $file"
                        fi
                    done
                fi
            done
        fi
    done
    
    # Docker logs cleanup
    docker system prune -f --volumes 2>/dev/null || log "WARN" "Could not prune Docker system"
    
    # Rotate large log files
    find /data/blockchain/nodes/logs -name "*.log" -size +100M -exec sh -c '
        for file; do
            mv "$file" "${file}.old"
            touch "$file"
            chmod 644 "$file"
            echo "Rotated large log file: $file"
        done
    ' sh {} +
    
    log "INFO" "Log cleanup completed"
}

# Clean temporary files
clean_temp_files() {
    local age_hours=${1:-$TEMP_FILE_AGE_HOURS}
    
    log "INFO" "Cleaning temporary files older than $age_hours hours"
    
    # System temp directories
    local temp_dirs=(
        "/tmp"
        "/var/tmp"
        "/data/blockchain/nodes/tmp"
        "/data/blockchain/storage/*/tmp"
    )
    
    for temp_pattern in "${temp_dirs[@]}"; do
        if compgen -G "$temp_pattern" > /dev/null; then
            for temp_dir in $temp_pattern; do
                if [ -d "$temp_dir" ]; then
                    find "$temp_dir" -type f -amin +$((age_hours * 60)) -delete 2>/dev/null || true
                    find "$temp_dir" -type d -empty -delete 2>/dev/null || true
                fi
            done
        fi
    done
    
    # Docker temporary files
    docker container prune -f 2>/dev/null || true
    docker image prune -f 2>/dev/null || true
    
    # Node-specific temp files
    find /data/blockchain/storage -name "*.tmp" -type f -mmin +$((age_hours * 60)) -delete 2>/dev/null || true
    find /data/blockchain/storage -name "*.lock" -type f -mmin +$((age_hours * 60)) -delete 2>/dev/null || true
    
    log "INFO" "Temporary files cleanup completed"
}

# Clean old backups
clean_backups() {
    local retention_days=${1:-$BACKUP_RETENTION_DAYS}
    
    log "INFO" "Cleaning backup files older than $retention_days days"
    
    local backup_dirs=(
        "/data/blockchain/nodes/monitoring/backups"
        "/data/blockchain/backups"
        "/backup"
    )
    
    for backup_dir in "${backup_dirs[@]}"; do
        if [ -d "$backup_dir" ]; then
            find "$backup_dir" -name "*.tar.gz" -type f -mtime +$retention_days -delete 2>/dev/null || true
            find "$backup_dir" -name "*.zip" -type f -mtime +$retention_days -delete 2>/dev/null || true
            find "$backup_dir" -name "*.sql" -type f -mtime +$retention_days -delete 2>/dev/null || true
            log "INFO" "Cleaned backups in $backup_dir"
        fi
    done
    
    log "INFO" "Backup cleanup completed"
}

# Optimize blockchain data
optimize_blockchain_data() {
    log "INFO" "Optimizing blockchain data storage"
    
    # Ethereum data optimization
    local eth_data="/data/blockchain/storage/ethereum"
    if [ -d "$eth_data" ]; then
        # Remove ancient chain data if available
        find "$eth_data" -name "ancient" -type d | while read -r ancient_dir; do
            if [ -d "$ancient_dir" ]; then
                local size_before=$(du -sb "$ancient_dir" | cut -f1)
                # Keep only recent ancient data (if supported by client)
                find "$ancient_dir" -name "*.dat" -mtime +90 -delete 2>/dev/null || true
                local size_after=$(du -sb "$ancient_dir" | cut -f1)
                local saved=$((size_before - size_after))
                log "INFO" "Optimized ancient data: saved $((saved / 1024 / 1024))MB"
            fi
        done
    fi
    
    # Solana data optimization
    local solana_data="/data/blockchain/storage/solana"
    if [ -d "$solana_data" ]; then
        # Remove old ledger data
        find "$solana_data" -name "rocksdb" -type d | while read -r db_dir; do
            if [ -d "$db_dir" ]; then
                # Compact RocksDB if tools available
                if command -v ldb >/dev/null 2>&1; then
                    ldb compact --db="$db_dir" 2>/dev/null || true
                    log "INFO" "Compacted RocksDB: $db_dir"
                fi
            fi
        done
    fi
    
    # General optimizations
    local storage_dirs=(/data/blockchain/storage/*)
    for storage_dir in "${storage_dirs[@]}"; do
        if [ -d "$storage_dir" ]; then
            # Remove core dumps
            find "$storage_dir" -name "core.*" -type f -delete 2>/dev/null || true
            
            # Remove old debug files
            find "$storage_dir" -name "*.debug" -type f -mtime +7 -delete 2>/dev/null || true
            
            # Remove old state snapshots
            find "$storage_dir" -name "*snapshot*" -type f -mtime +30 -delete 2>/dev/null || true
        fi
    done
    
    log "INFO" "Blockchain data optimization completed"
}

# Compress old data
compress_old_data() {
    local compress_age_days=${1:-7}
    
    log "INFO" "Compressing data older than $compress_age_days days"
    
    # Compress old monitoring data
    find /data/blockchain/nodes/monitoring -name "*.db" -type f -mtime +$compress_age_days | while read -r db_file; do
        if [[ ! "$db_file" == *.gz ]]; then
            gzip "$db_file" && log "INFO" "Compressed database: $db_file"
        fi
    done
    
    # Compress old exports
    find /data/blockchain -name "*.json" -size +10M -mtime +$compress_age_days | while read -r json_file; do
        if [[ ! "$json_file" == *.gz ]]; then
            gzip "$json_file" && log "INFO" "Compressed large JSON: $json_file"
        fi
    done
    
    log "INFO" "Data compression completed"
}

# Check and alert on disk usage
check_disk_usage() {
    local path=${1:-"/data"}
    local usage=$(get_disk_usage "$path")
    local disk_info=($(get_disk_info "$path"))
    
    log "INFO" "Disk usage for $path: ${usage}% (${disk_info[1]}/${disk_info[0]} used, ${disk_info[2]} free)"
    
    if [ "$usage" -ge "$DISK_CRITICAL_THRESHOLD" ]; then
        log "ERROR" "CRITICAL: Disk usage ${usage}% exceeds critical threshold ${DISK_CRITICAL_THRESHOLD}%"
        send_notification "critical" "Disk usage critical: ${usage}%"
        return 2
    elif [ "$usage" -ge "$DISK_WARNING_THRESHOLD" ]; then
        log "WARN" "WARNING: Disk usage ${usage}% exceeds warning threshold ${DISK_WARNING_THRESHOLD}%"
        send_notification "warning" "Disk usage high: ${usage}%"
        return 1
    else
        log "INFO" "Disk usage within normal range: ${usage}%"
        return 0
    fi
}

# Emergency cleanup
emergency_cleanup() {
    log "WARN" "EMERGENCY: Performing aggressive disk cleanup"
    
    # Aggressive log cleanup
    clean_logs 7
    
    # Remove all temporary files
    clean_temp_files 1
    
    # Aggressive backup cleanup  
    clean_backups 3
    
    # Clean Docker aggressively
    docker system prune -af --volumes 2>/dev/null || true
    
    # Remove old container logs
    find /var/lib/docker/containers -name "*.log" -mtime +1 -delete 2>/dev/null || true
    
    # Clean package caches
    apt-get clean 2>/dev/null || true
    yum clean all 2>/dev/null || true
    
    # Remove old kernels (if safe)
    if command -v package-cleanup >/dev/null 2>&1; then
        package-cleanup --oldkernels --count=1 -y 2>/dev/null || true
    fi
    
    log "WARN" "Emergency cleanup completed"
}

# Generate disk usage report
generate_disk_report() {
    local report_file="/data/blockchain/nodes/logs/disk-usage-report.txt"
    
    {
        echo "=== Disk Usage Report ==="
        echo "Generated: $(date)"
        echo ""
        
        echo "Overall Disk Usage:"
        df -h
        echo ""
        
        echo "Largest Directories in /data:"
        du -h /data/* 2>/dev/null | sort -hr | head -20
        echo ""
        
        echo "Blockchain Storage Usage:"
        if [ -d "/data/blockchain/storage" ]; then
            du -h /data/blockchain/storage/* 2>/dev/null | sort -hr
        fi
        echo ""
        
        echo "Log Directory Usage:"
        if [ -d "/data/blockchain/nodes/logs" ]; then
            du -h /data/blockchain/nodes/logs/* 2>/dev/null | sort -hr
        fi
        echo ""
        
        echo "Docker Space Usage:"
        docker system df 2>/dev/null || echo "Docker not available"
        echo ""
        
        echo "Cleanup Thresholds:"
        echo "Warning Threshold: ${DISK_WARNING_THRESHOLD}%"
        echo "Critical Threshold: ${DISK_CRITICAL_THRESHOLD}%"
        echo "Log Retention: ${LOG_RETENTION_DAYS} days"
        echo "Backup Retention: ${BACKUP_RETENTION_DAYS} days"
        
    } > "$report_file"
    
    log "INFO" "Disk usage report generated: $report_file"
}

# Send notification
send_notification() {
    local severity=$1
    local message=$2
    
    # Send to monitoring system
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys
sys.path.append('/data/blockchain/nodes/monitoring')
from alert_system import AlertManager, Alert
from datetime import datetime

alert_manager = AlertManager()
alert = Alert(
    id='disk_cleanup_$(date +%s)',
    severity='$severity',
    source='disk_cleanup',
    message='$message',
    timestamp=datetime.now()
)
alert_manager.process_alerts([alert])
" 2>/dev/null || log "WARN" "Could not send notification to monitoring system"
    fi
    
    # Log to alerts file
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DISK-CLEANUP] $message" >> "/data/blockchain/nodes/logs/alerts.log"
}

# Monitor and cleanup based on usage
monitor_and_cleanup() {
    local disk_path=${1:-"/data"}
    
    check_disk_usage "$disk_path"
    local usage_status=$?
    
    case $usage_status in
        0)
            # Normal usage - routine cleanup
            clean_temp_files
            clean_logs
            ;;
        1)
            # Warning level - moderate cleanup
            log "WARN" "Disk usage high, performing cleanup"
            clean_temp_files 12
            clean_logs $((LOG_RETENTION_DAYS / 2))
            clean_backups
            compress_old_data
            optimize_blockchain_data
            ;;
        2)
            # Critical level - aggressive cleanup
            log "ERROR" "Disk usage critical, performing emergency cleanup"
            emergency_cleanup
            ;;
    esac
    
    # Check usage after cleanup
    local usage_after=$(get_disk_usage "$disk_path")
    log "INFO" "Disk usage after cleanup: ${usage_after}%"
    
    if [ "$usage_after" -lt "$usage" ]; then
        local saved=$((usage - usage_after))
        send_notification "info" "Disk cleanup completed, freed ${saved}% space"
    fi
}

# Main execution
main() {
    local action="${1:-monitor}"
    local target="${2:-/data}"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "INFO" "Disk cleanup script started. Action: $action, Target: $target"
    
    case "$action" in
        "monitor")
            monitor_and_cleanup "$target"
            ;;
        "clean-logs")
            clean_logs
            send_notification "info" "Log cleanup completed"
            ;;
        "clean-temp")
            clean_temp_files
            send_notification "info" "Temporary files cleanup completed"
            ;;
        "clean-backups")
            clean_backups
            send_notification "info" "Backup cleanup completed"
            ;;
        "optimize")
            optimize_blockchain_data
            compress_old_data
            send_notification "info" "Data optimization completed"
            ;;
        "emergency")
            emergency_cleanup
            send_notification "warning" "Emergency disk cleanup completed"
            ;;
        "report")
            generate_disk_report
            send_notification "info" "Disk usage report generated"
            ;;
        "check")
            check_disk_usage "$target"
            ;;
        *)
            echo "Usage: $0 [action] [target_path]"
            echo "Actions:"
            echo "  monitor     - Monitor disk usage and cleanup as needed (default)"
            echo "  clean-logs  - Clean old log files"
            echo "  clean-temp  - Clean temporary files"
            echo "  clean-backups - Clean old backup files"
            echo "  optimize    - Optimize blockchain data storage"
            echo "  emergency   - Emergency aggressive cleanup"
            echo "  report      - Generate disk usage report"
            echo "  check       - Check disk usage only"
            echo ""
            echo "Target path defaults to /data if not specified"
            exit 1
            ;;
    esac
    
    log "INFO" "Disk cleanup script completed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi