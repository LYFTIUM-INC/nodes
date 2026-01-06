#!/bin/bash

# Polygon Memory Monitoring Script
# Optimized for MEV operations on 64GB system

set -e

LOG_FILE="/data/blockchain/nodes/logs/polygon-memory-monitor.log"
ALERT_THRESHOLD_PCT=85
MAX_BOR_MEMORY_GB=12
MAX_HEIMDALL_MEMORY_GB=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Convert bytes to human readable format
bytes_to_human() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    
    while [ $bytes -gt 1024 ] && [ $unit -lt ${#units[@]} ]; do
        bytes=$((bytes / 1024))
        unit=$((unit + 1))
    done
    
    echo "${bytes}${units[$unit]}"
}

# Get process memory usage
get_process_memory() {
    local process_name=$1
    local pid=$(pgrep -f "$process_name" | head -1)
    
    if [ -n "$pid" ]; then
        local mem_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$mem_kb" ]; then
            echo $((mem_kb * 1024))  # Convert to bytes
        else
            echo 0
        fi
    else
        echo 0
    fi
}

# Get system memory info
get_system_memory() {
    local total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local used_kb=$((total_kb - available_kb))
    
    echo "$total_kb $available_kb $used_kb"
}

# Check if memory usage is critical
check_memory_critical() {
    local process_name=$1
    local max_memory_gb=$2
    local current_memory_bytes=$3
    
    local max_memory_bytes=$((max_memory_gb * 1024 * 1024 * 1024))
    local usage_pct=$((current_memory_bytes * 100 / max_memory_bytes))
    
    if [ $usage_pct -gt $ALERT_THRESHOLD_PCT ]; then
        return 0  # Critical
    else
        return 1  # Normal
    fi
}

# Restart service if memory critical
restart_if_critical() {
    local service_name=$1
    local process_name=$2
    local max_memory_gb=$3
    local current_memory_bytes=$4
    
    if check_memory_critical "$process_name" "$max_memory_gb" "$current_memory_bytes"; then
        local usage_gb=$((current_memory_bytes / 1024 / 1024 / 1024))
        log_with_timestamp "CRITICAL: $service_name using ${usage_gb}GB (max: ${max_memory_gb}GB). Restarting..."
        
        # Graceful restart
        sudo systemctl restart "$service_name"
        sleep 10
        
        log_with_timestamp "$service_name restarted successfully"
        return 0
    fi
    
    return 1
}

# Main monitoring function
monitor_memory() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Get system memory info
    read total_kb available_kb used_kb <<< $(get_system_memory)
    local total_gb=$((total_kb / 1024 / 1024))
    local available_gb=$((available_kb / 1024 / 1024))
    local used_gb=$((used_kb / 1024 / 1024))
    local used_pct=$((used_kb * 100 / total_kb))
    
    # Get process memory usage
    local bor_memory=$(get_process_memory "bor")
    local heimdall_memory=$(get_process_memory "heimdall")
    
    local bor_memory_gb=$((bor_memory / 1024 / 1024 / 1024))
    local heimdall_memory_gb=$((heimdall_memory / 1024 / 1024 / 1024))
    
    # Display current status
    echo -e "${BLUE}=== Polygon Memory Monitor ===${NC}"
    echo -e "${BLUE}System Memory:${NC} ${used_gb}GB / ${total_gb}GB (${used_pct}%) - Available: ${available_gb}GB"
    echo -e "${BLUE}Bor Memory:${NC} ${bor_memory_gb}GB / ${MAX_BOR_MEMORY_GB}GB"
    echo -e "${BLUE}Heimdall Memory:${NC} ${heimdall_memory_gb}GB / ${MAX_HEIMDALL_MEMORY_GB}GB"
    
    # Log detailed info
    log_with_timestamp "System: ${used_gb}GB/${total_gb}GB (${used_pct}%), Bor: ${bor_memory_gb}GB, Heimdall: ${heimdall_memory_gb}GB"
    
    # Check for critical memory usage
    local restart_needed=false
    
    if restart_if_critical "polygon-bor" "bor" "$MAX_BOR_MEMORY_GB" "$bor_memory"; then
        restart_needed=true
    fi
    
    if restart_if_critical "polygon-heimdall" "heimdall" "$MAX_HEIMDALL_MEMORY_GB" "$heimdall_memory"; then
        restart_needed=true
    fi
    
    # Check overall system memory
    if [ $used_pct -gt 90 ]; then
        echo -e "${RED}WARNING: System memory usage is critical (${used_pct}%)${NC}"
        log_with_timestamp "WARNING: System memory usage critical: ${used_pct}%"
    fi
    
    # Service status check
    echo -e "\n${BLUE}=== Service Status ===${NC}"
    
    if systemctl is-active --quiet polygon-heimdall; then
        echo -e "Heimdall: ${GREEN}Running${NC}"
    else
        echo -e "Heimdall: ${RED}Stopped${NC}"
        log_with_timestamp "WARNING: Heimdall service is not running"
    fi
    
    if systemctl is-active --quiet polygon-bor; then
        echo -e "Bor: ${GREEN}Running${NC}"
    else
        echo -e "Bor: ${RED}Stopped${NC}"
        log_with_timestamp "WARNING: Bor service is not running"
    fi
    
    # Sync status check
    echo -e "\n${BLUE}=== Sync Status ===${NC}"
    
    # Check Heimdall sync
    if curl -s http://localhost:1317/status >/dev/null 2>&1; then
        local catching_up=$(curl -s http://localhost:1317/status | jq -r '.result.sync_info.catching_up' 2>/dev/null)
        if [ "$catching_up" = "false" ]; then
            echo -e "Heimdall: ${GREEN}Synced${NC}"
        elif [ "$catching_up" = "true" ]; then
            echo -e "Heimdall: ${YELLOW}Syncing${NC}"
        else
            echo -e "Heimdall: ${RED}Status Unknown${NC}"
        fi
    else
        echo -e "Heimdall: ${RED}RPC Not Responding${NC}"
    fi
    
    # Check Bor sync
    if curl -s -X POST -H "Content-Type: application/json" \
       --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
       http://localhost:8548 >/dev/null 2>&1; then
        local sync_status=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
            http://localhost:8548 | jq -r '.result' 2>/dev/null)
        
        if [ "$sync_status" = "false" ]; then
            echo -e "Bor: ${GREEN}Synced${NC}"
        else
            echo -e "Bor: ${YELLOW}Syncing${NC}"
        fi
    else
        echo -e "Bor: ${RED}RPC Not Responding${NC}"
    fi
    
    return 0
}

# Continuous monitoring mode
continuous_monitor() {
    local interval=${1:-60}  # Default 60 seconds
    
    echo "Starting continuous monitoring (interval: ${interval}s)"
    echo "Press Ctrl+C to stop"
    
    while true; do
        clear
        monitor_memory
        sleep "$interval"
    done
}

# Usage information
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -c, --continuous [interval]  Continuous monitoring (default: 60s)"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          Single check"
    echo "  $0 -c                       Continuous monitoring (60s interval)"
    echo "  $0 -c 30                    Continuous monitoring (30s interval)"
}

# Main execution
case "${1:-}" in
    -c|--continuous)
        continuous_monitor "${2:-60}"
        ;;
    -h|--help)
        usage
        ;;
    "")
        monitor_memory
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac