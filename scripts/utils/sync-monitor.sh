#!/bin/bash

# Erigon Sync Monitoring Script for MEV Operations
# Monitors sync progress, performance metrics, and system resources

set -e

# Configuration
LOG_FILE="/data/blockchain/storage/erigon/logs/sync-monitor.log"
ALERT_LOG="/data/blockchain/storage/erigon/logs/sync-alerts.log"
METRICS_FILE="/data/blockchain/storage/erigon/logs/sync-metrics.json"
ERIGON_RPC="http://localhost:8545"
ERIGON_METRICS="http://localhost:6060/metrics"
NETWORK_RPC="https://ethereum.publicnode.com"

# Thresholds
MAX_BLOCKS_BEHIND=100
MIN_SYNC_SPEED=10  # blocks per minute
MAX_MEMORY_USAGE=90  # percentage
MIN_DISK_SPACE=50    # GB

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_alert() {
    local message=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ALERT: $message" | tee -a "$ALERT_LOG"
    log_message "ALERT" "$message"
}

get_rpc_response() {
    local rpc_url=$1
    local method=$2
    local params=${3:-"[]"}
    
    curl -s -X POST -H "Content-Type: application/json" \
         --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
         "$rpc_url" 2>/dev/null
}

hex_to_dec() {
    local hex_value=$1
    if [ -n "$hex_value" ] && [ "$hex_value" != "null" ] && [ "$hex_value" != "0x" ]; then
        printf "%d" "$hex_value" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_sync_status() {
    local sync_response=$(get_rpc_response "$ERIGON_RPC" "eth_syncing")
    echo "$sync_response" | jq -r '.result' 2>/dev/null || echo "false"
}

get_current_block() {
    local block_response=$(get_rpc_response "$ERIGON_RPC" "eth_blockNumber")
    local block_hex=$(echo "$block_response" | jq -r '.result' 2>/dev/null)
    hex_to_dec "$block_hex"
}

get_network_block() {
    local block_response=$(get_rpc_response "$NETWORK_RPC" "eth_blockNumber")
    local block_hex=$(echo "$block_response" | jq -r '.result' 2>/dev/null)
    hex_to_dec "$block_hex"
}

get_peer_count() {
    local peer_response=$(get_rpc_response "$ERIGON_RPC" "net_peerCount")
    local peer_hex=$(echo "$peer_response" | jq -r '.result' 2>/dev/null)
    hex_to_dec "$peer_hex"
}

get_memory_usage() {
    local total_mem=$(free | grep '^Mem:' | awk '{print $2}')
    local used_mem=$(free | grep '^Mem:' | awk '{print $3}')
    echo "scale=2; $used_mem * 100 / $total_mem" | bc -l 2>/dev/null || echo "0"
}

get_disk_space() {
    df /data | tail -1 | awk '{print $4}' | sed 's/G//' | awk '{print int($1/1024/1024)}'
}

get_erigon_memory() {
    local erigon_pid=$(pgrep -f "erigon.*--datadir.*erigon" 2>/dev/null | head -1)
    if [ -n "$erigon_pid" ]; then
        ps -p "$erigon_pid" -o rss= 2>/dev/null | awk '{print int($1/1024/1024)}'
    else
        echo "0"
    fi
}

get_sync_speed() {
    # Calculate blocks per minute based on recent progress
    local current_time=$(date +%s)
    local temp_file="/tmp/erigon_sync_speed.tmp"
    
    if [ -f "$temp_file" ]; then
        local last_data=$(cat "$temp_file")
        local last_time=$(echo "$last_data" | cut -d: -f1)
        local last_block=$(echo "$last_data" | cut -d: -f2)
        
        local time_diff=$((current_time - last_time))
        local current_block=$(get_current_block)
        local block_diff=$((current_block - last_block))
        
        if [ $time_diff -gt 0 ]; then
            echo "scale=2; $block_diff * 60 / $time_diff" | bc -l 2>/dev/null || echo "0"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
    
    # Update the temp file
    echo "$current_time:$(get_current_block)" > "$temp_file"
}

check_erigon_health() {
    local health_response=$(get_rpc_response "$ERIGON_RPC" "eth_blockNumber")
    if echo "$health_response" | jq -e '.result' > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

generate_metrics_json() {
    local current_block=$(get_current_block)
    local network_block=$(get_network_block)
    local blocks_behind=$((network_block - current_block))
    local sync_percentage="0"
    
    if [ $network_block -gt 0 ] && [ $current_block -gt 0 ]; then
        sync_percentage=$(echo "scale=4; $current_block * 100 / $network_block" | bc -l 2>/dev/null || echo "0")
    fi
    
    local peer_count=$(get_peer_count)
    local memory_usage=$(get_memory_usage)
    local disk_space=$(get_disk_space)
    local erigon_memory=$(get_erigon_memory)
    local sync_speed=$(get_sync_speed)
    local sync_status=$(get_sync_status)
    local is_syncing="true"
    
    if [ "$sync_status" = "false" ] || [ $blocks_behind -lt 10 ]; then
        is_syncing="false"
    fi
    
    cat > "$METRICS_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "sync": {
    "current_block": $current_block,
    "network_block": $network_block,
    "blocks_behind": $blocks_behind,
    "sync_percentage": $sync_percentage,
    "is_syncing": $is_syncing,
    "sync_speed_blocks_per_minute": $sync_speed
  },
  "network": {
    "peer_count": $peer_count
  },
  "resources": {
    "memory_usage_percent": $memory_usage,
    "disk_space_available_gb": $disk_space,
    "erigon_memory_usage_gb": $erigon_memory
  },
  "health": {
    "rpc_responsive": $(check_erigon_health && echo "true" || echo "false")
  }
}
EOF
}

check_alerts() {
    local current_block=$(get_current_block)
    local network_block=$(get_network_block)
    local blocks_behind=$((network_block - current_block))
    local memory_usage=$(get_memory_usage)
    local disk_space=$(get_disk_space)
    local sync_speed=$(get_sync_speed)
    local peer_count=$(get_peer_count)
    
    # Check if too far behind
    if [ $blocks_behind -gt $MAX_BLOCKS_BEHIND ] && [ $current_block -gt 0 ]; then
        log_alert "Node is $blocks_behind blocks behind (threshold: $MAX_BLOCKS_BEHIND)"
    fi
    
    # Check sync speed
    local sync_speed_int=$(echo "$sync_speed" | cut -d. -f1)
    if [ $current_block -gt 0 ] && [ $blocks_behind -gt 50 ] && [ ${sync_speed_int:-0} -lt $MIN_SYNC_SPEED ]; then
        log_alert "Sync speed is ${sync_speed} blocks/min (threshold: $MIN_SYNC_SPEED)"
    fi
    
    # Check memory usage
    local memory_usage_int=$(echo "$memory_usage" | cut -d. -f1)
    if [ ${memory_usage_int:-0} -gt $MAX_MEMORY_USAGE ]; then
        log_alert "Memory usage is ${memory_usage}% (threshold: $MAX_MEMORY_USAGE%)"
    fi
    
    # Check disk space
    if [ $disk_space -lt $MIN_DISK_SPACE ]; then
        log_alert "Disk space is ${disk_space}GB (threshold: ${MIN_DISK_SPACE}GB)"
    fi
    
    # Check if Erigon is not responding
    if ! check_erigon_health; then
        log_alert "Erigon RPC is not responding"
    fi
    
    # Check peer count
    if [ $peer_count -lt 5 ]; then
        log_alert "Low peer count: $peer_count (minimum recommended: 5)"
    fi
}

display_status() {
    clear
    echo -e "${BLUE}=== Erigon Sync Monitor for MEV Operations ===${NC}"
    echo "Timestamp: $(date)"
    echo
    
    local current_block=$(get_current_block)
    local network_block=$(get_network_block)
    local blocks_behind=$((network_block - current_block))
    local sync_percentage="0"
    
    if [ $network_block -gt 0 ] && [ $current_block -gt 0 ]; then
        sync_percentage=$(echo "scale=2; $current_block * 100 / $network_block" | bc -l 2>/dev/null || echo "0")
    fi
    
    echo -e "${GREEN}Sync Status:${NC}"
    echo "  Current Block:   $(printf "%'d" $current_block)"
    echo "  Network Block:   $(printf "%'d" $network_block)"
    echo "  Blocks Behind:   $(printf "%'d" $blocks_behind)"
    echo "  Sync Progress:   ${sync_percentage}%"
    
    if [ $blocks_behind -lt 10 ] && [ $current_block -gt 0 ]; then
        echo -e "  Status:          ${GREEN}SYNCED${NC}"
    elif [ $current_block -gt 0 ]; then
        echo -e "  Status:          ${YELLOW}SYNCING${NC}"
    else
        echo -e "  Status:          ${RED}NOT SYNCED${NC}"
    fi
    
    echo
    echo -e "${GREEN}Performance:${NC}"
    local sync_speed=$(get_sync_speed)
    echo "  Sync Speed:      ${sync_speed} blocks/min"
    
    if [ $blocks_behind -gt 0 ] && [ $current_block -gt 0 ]; then
        local eta_minutes=$(echo "scale=0; $blocks_behind / $sync_speed" | bc -l 2>/dev/null)
        if [ ${eta_minutes:-0} -gt 0 ]; then
            local eta_hours=$((eta_minutes / 60))
            local eta_mins=$((eta_minutes % 60))
            echo "  ETA to Sync:     ${eta_hours}h ${eta_mins}m"
        fi
    fi
    
    echo "  Peer Count:      $(get_peer_count)"
    
    echo
    echo -e "${GREEN}Resources:${NC}"
    echo "  Memory Usage:    $(get_memory_usage)%"
    echo "  Erigon Memory:   $(get_erigon_memory)GB"
    echo "  Disk Available:  $(get_disk_space)GB"
    
    echo
    echo -e "${GREEN}Health:${NC}"
    if check_erigon_health; then
        echo -e "  RPC Status:      ${GREEN}HEALTHY${NC}"
    else
        echo -e "  RPC Status:      ${RED}UNHEALTHY${NC}"
    fi
    
    local sync_status=$(get_sync_status)
    if [ "$sync_status" != "false" ]; then
        echo "  Sync Details:    $sync_status"
    fi
    
    echo
    echo "Press Ctrl+C to exit"
}

# Main monitoring loop
main() {
    echo -e "${GREEN}Starting Erigon Sync Monitor...${NC}"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_message "INFO" "Sync monitor started"
    
    if [ "$1" = "--continuous" ]; then
        # Continuous monitoring mode
        while true; do
            display_status
            generate_metrics_json
            check_alerts
            sleep 30
        done
    else
        # Single run mode
        display_status
        generate_metrics_json
        check_alerts
        
        echo
        echo "Metrics saved to: $METRICS_FILE"
        echo "Logs saved to: $LOG_FILE"
        echo
        echo "For continuous monitoring, run: $0 --continuous"
    fi
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}Monitoring stopped${NC}"; exit 0' INT

# Run main function
main "$@"