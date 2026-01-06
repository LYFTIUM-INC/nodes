#!/bin/bash
# Enterprise Blockchain Monitoring System
# World's Most Advanced Blockchain Data Lab

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/data/blockchain/nodes/data/logs/current"
LOG_FILE="${LOG_DIR}/blockchain-monitor.log"
METRICS_FILE="${LOG_DIR}/blockchain-metrics.json"
ALERT_THRESHOLD=300  # 5 minutes without progress

# Ensure log directory exists with proper permissions
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Chain configurations
declare -A CHAINS=(
    ["ethereum"]="8545"
    ["optimism"]="8546"
    ["arbitrum"]="8547"
    ["base"]="8548"
)

# Initialize metrics
declare -A LAST_BLOCKS
declare -A SYNC_SPEEDS
declare -A PEER_COUNTS

# Logging function
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# Get chain status
get_chain_status() {
    local chain=$1
    local port=${CHAINS[$chain]}
    
    # Get block number
    local block_response=$(curl -s -X POST http://127.0.0.1:$port \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)
    
    local block_hex=$(echo "$block_response" | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4)
    local block_num=0
    if [[ -n "$block_hex" ]]; then
        block_num=$((16#${block_hex#0x}))
    fi
    
    # Get sync status
    local sync_response=$(curl -s -X POST http://127.0.0.1:$port \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null)
    
    # Get peer count
    local peer_response=$(curl -s -X POST http://127.0.0.1:$port \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null)
    
    local peer_hex=$(echo "$peer_response" | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4)
    local peer_count=0
    if [[ -n "$peer_hex" ]]; then
        peer_count=$((16#${peer_hex#0x}))
    fi
    
    echo "$block_num|$sync_response|$peer_count"
}

# Calculate sync speed
calculate_sync_speed() {
    local chain=$1
    local current_block=$2
    local timestamp=$(date +%s)
    
    if [[ -n "${LAST_BLOCKS[$chain]}" ]]; then
        local last_block=${LAST_BLOCKS[$chain]%%|*}
        local last_timestamp=${LAST_BLOCKS[$chain]##*|}
        local time_diff=$((timestamp - last_timestamp))
        
        if [[ $time_diff -gt 0 ]]; then
            local block_diff=$((current_block - last_block))
            local speed=$((block_diff / time_diff))
            SYNC_SPEEDS[$chain]=$speed
        fi
    fi
    
    LAST_BLOCKS[$chain]="$current_block|$timestamp"
}

# Generate metrics JSON
generate_metrics() {
    local json="{"
    local first=true
    
    for chain in "${!CHAINS[@]}"; do
        [[ "$first" == true ]] && first=false || json+=","
        
        local current_block=${LAST_BLOCKS[$chain]%%|*}
        local sync_speed=${SYNC_SPEEDS[$chain]:-0}
        local peer_count=${PEER_COUNTS[$chain]:-0}
        
        json+="\"$chain\":{\"block\":$current_block,\"sync_speed\":$sync_speed,\"peers\":$peer_count}"
    done
    
    json+="}"
    echo "$json" > "$METRICS_FILE" 2>/dev/null || true
}

# Health check
health_check() {
    local chain=$1
    local current_block=$2
    local peer_count=$3
    local service_status=$4
    
    # Check if service is down
    if [[ "$service_status" != "active" ]]; then
        log "ERROR" "$chain service is not active! Status: $service_status"
        return 1
    fi
    
    # Check if stuck at block 0
    if [[ $current_block -eq 0 ]] && [[ "$service_status" == "active" ]]; then
        log "WARN" "$chain is active but stuck at block 0"
        return 1
    fi
    
    # Check peer connectivity
    if [[ $peer_count -eq 0 ]] && [[ "$service_status" == "active" ]]; then
        log "WARN" "$chain has no peers connected"
        return 1
    fi
    
    # Check sync progress
    local sync_speed=${SYNC_SPEEDS[$chain]:-0}
    if [[ $sync_speed -eq 0 ]] && [[ $current_block -gt 0 ]]; then
        log "WARN" "$chain sync appears stalled (0 blocks/sec)"
    fi
    
    return 0
}

# Main monitoring loop
monitor_chains() {
    log "INFO" "Starting Enterprise Blockchain Monitor"
    log "INFO" "Monitoring chains: ${!CHAINS[*]}"
    
    while true; do
        echo -e "\n=== Blockchain Status Report $(date) ===" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "\n=== Blockchain Status Report $(date) ==="
        
        local all_healthy=true
        
        for chain in "${!CHAINS[@]}"; do
            # Check service status
            local service_status=$(systemctl is-active $chain 2>/dev/null || echo "unknown")
            
            # Get chain data
            local chain_data=$(get_chain_status $chain)
            IFS='|' read -r block_num sync_response peer_count <<< "$chain_data"
            
            # Store peer count
            PEER_COUNTS[$chain]=$peer_count
            
            # Calculate sync speed
            calculate_sync_speed $chain $block_num
            
            # Format output
            local status_line="$chain: Block #$block_num"
            
            if [[ "$sync_response" != *"false"* ]] && [[ "$sync_response" != *"null"* ]] && [[ -n "$sync_response" ]]; then
                # Extract sync progress if available
                local current_hex=$(echo "$sync_response" | grep -o '"currentBlock":"0x[0-9a-fA-F]*"' | cut -d'"' -f4)
                local highest_hex=$(echo "$sync_response" | grep -o '"highestBlock":"0x[0-9a-fA-F]*"' | cut -d'"' -f4)
                
                if [[ -n "$current_hex" ]] && [[ -n "$highest_hex" ]]; then
                    local current=$((16#${current_hex#0x}))
                    local highest=$((16#${highest_hex#0x}))
                    if [[ $highest -gt 0 ]]; then
                        local progress=$(awk "BEGIN {printf \"%.2f\", ($current/$highest)*100}")
                        status_line+=" (Syncing: $progress%)"
                    fi
                fi
            fi
            
            status_line+=" | Peers: $peer_count | Speed: ${SYNC_SPEEDS[$chain]:-0} blocks/s | Service: $service_status"
            
            echo "$status_line" | tee -a "$LOG_FILE" 2>/dev/null || echo "$status_line"
            
            # Health check
            if ! health_check $chain $block_num $peer_count $service_status; then
                all_healthy=false
            fi
        done
        
        # System metrics
        echo -e "\n--- System Metrics ---" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "\n--- System Metrics ---"
        
        # Disk usage
        local disk_usage=$(df -h /data/blockchain | tail -1 | awk '{print $4" free ("$5" used)"}')
        echo "Disk: $disk_usage" | tee -a "$LOG_FILE" 2>/dev/null || echo "Disk: $disk_usage"
        
        # Memory
        local mem_info=$(free -h | awk '/^Mem:/ {print $7" available of "$2" ("int(($3/$2)*100)"% used)"}')
        echo "Memory: $mem_info" | tee -a "$LOG_FILE" 2>/dev/null || echo "Memory: $mem_info"
        
        # CPU load
        local cpu_load=$(uptime | awk -F'load average:' '{print $2}')
        echo "Load Average:$cpu_load" | tee -a "$LOG_FILE" 2>/dev/null || echo "Load Average:$cpu_load"
        
        # Generate metrics file
        generate_metrics
        
        # Overall health status
        if [[ "$all_healthy" == true ]]; then
            log "INFO" "All systems operational"
        else
            log "WARN" "Some systems require attention"
        fi
        
        sleep 60
    done
}

# Startup checks
startup_checks() {
    log "INFO" "Performing startup checks..."
    
    # Check if all required services exist
    for chain in "${!CHAINS[@]}"; do
        if ! systemctl list-unit-files | grep -q "^${chain}.service"; then
            log "WARN" "Service ${chain}.service not found"
        fi
    done
    
    # Check disk space
    local disk_free=$(df -BG /data/blockchain | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ $disk_free -lt 100 ]]; then
        log "WARN" "Low disk space: ${disk_free}GB free"
    fi
    
    log "INFO" "Startup checks complete"
}

# Signal handlers
trap 'log "INFO" "Monitor shutting down..."; exit 0' SIGTERM SIGINT

# Main execution
main() {
    startup_checks
    monitor_chains
}

# Run
main