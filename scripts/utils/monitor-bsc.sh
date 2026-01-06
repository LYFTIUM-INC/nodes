#!/bin/bash

# BSC Node Monitoring Script
# Monitors sync status, memory usage, peer count, and performance

LOG_FILE="/data/bsc/logs/monitor.log"
ALERT_FILE="/data/bsc/logs/alerts.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $1" | tee -a "$ALERT_FILE"
}

check_rpc_health() {
    local response=$(curl -s -m 5 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
        http://localhost:8555 2>/dev/null)
    
    if echo "$response" | grep -q '"result":"56"'; then
        echo "✓ RPC HEALTHY"
        return 0
    else
        echo "✗ RPC UNHEALTHY"
        return 1
    fi
}

get_sync_status() {
    local response=$(curl -s -m 5 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":2}' \
        http://localhost:8555 2>/dev/null)
    
    if echo "$response" | grep -q '"result":false'; then
        echo "SYNCED"
    elif echo "$response" | grep -q '"currentBlock"'; then
        local current=$(echo "$response" | grep -o '"currentBlock":"[^"]*"' | cut -d'"' -f4)
        local highest=$(echo "$response" | grep -o '"highestBlock":"[^"]*"' | cut -d'"' -f4)
        
        # Convert hex to decimal
        current_dec=$(printf "%d" "$current" 2>/dev/null || echo "0")
        highest_dec=$(printf "%d" "$highest" 2>/dev/null || echo "0")
        
        if [ "$highest_dec" -gt 0 ]; then
            local progress=$(( current_dec * 100 / highest_dec ))
            echo "SYNCING ${progress}% (${current_dec}/${highest_dec})"
        else
            echo "SYNCING (unknown progress)"
        fi
    else
        echo "UNKNOWN"
    fi
}

get_peer_count() {
    local response=$(curl -s -m 5 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":3}' \
        http://localhost:8555 2>/dev/null)
    
    if echo "$response" | grep -q '"result"'; then
        local hex_count=$(echo "$response" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
        printf "%d" "$hex_count" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_memory_usage() {
    local pid=$(pgrep -f "geth.*8555")
    if [ -n "$pid" ]; then
        local memory_kb=$(ps -p "$pid" -o rss --no-headers 2>/dev/null | tr -d ' ')
        if [ -n "$memory_kb" ]; then
            local memory_mb=$((memory_kb / 1024))
            echo "${memory_mb}MB"
        else
            echo "N/A"
        fi
    else
        echo "NOT_RUNNING"
    fi
}

get_disk_usage() {
    local usage=$(du -sh /data/bsc 2>/dev/null | cut -f1)
    echo "${usage:-N/A}"
}

print_status() {
    echo -e "\n${BLUE}=== BSC Node Status ===${NC}"
    echo -e "Timestamp: $(date)"
    echo -e "RPC Health: $(check_rpc_health)"
    echo -e "Sync Status: $(get_sync_status)"
    echo -e "Peer Count: $(get_peer_count)"
    echo -e "Memory Usage: $(get_memory_usage)"
    echo -e "Disk Usage: $(get_disk_usage)"
    echo -e "Uptime: $(ps -p $(pgrep -f "geth.*8555") -o etime --no-headers 2>/dev/null | tr -d ' ' || echo 'NOT_RUNNING')"
    echo -e "${BLUE}=========================${NC}\n"
}

monitor_continuous() {
    echo -e "${GREEN}Starting BSC Node Monitor...${NC}"
    log_message "BSC Monitor started"
    
    while true; do
        # Check RPC health
        if ! check_rpc_health >/dev/null; then
            alert_message "RPC endpoint not responding"
        fi
        
        # Check peer count
        peer_count=$(get_peer_count)
        if [ "$peer_count" -lt 3 ]; then
            alert_message "Low peer count: $peer_count"
        fi
        
        # Check memory usage
        memory_usage=$(get_memory_usage)
        if [[ "$memory_usage" == "NOT_RUNNING" ]]; then
            alert_message "BSC process not running"
        elif [[ "$memory_usage" =~ ^([0-9]+)MB$ ]]; then
            memory_mb=${BASH_REMATCH[1]}
            if [ "$memory_mb" -gt 14000 ]; then
                alert_message "High memory usage: ${memory_usage}"
            fi
        fi
        
        # Log current status
        sync_status=$(get_sync_status)
        log_message "Status: RPC=$(check_rpc_health), Sync=${sync_status}, Peers=${peer_count}, Memory=${memory_usage}"
        
        sleep 30
    done
}

case "${1:-status}" in
    "status")
        print_status
        ;;
    "monitor")
        monitor_continuous
        ;;
    "log")
        tail -f "$LOG_FILE"
        ;;
    "alerts")
        tail -f "$ALERT_FILE"
        ;;
    *)
        echo "Usage: $0 {status|monitor|log|alerts}"
        echo "  status  - Show current status"
        echo "  monitor - Run continuous monitoring"
        echo "  log     - Show monitor log"
        echo "  alerts  - Show alerts log"
        exit 1
        ;;
esac