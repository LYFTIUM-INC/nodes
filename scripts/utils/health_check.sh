#!/bin/bash

# MEV Infrastructure Health Check Script
# Runs automated health checks every minute

# Set up logging
LOG_DIR="/data/blockchain/nodes/mev/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/health-check.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if a process is running
check_process() {
    local process_name=$1
    if pgrep -f "$process_name" > /dev/null; then
        echo "OK"
    else
        echo "FAILED"
    fi
}

# Function to check if a port is listening
check_port() {
    local port=$1
    if netstat -tuln | grep -q ":$port "; then
        echo "OK"
    else
        echo "FAILED"
    fi
}

# Function to check RPC endpoint
check_rpc() {
    local url=$1
    local name=$2
    
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$url" --max-time 5)
    
    if [[ $response == *"result"* ]]; then
        echo "OK"
    else
        echo "FAILED"
    fi
}

# Function to check disk space
check_disk_space() {
    local threshold=$1
    local usage=$(df /data | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ $usage -lt $threshold ]; then
        echo "OK ($usage%)"
    else
        echo "WARNING ($usage%)"
    fi
}

# Function to check memory usage
check_memory() {
    local threshold=$1
    local usage=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
    
    if [ $usage -lt $threshold ]; then
        echo "OK ($usage%)"
    else
        echo "WARNING ($usage%)"
    fi
}

# Function to check CPU usage
check_cpu() {
    local threshold=$1
    local usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    
    if (( $(echo "$usage < $threshold" | bc -l) )); then
        echo "OK ($usage%)"
    else
        echo "WARNING ($usage%)"
    fi
}

# Main health check
log "Starting MEV infrastructure health check"

# Check system resources
log "=== System Resources ==="
log "CPU Usage: $(check_cpu 75)"
log "Memory Usage: $(check_memory 80)"
log "Disk Space: $(check_disk_space 85)"

# Check blockchain nodes
log "=== Blockchain Nodes ==="
log "Ethereum RPC: $(check_rpc 'http://ethereum-erigon:8545' 'Ethereum')"
log "Arbitrum RPC: $(check_rpc 'http://arbitrum-node:8549' 'Arbitrum')"
log "Optimism RPC: $(check_rpc 'http://optimism-node:8551' 'Optimism')"
log "Base RPC: $(check_rpc 'http://base-mainnet:8553' 'Base')"
log "Polygon RPC: $(check_rpc 'http://polygon-bor:8545' 'Polygon')"

# Check MEV services
log "=== MEV Services ==="

# Check if MEV monitoring is running
MONITOR_STATUS=$(check_process "mev_monitoring.py")
log "MEV Monitor: $MONITOR_STATUS"

# Check if unified manager is running
MANAGER_STATUS=$(check_process "unified_manager.py")
log "Unified Manager: $MANAGER_STATUS"

# Check critical ports
log "=== Network Ports ==="
log "Ethereum Port 8545: $(check_port 8545)"
log "Arbitrum Port 8549: $(check_port 8549)"
log "Optimism Port 8551: $(check_port 8551)"
log "Base Port 8553: $(check_port 8553)"

# Check Docker containers
log "=== Docker Containers ==="
for container in ethereum-light arbitrum-node optimism-node base-mainnet polygon-bor; do
    if docker ps | grep -q "$container"; then
        log "$container: OK"
    else
        log "$container: FAILED"
    fi
done

# Generate summary
ISSUES=0
grep -q "FAILED\|WARNING" "$LOG_FILE" && ISSUES=1

if [ $ISSUES -eq 0 ]; then
    log "=== Health Check Complete: ALL SYSTEMS OPERATIONAL ==="
else
    log "=== Health Check Complete: ISSUES DETECTED ==="
    
    # Send alert if critical issues found
    if grep -q "FAILED" "$LOG_FILE"; then
        log "CRITICAL: System failures detected!"
        # TODO: Add alert notification here (webhook, email, etc)
    fi
fi

log "Health check completed"
echo "---"