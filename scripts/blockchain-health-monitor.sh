#!/bin/bash
# Blockchain Node Health Monitor
# Monitors all critical RPC/WebSocket endpoints and services

LOG_FILE="/data/blockchain/logs/health-monitor.log"
DISK_THRESHOLD=85
ALERT_EMAIL="admin@blockchain.local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Function to check disk space
check_disk_space() {
    local usage=$(df /data/blockchain | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "${usage%.*}" -gt "$DISK_THRESHOLD" ]; then
        log "${RED}CRITICAL: Disk usage at ${usage}% (threshold: ${DISK_THRESHOLD}%)${NC}"
        return 1
    else
        log "${GREEN}OK: Disk usage at ${usage}%${NC}"
        return 0
    fi
}

# Function to test RPC endpoint
test_rpc() {
    local name=$1
    local url=$2
    local response=$(curl -s -m 5 "$url" \
        -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)
    
    if echo "$response" | grep -q '"result"'; then
        log "${GREEN}✅ $name RPC: Working${NC}"
        return 0
    else
        log "${RED}❌ $name RPC: Failed${NC}"
        return 1
    fi
}

# Function to test WebSocket endpoint
test_ws() {
    local name=$1
    local url=$2
    if echo '{"jsonrpc":"2.0","method":"eth_subscribe","params":["newHeads"],"id":1}' | timeout 5s websocat "$url" >/dev/null 2>&1; then
        log "${GREEN}✅ $name WebSocket: Working${NC}"
        return 0
    else
        log "${YELLOW}⚠️ $name WebSocket: Not responding${NC}"
        return 1
    fi
}

# Function to check Docker containers
check_docker() {
    local unhealthy=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep -v "healthy\|Up")
    if [ -n "$unhealthy" ]; then
        log "${YELLOW}⚠️ Unhealthy containers detected:${NC}"
        echo "$unhealthy" | while read line; do
            log "  $line"
        done
    else
        log "${GREEN}✅ All containers healthy${NC}"
    fi
}

# Function to check system services
check_services() {
    local failed_services=$(systemctl is-failed --no-legend | head -5)
    if [ -n "$failed_services" ]; then
        log "${RED}❌ Failed services:${NC}"
        echo "$failed_services" | while read line; do
            log "  $line"
        done
    else
        log "${GREEN}✅ All services running${NC}"
    fi
}

# Main health check
log "=== Blockchain Health Check Started ==="

check_disk_space
disk_status=$?

test_rpc "Erigon" "http://127.0.0.1:8545"
erigon_rpc_status=$?

test_rpc "Geth" "http://127.0.0.1:8549"
geth_rpc_status=$?

test_rpc "Reth" "http://127.0.0.1:18657"
reth_rpc_status=$?

test_ws "Erigon" "ws://127.0.0.1:8546"
erigon_ws_status=$?

test_ws "Geth" "ws://127.0.0.1:8550"
geth_ws_status=$?

check_docker
docker_status=$?

check_services
service_status=$?

# Test MEV services
if curl -s http://127.0.0.1:9098/health | grep -q "healthy"; then
    log "${GREEN}✅ MEV Execution: Working${NC}"
    mev_status=0
else
    log "${RED}❌ MEV Execution: Failed${NC}"
    mev_status=1
fi

# Summary
total_issues=$((disk_status + erigon_rpc_status + geth_rpc_status + reth_rpc_status + erigon_ws_status + geth_ws_status + docker_status + service_status + mev_status))

log "=== Health Check Summary ==="
if [ $total_issues -eq 0 ]; then
    log "${GREEN}🎉 ALL SYSTEMS OPERATIONAL${NC}"
    exit 0
else
    log "${YELLOW}⚠️  $total_issues issues detected${NC}"
    exit 1
fi
