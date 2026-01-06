#!/bin/bash
# Auto-Recovery Script for Blockchain Nodes
# Designed to prevent MEV/Arbitrage operation disruptions

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/data/blockchain/nodes/logs/auto-recovery.log"
LOCK_FILE="/tmp/auto-recovery.lock"
CONFIG_FILE="/data/blockchain/nodes/config/recovery-config.json"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi
}

# Signal handlers
trap cleanup EXIT
trap 'error_exit "Interrupted by user"' INT TERM

# Check if script is already running
if [[ -f "$LOCK_FILE" ]]; then
    if kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
        log "Auto-recovery script already running (PID: $(cat "$LOCK_FILE"))"
        exit 0
    else
        log "Removing stale lock file"
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file
echo $$ > "$LOCK_FILE"

log "Starting auto-recovery process"

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Loading recovery configuration"
        # Source configuration variables from JSON
        eval "$(jq -r '.recovery_settings | to_entries[] | "export \(.key)=\(.value)"' "$CONFIG_FILE")"
    else
        log "Using default recovery configuration"
        # Default settings
        export MAX_RESTART_ATTEMPTS=3
        export RESTART_COOLDOWN=300
        export MAX_SYNC_LAG=50
        export MAX_RESPONSE_TIME=2000
        export MIN_PEERS=3
        export ENABLE_BACKUP_FALLBACK=true
        export ENABLE_RESOURCE_CLEANUP=true
    fi
}

# Check node health
check_node_health() {
    local chain="$1"
    local rpc_url="$2"
    local backup_url="$3"
    
    log "Checking health for $chain"
    
    # Test RPC connectivity
    local response_time
    response_time=$(curl -o /dev/null -s -w "%{time_total}" \
        --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$rpc_url" 2>/dev/null || echo "999")
    
    response_time=$(echo "$response_time * 1000" | bc | cut -d. -f1)
    
    if [[ "$response_time" -gt "$MAX_RESPONSE_TIME" ]]; then
        log "WARNING: $chain response time too high: ${response_time}ms"
        return 1
    fi
    
    # Get current block height
    local block_height
    block_height=$(curl -s --max-time 10 \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$rpc_url" | jq -r '.result // "0x0"' | xargs printf "%d\n" 2>/dev/null || echo "0")
    
    # Get latest block from backup
    local latest_block
    latest_block=$(curl -s --max-time 10 \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$backup_url" | jq -r '.result // "0x0"' | xargs printf "%d\n" 2>/dev/null || echo "0")
    
    local blocks_behind=$((latest_block - block_height))
    
    if [[ "$blocks_behind" -gt "$MAX_SYNC_LAG" ]]; then
        log "WARNING: $chain is $blocks_behind blocks behind"
        return 1
    fi
    
    # Check peer count
    local peer_count
    peer_count=$(curl -s --max-time 10 \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        "$rpc_url" | jq -r '.result // "0x0"' | xargs printf "%d\n" 2>/dev/null || echo "0")
    
    if [[ "$peer_count" -lt "$MIN_PEERS" ]]; then
        log "WARNING: $chain has only $peer_count peers"
        return 1
    fi
    
    log "SUCCESS: $chain health check passed (${response_time}ms, ${blocks_behind} blocks behind, ${peer_count} peers)"
    return 0
}

# Restart service with backoff
restart_service() {
    local service_name="$1"
    local attempt_file="/tmp/restart_attempts_${service_name}"
    
    # Check restart attempts
    local attempts=0
    if [[ -f "$attempt_file" ]]; then
        attempts=$(cat "$attempt_file")
    fi
    
    if [[ "$attempts" -ge "$MAX_RESTART_ATTEMPTS" ]]; then
        log "ERROR: Max restart attempts reached for $service_name"
        return 1
    fi
    
    # Check last restart time
    local last_restart_file="/tmp/last_restart_${service_name}"
    if [[ -f "$last_restart_file" ]]; then
        local last_restart=$(cat "$last_restart_file")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_restart))
        
        if [[ "$time_diff" -lt "$RESTART_COOLDOWN" ]]; then
            log "WARNING: Restart cooldown active for $service_name (${time_diff}s ago)"
            return 1
        fi
    fi
    
    log "Restarting service: $service_name (attempt $((attempts + 1)))"
    
    # Stop service gracefully
    if systemctl is-active --quiet "$service_name"; then
        sudo systemctl stop "$service_name"
        sleep 10
    fi
    
    # Kill any remaining processes
    case "$service_name" in
        "ethereum")
            sudo pkill -f "erigon" || true
            ;;
        "optimism")
            sudo pkill -f "op-geth" || true
            ;;
        "avalanchego")
            sudo pkill -f "avalanchego" || true
            ;;
    esac
    
    sleep 5
    
    # Start service
    if sudo systemctl start "$service_name"; then
        log "SUCCESS: $service_name restarted successfully"
        echo "$((attempts + 1))" > "$attempt_file"
        date +%s > "$last_restart_file"
        return 0
    else
        log "ERROR: Failed to restart $service_name"
        return 1
    fi
}

# Clean up system resources
cleanup_resources() {
    if [[ "$ENABLE_RESOURCE_CLEANUP" != "true" ]]; then
        return 0
    fi
    
    log "Performing resource cleanup"
    
    # Check memory usage
    local memory_usage
    memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    
    if [[ "$memory_usage" -gt 85 ]]; then
        log "High memory usage detected: ${memory_usage}%"
        
        # Drop caches
        sudo sync
        sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
        log "Dropped system caches"
    fi
    
    # Check disk usage
    local disk_usage
    disk_usage=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [[ "$disk_usage" -gt 85 ]]; then
        log "High disk usage detected: ${disk_usage}%"
        
        # Clean up old logs
        find /data/blockchain/nodes/logs -name "*.log" -mtime +7 -delete 2>/dev/null || true
        find /var/log -name "*.log.*.gz" -mtime +7 -delete 2>/dev/null || true
        
        log "Cleaned up old log files"
    fi
    
    # Check for zombie processes
    local zombie_count
    zombie_count=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')
    
    if [[ "$zombie_count" -gt 0 ]]; then
        log "Found $zombie_count zombie processes"
        # Parent processes of zombies will be cleaned up by systemd
    fi
}

# Enable backup endpoints
enable_backup_endpoint() {
    local chain="$1"
    local backup_url="$2"
    
    if [[ "$ENABLE_BACKUP_FALLBACK" != "true" ]]; then
        return 0
    fi
    
    log "Enabling backup endpoint for $chain"
    
    # Update backup endpoints configuration
    local backup_config="/data/blockchain/nodes/config/backup_endpoints.json"
    
    if [[ ! -f "$backup_config" ]]; then
        echo '{}' > "$backup_config"
    fi
    
    # Update configuration
    jq --arg chain "$chain" --arg url "$backup_url" --arg timestamp "$(date -Iseconds)" \
        '.[$chain] = {
            "backup_endpoint": $url,
            "enabled_at": $timestamp,
            "reason": "Auto-recovery fallback"
        }' "$backup_config" > "${backup_config}.tmp" && mv "${backup_config}.tmp" "$backup_config"
    
    log "Backup endpoint enabled for $chain: $backup_url"
}

# Check and fix port conflicts
fix_port_conflicts() {
    log "Checking for port conflicts"
    
    # Common blockchain ports
    local ports=(8545 8546 8547 8555 8556 8557 9650 30303 30304 30308)
    
    for port in "${ports[@]}"; do
        local pid
        pid=$(lsof -ti tcp:"$port" 2>/dev/null | head -1 || echo "")
        
        if [[ -n "$pid" ]]; then
            local process_name
            process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            
            # Check if it's a Docker container
            if [[ "$process_name" == "docker-proxy" ]]; then
                local container_id
                container_id=$(docker ps -q --filter "publish=$port" 2>/dev/null | head -1)
                
                if [[ -n "$container_id" ]]; then
                    local container_name
                    container_name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^.//')
                    
                    log "WARNING: Docker container $container_name is using port $port"
                    
                    # Stop conflicting containers
                    if [[ "$container_name" =~ (old|backup|test) ]]; then
                        log "Stopping conflicting container: $container_name"
                        docker stop "$container_id" 2>/dev/null || true
                    fi
                fi
            fi
        fi
    done
}

# Main recovery function
perform_recovery() {
    local chain="$1"
    local rpc_url="$2"
    local backup_url="$3"
    local service_name="$4"
    
    log "Starting recovery for $chain"
    
    # Check if service is running
    if ! systemctl is-active --quiet "$service_name"; then
        log "Service $service_name is not running, attempting to start"
        if ! sudo systemctl start "$service_name"; then
            log "Failed to start $service_name, attempting restart"
            restart_service "$service_name"
        fi
        sleep 30  # Wait for service to initialize
    fi
    
    # Check node health
    if ! check_node_health "$chain" "$rpc_url" "$backup_url"; then
        log "$chain health check failed, initiating recovery"
        
        # Fix port conflicts first
        fix_port_conflicts
        
        # Attempt service restart
        if restart_service "$service_name"; then
            sleep 60  # Wait for service to stabilize
            
            # Recheck health
            if check_node_health "$chain" "$rpc_url" "$backup_url"; then
                log "SUCCESS: $chain recovered after restart"
                return 0
            fi
        fi
        
        # If restart failed, enable backup endpoint
        log "Local node recovery failed, enabling backup endpoint"
        enable_backup_endpoint "$chain" "$backup_url"
    else
        log "$chain is healthy"
    fi
}

# Main execution
main() {
    load_config
    
    # System resource cleanup
    cleanup_resources
    
    # Define node configurations
    declare -A nodes=(
        ["ethereum"]="http://localhost:8545|https://ethereum-rpc.publicnode.com|ethereum"
        ["optimism"]="http://localhost:8546|https://optimism-rpc.publicnode.com|optimism"  
        ["arbitrum"]="http://localhost:8547|https://arbitrum-rpc.publicnode.com|arbitrum"
        ["avalanche"]="http://localhost:9650/ext/bc/C/rpc|https://avalanche-c-chain-rpc.publicnode.com|avalanchego"
    )
    
    # Process each node
    for chain in "${!nodes[@]}"; do
        IFS='|' read -r rpc_url backup_url service_name <<< "${nodes[$chain]}"
        perform_recovery "$chain" "$rpc_url" "$backup_url" "$service_name"
    done
    
    # Generate status report
    cat << EOF > "/data/blockchain/nodes/status/auto-recovery-report.json"
{
    "timestamp": "$(date -Iseconds)",
    "recovery_run": true,
    "nodes_checked": $(echo "${!nodes[@]}" | wc -w),
    "log_file": "$LOG_FILE",
    "next_run": "$(date -d '+30 minutes' -Iseconds)"
}
EOF
    
    log "Auto-recovery cycle completed"
}

# Execute main function
main "$@"