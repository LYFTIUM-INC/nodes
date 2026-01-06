#!/bin/bash
# Blockchain Infrastructure Health Check Script
# Monitors execution layer (Geth/Erigon/Reth) and consensus layer (Lighthouse)
# Author: LYFTIUM Infrastructure Team
# Updated: 2025-01-06

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GETH_RPC="http://127.0.0.1:8549"
GETH_ENGINE="http://127.0.0.1:8554"
ERIGON_RPC="http://127.0.0.1:8545"
ERIGON_ENGINE="http://127.0.0.1:8552"
RETH_RPC="http://127.0.0.1:8557"
RETH_ENGINE="http://127.0.0.1:8553"
LIGHTHOUSE_API="http://127.0.0.1:5052"
MEV_BOOST="http://127.0.0.1:18551"

# Status tracking
EXIT_CODE=0

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; EXIT_CODE=1; }

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}    Blockchain Infrastructure Health Check${NC}"
    echo -e "${BLUE}    $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"
}

# Check if a port is listening using ss
check_port() {
    local port=$1
    local name=$2

    if ss -tln | grep -q ":$port "; then
        log_success "$name is listening on port $port"
        return 0
    else
        log_error "$name is NOT listening on port $port"
        return 1
    fi
}

# Check Ethereum RPC endpoint
check_rpc() {
    local url=$1
    local name=$2

    local result=$(curl -s -X POST -H "Content-Type: application/json" \
        --max-time 10 \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        "$url" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "$name RPC is not responding"
        return 1
    fi

    local syncing=$(echo "$result" | jq -r '.result' 2>/dev/null)

    if [[ "$syncing" == "false" ]]; then
        local block=$(curl -s -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "$url" 2>/dev/null | jq -r '.result' 2>/dev/null)
        log_success "$name is synced at block $((16#${block:2}))"
    elif [[ -n "$syncing" && "$syncing" != "null" ]]; then
        local current=$(echo "$syncing" | jq -r '.currentBlock' 2>/dev/null)
        local highest=$(echo "$syncing" | jq -r '.highestBlock' 2>/dev/null)
        local pct=$(echo "scale=1; ($current * 100 / $highest)" | bc 2>/dev/null)
        log_warning "$name is syncing: block $current / $highest (${pct}%)"
    else
        log_error "$name RPC error"
        return 1
    fi
}

# Check Engine API
check_engine() {
    local url=$1
    local name=$2

    local result=$(curl -s -X POST -H "Content-Type: application/json" \
        --max-time 10 \
        -d '{"jsonrpc":"2.0","method":"engine_getPayloadV1","params":["0x0000000000000000000000000000000000000000000000000000000000000000"],"id":1}' \
        "$url" 2>/dev/null)

    if echo "$result" | jq -e '.error' >/dev/null 2>&1; then
        # Error is expected if not synced, but we should get a response
        log_success "$name Engine API is responding"
    elif echo "$result" | jq -e '.result' >/dev/null 2>&1; then
        log_success "$name Engine API is operational"
    else
        log_warning "$name Engine API status unknown"
    fi
}

# Check Lighthouse
check_lighthouse() {
    local result=$(curl -s "$LIGHTHOUSE_API/eth/v1/node/syncing" --max-time 10 2>/dev/null)

    if [[ -z "$result" ]]; then
        log_error "Lighthouse API is not responding"
        return 1
    fi

    local head_slot=$(echo "$result" | jq -r '.data.head_slot' 2>/dev/null)
    local sync_state=$(echo "$result" | jq -r '.data.is_syncing' 2>/dev/null)

    if [[ "$sync_state" == "false" ]]; then
        log_success "Lighthouse is synced at slot $head_slot"
    else
        log_warning "Lighthouse is syncing (head_slot: $head_slot)"
    fi

    # Check connection to execution layer
    local is_optimistic=$(curl -s "$LIGHTHOUSE_API/eth/v1/node/health" --max-time 10 2>/dev/null | jq -r '.data.optimistic' 2>/dev/null)
    if [[ "$is_optimistic" == "true" ]]; then
        log_success "Lighthouse is connected to execution layer"
    else
        log_error "Lighthouse is NOT connected to execution layer"
    fi
}

# Check MEV-Boost
check_mev_boost() {
    local result=$(curl -s "$MEV_BOOST" --max-time 10 2>/dev/null)

    if [[ -z "$result" ]]; then
        log_error "MEV-Boost is not responding"
        return 1
    fi

    log_success "MEV-Boost is running"
}

# Check JWT secret consistency
check_jwt() {
    local jwt_common="/data/blockchain/storage/jwt-common/jwt-secret.hex"
    local jwt_link="/data/blockchain/storage/jwt-secret-common.hex"

    if [[ ! -f "$jwt_common" ]]; then
        log_error "JWT secret not found at $jwt_common"
        return 1
    fi

    # Check if symlink exists and points to the right place
    if [[ -L "$jwt_link" ]]; then
        local target=$(readlink -f "$jwt_link")
        if [[ "$target" == "$jwt_common" ]]; then
            log_success "JWT symlink is correctly configured"
        else
            log_warning "JWT symlink points to $target (should be $jwt_common)"
        fi
    else
        log_warning "JWT symlink not found at $jwt_link"
    fi

    # Check JWT file size (should be 32 or 64 bytes for hex)
    local size=$(stat -f%z "$jwt_common" 2>/dev/null || stat -c%s "$jwt_common" 2>/dev/null)
    if [[ "$size" == "32" || "$size" == "64" ]]; then
        log_success "JWT secret file size is correct ($size bytes)"
    else
        log_warning "JWT secret file size is unusual ($size bytes)"
    fi
}

# Check system resources
check_resources() {
    local mem_avail=$(free -m | awk '/^Mem:/{print $7}')
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local mem_pct=$((mem_avail * 100 / mem_total))

    if [[ $mem_avail -gt 8192 ]]; then
        log_success "Memory available: ${mem_avail}MB / ${mem_total}MB"
    elif [[ $mem_avail -gt 4096 ]]; then
        log_warning "Memory low: ${mem_avail}MB / ${mem_total}MB"
    else
        log_error "Memory critical: ${mem_avail}MB / ${mem_total}MB"
    fi

    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | cut -d',' -f1)
    local cpus=$(nproc)
    local load_pct=$(echo "scale=1; $load * 100 / $cpus" | bc 2>/dev/null)

    if (( $(echo "$load < $cpus" | bc -l) )); then
        log_success "Load average: $load (${load_pct}% of $cpus CPUs)"
    else
        log_warning "Load average is high: $load"
    fi
}

# Check disk space
check_disk() {
    local data_dir="/data/blockchain/storage"
    local avail=$(df -m "$data_dir" | awk 'NR==2 {print $4}')
    local total=$(df -m "$data_dir" | awk 'NR==2 {print $2}')
    local pct=$((100 - (avail * 100 / total)))

    if [[ $avail -gt 512000 ]]; then
        log_success "Disk space: ${avail}MB / ${total}MB available (${pct}% used)"
    elif [[ $avail -gt 102400 ]]; then
        log_warning "Disk space low: ${avail}MB remaining (${pct}% used)"
    else
        log_error "Disk space critical: ${avail}MB remaining (${pct}% used)"
    fi
}

# Main health check
main() {
    print_header

    # Check system resources first
    echo -e "${BLUE}System Resources${NC}"
    check_resources
    check_disk
    echo

    # Check JWT configuration
    echo -e "${BLUE}JWT Configuration${NC}"
    check_jwt
    echo

    # Check Execution Layer
    echo -e "${BLUE}Execution Layer${NC}"

    # Check Geth (primary)
    if check_port 8549 "Geth RPC"; then
        check_rpc "$GETH_RPC" "Geth"
    fi
    if check_port 8554 "Geth Engine"; then
        check_engine "$GETH_ENGINE" "Geth Engine API"
    fi

    # Check Erigon (backup)
    if check_port 8545 "Erigon RPC"; then
        check_rpc "$ERIGON_RPC" "Erigon"
    fi

    # Check Reth (if configured)
    if check_port 8557 "Reth RPC"; then
        check_rpc "$RETH_RPC" "Reth"
    fi

    echo

    # Check Consensus Layer
    echo -e "${BLUE}Consensus Layer${NC}"
    if check_port 5052 "Lighthouse API"; then
        check_lighthouse
    fi

    echo

    # Check MEV Infrastructure
    echo -e "${BLUE}MEV Infrastructure${NC}"
    check_mev_boost

    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"

    if [[ $EXIT_CODE -eq 0 ]]; then
        log_success "All critical services are operational"
    else
        log_error "Some services require attention"
    fi

    return $EXIT_CODE
}

# Run health check
main "$@"
