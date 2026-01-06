#!/bin/bash
# Automated Disk Cleanup for Blockchain Nodes
# Prevents disk space issues and maintains optimal performance

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/disk-cleaner.log"
DISK_THRESHOLD=85
AGGRESSIVE_THRESHOLD=90

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Function to get disk usage percentage
get_disk_usage() {
    df -h /data | tail -1 | awk '{print $5}' | sed 's/%//'
}

# Function to clean Docker artifacts
clean_docker() {
    log "Cleaning Docker artifacts..."
    
    # Remove stopped containers
    local stopped_containers=$(docker ps -aq --filter "status=exited" 2>/dev/null || true)
    if [ -n "$stopped_containers" ]; then
        log "Removing stopped containers: $stopped_containers"
        docker rm $stopped_containers
    fi
    
    # Remove dangling images
    local dangling_images=$(docker images -f "dangling=true" -q 2>/dev/null || true)
    if [ -n "$dangling_images" ]; then
        log "Removing dangling images: $dangling_images"
        docker rmi $dangling_images
    fi
    
    # Clean build cache
    docker builder prune -f >/dev/null 2>&1 || true
    
    # Clean system (but keep volumes)
    docker system prune -f >/dev/null 2>&1 || true
    
    log "Docker cleanup completed"
}

# Function to clean logs
clean_logs() {
    log "Cleaning system and application logs..."
    
    # Clean Docker logs older than 7 days
    find /var/lib/docker/containers/ -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    # Clean systemd journal logs older than 30 days
    journalctl --vacuum-time=30d >/dev/null 2>&1 || true
    
    # Clean monitoring logs older than 30 days
    find "${SCRIPT_DIR}" -name "*.log" -mtime +30 -delete 2>/dev/null || true
    
    # Clean temporary files
    find /tmp -type f -mtime +7 -delete 2>/dev/null || true
    
    log "Log cleanup completed"
}

# Function to clean blockchain data (conservative)
clean_blockchain_data() {
    local usage=$1
    log "Cleaning blockchain data - disk usage: ${usage}%"
    
    # Only clean if we have aggressive threshold
    if [ "$usage" -ge "$AGGRESSIVE_THRESHOLD" ]; then
        log "Aggressive cleanup mode activated"
        
        # Clean Ethereum ancient chain data if using Geth
        if docker ps --format "{{.Names}}" | grep -q "ethereum-light"; then
            log "Cleaning Ethereum ancient chain data..."
            docker exec ethereum-light geth removedb --datadir /root/.ethereum || true
        fi
        
        # Clean Solana snapshots older than 7 days
        if [ -d "/data/blockchain/storage/solana/snapshots" ]; then
            log "Cleaning old Solana snapshots..."
            find /data/blockchain/storage/solana/snapshots -name "*.tar.*" -mtime +7 -delete 2>/dev/null || true
        fi
    fi
}

# Function to prune Ethereum data
prune_ethereum() {
    log "Checking if Ethereum node needs pruning..."
    
    if docker ps --format "{{.Names}}" | grep -q "ethereum-light"; then
        # Check if node is synced before pruning
        local sync_status=$(docker exec ethereum-light geth attach --exec "eth.syncing" ipc:/root/.ethereum/geth.ipc 2>/dev/null || echo "false")
        
        if [ "$sync_status" = "false" ]; then
            log "Ethereum node is synced, safe to prune"
            # Snapshot prune (safer than full state prune)
            docker exec ethereum-light geth snapshot prune-state --datadir /root/.ethereum || log "Pruning failed or not needed"
        else
            log "Ethereum node still syncing, skipping pruning"
        fi
    fi
}

# Function to optimize Solana ledger
optimize_solana() {
    log "Optimizing Solana ledger..."
    
    if docker ps --format "{{.Names}}" | grep -q "solana-dev"; then
        # Clean old snapshots and optimize accounts DB
        docker exec solana-dev solana-validator cleanup --ledger /data 2>/dev/null || log "Solana cleanup not needed"
    fi
}

# Main cleanup function
main() {
    log "=== Starting disk cleanup process ==="
    
    local initial_usage=$(get_disk_usage)
    log "Initial disk usage: ${initial_usage}%"
    
    if [ "$initial_usage" -lt "$DISK_THRESHOLD" ]; then
        log "Disk usage below threshold (${DISK_THRESHOLD}%), no cleanup needed"
        return 0
    fi
    
    log "Disk usage above threshold, starting cleanup..."
    
    # Step 1: Clean Docker artifacts (safest)
    clean_docker
    local usage_after_docker=$(get_disk_usage)
    log "Disk usage after Docker cleanup: ${usage_after_docker}%"
    
    # Step 2: Clean logs
    if [ "$usage_after_docker" -ge "$DISK_THRESHOLD" ]; then
        clean_logs
        local usage_after_logs=$(get_disk_usage)
        log "Disk usage after log cleanup: ${usage_after_logs}%"
    fi
    
    # Step 3: Optimize blockchain data
    if [ "$usage_after_logs" -ge "$DISK_THRESHOLD" ]; then
        optimize_solana
        prune_ethereum
        local usage_after_blockchain=$(get_disk_usage)
        log "Disk usage after blockchain optimization: ${usage_after_blockchain}%"
    fi
    
    # Step 4: Aggressive cleanup if still needed
    if [ "$usage_after_blockchain" -ge "$AGGRESSIVE_THRESHOLD" ]; then
        log "WARNING: Disk usage still critical, performing aggressive cleanup"
        clean_blockchain_data "$usage_after_blockchain"
    fi
    
    local final_usage=$(get_disk_usage)
    local space_freed=$((initial_usage - final_usage))
    
    log "=== Cleanup completed ==="
    log "Initial: ${initial_usage}% | Final: ${final_usage}% | Freed: ${space_freed}%"
    
    # Alert if still critical
    if [ "$final_usage" -ge "$AGGRESSIVE_THRESHOLD" ]; then
        log "ALERT: Disk usage still critical after cleanup: ${final_usage}%"
        # Could send notification here
        echo "CRITICAL: Disk space cleanup insufficient - manual intervention required" >&2
        return 1
    fi
}

# Run cleanup
main "$@"