#!/bin/bash
# Blockchain Node Health Monitoring Dashboard
# Real-time monitoring for MEV arbitrage infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_WARNING_THRESHOLD=75
RESOURCE_CRITICAL_THRESHOLD=90
RPC_TIMEOUT=5

# Function to check if a service is running
check_service() {
    local service=$1
    if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
        echo -e "${GREEN}●${NC} Running"
    else
        echo -e "${RED}●${NC} Stopped"
    fi
}

# Function to get container resource usage
get_container_stats() {
    local container=$1
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" "${container}" 2>/dev/null | tail -1
    else
        echo "N/A\tN/A\tN/A\tN/A"
    fi
}

# Function to check RPC endpoint
check_rpc_endpoint() {
    local url=$1
    local method=$2
    local params=$3
    
    local response=$(curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" \
        --max-time ${RPC_TIMEOUT} \
        "${url}" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response"
    else
        echo "ERROR"
    fi
}

# Function to get Ethereum block info
get_eth_block_info() {
    local port=$1
    local response=$(check_rpc_endpoint "http://localhost:${port}" "eth_blockNumber" "[]")
    
    if [ "$response" != "ERROR" ]; then
        local block_hex=$(echo "$response" | jq -r '.result' 2>/dev/null)
        if [ -n "$block_hex" ] && [ "$block_hex" != "null" ]; then
            printf "%d" "$block_hex"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# Function to get Solana slot info
get_solana_slot_info() {
    local response=$(check_rpc_endpoint "http://localhost:8899" "getSlot" "[]")
    
    if [ "$response" != "ERROR" ]; then
        echo "$response" | jq -r '.result' 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# Function to calculate color based on percentage
get_color_by_percentage() {
    local value=$1
    local clean_value=${value%.*}
    
    if [ "$clean_value" -ge "$RESOURCE_CRITICAL_THRESHOLD" ]; then
        echo "$RED"
    elif [ "$clean_value" -ge "$RESOURCE_WARNING_THRESHOLD" ]; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

# Clear screen and display header
clear
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    BLOCKCHAIN NODE HEALTH MONITORING DASHBOARD                 ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# System Overview
echo -e "${YELLOW}▶ SYSTEM OVERVIEW${NC}"
echo -e "────────────────────────────────────────────────────────────────────────────────"
load=$(uptime | awk -F'load average:' '{print $2}')
cpu_count=$(nproc)
mem_info=$(free -h | grep Mem | awk '{print $2, $3, $4}')
disk_info=$(df -h /data | tail -1 | awk '{print $2, $3, $4, $5}')

echo -e "Load Average:${load} (${cpu_count} CPUs)"
echo -e "Memory: ${mem_info}"
echo -e "Disk (/data): ${disk_info}"
echo ""

# Node Status
echo -e "${YELLOW}▶ NODE STATUS${NC}"
echo -e "────────────────────────────────────────────────────────────────────────────────"
printf "%-20s %-10s %-20s %-10s %-10s\n" "NODE" "STATUS" "BLOCK/SLOT" "CPU" "MEMORY"
echo -e "────────────────────────────────────────────────────────────────────────────────"

# Ethereum Erigon
eth_status=$(check_service "ethereum-erigon")
eth_block=$(get_eth_block_info 8545)
eth_stats=$(get_container_stats "ethereum-erigon")
eth_cpu=$(echo "$eth_stats" | awk '{print $2}')
eth_mem=$(echo "$eth_stats" | awk '{print $4}')
printf "%-20s %-10s %-20s %-10s %-10s\n" "Ethereum (Erigon)" "$eth_status" "Block: $eth_block" "$eth_cpu" "$eth_mem"

# Solana
solana_status=$(check_service "solana-dev")
solana_slot=$(get_solana_slot_info)
solana_stats=$(get_container_stats "solana-dev")
solana_cpu=$(echo "$solana_stats" | awk '{print $2}')
solana_mem=$(echo "$solana_stats" | awk '{print $4}')
printf "%-20s %-10s %-20s %-10s %-10s\n" "Solana" "$solana_status" "Slot: $solana_slot" "$solana_cpu" "$solana_mem"

# Arbitrum
arb_status=$(check_service "arbitrum-node")
arb_block=$(get_eth_block_info 8548)
arb_stats=$(get_container_stats "arbitrum-node")
arb_cpu=$(echo "$arb_stats" | awk '{print $2}')
arb_mem=$(echo "$arb_stats" | awk '{print $4}')
printf "%-20s %-10s %-20s %-10s %-10s\n" "Arbitrum" "$arb_status" "Block: $arb_block" "$arb_cpu" "$arb_mem"

# Optimism
op_status=$(check_service "optimism-node")
op_block=$(get_eth_block_info 8550)
op_stats=$(get_container_stats "optimism-node")
op_cpu=$(echo "$op_stats" | awk '{print $2}')
op_mem=$(echo "$op_stats" | awk '{print $4}')
printf "%-20s %-10s %-20s %-10s %-10s\n" "Optimism" "$op_status" "Block: $op_block" "$op_cpu" "$op_mem"

# Base
base_status=$(check_service "base-node")
base_block=$(get_eth_block_info 8547)
base_stats=$(get_container_stats "base-node")
base_cpu=$(echo "$base_stats" | awk '{print $2}')
base_mem=$(echo "$base_stats" | awk '{print $4}')
printf "%-20s %-10s %-20s %-10s %-10s\n" "Base" "$base_status" "Block: $base_block" "$base_cpu" "$base_mem"

# MEV-Boost
mev_status=$(check_service "mev-boost")
mev_stats=$(get_container_stats "mev-boost")
mev_cpu=$(echo "$mev_stats" | awk '{print $2}')
mev_mem=$(echo "$mev_stats" | awk '{print $4}')
printf "%-20s %-10s %-20s %-10s %-10s\n" "MEV-Boost" "$mev_status" "N/A" "$mev_cpu" "$mev_mem"

echo ""

# RPC Endpoint Health
echo -e "${YELLOW}▶ RPC ENDPOINT HEALTH${NC}"
echo -e "────────────────────────────────────────────────────────────────────────────────"
printf "%-20s %-15s %-10s %-30s\n" "ENDPOINT" "PORT" "STATUS" "LATENCY"
echo -e "────────────────────────────────────────────────────────────────────────────────"

# Test each RPC endpoint
endpoints=(
    "Ethereum HTTP|8545|eth_blockNumber"
    "Ethereum WS|8546|eth_blockNumber"
    "Solana HTTP|8899|getSlot"
    "Solana WS|8900|getSlot"
    "Arbitrum HTTP|8548|eth_blockNumber"
    "Optimism HTTP|8550|eth_blockNumber"
    "Base HTTP|8547|eth_blockNumber"
)

for endpoint in "${endpoints[@]}"; do
    IFS='|' read -r name port method <<< "$endpoint"
    start_time=$(date +%s%N)
    
    if [[ "$name" == *"WS"* ]]; then
        # WebSocket test
        timeout 1 bash -c "echo '' | nc -w1 localhost $port" >/dev/null 2>&1
        result=$?
    else
        # HTTP test
        response=$(check_rpc_endpoint "http://localhost:${port}" "${method}" "[]")
        [ "$response" != "ERROR" ] && result=0 || result=1
    fi
    
    end_time=$(date +%s%N)
    latency=$(( (end_time - start_time) / 1000000 ))
    
    if [ $result -eq 0 ]; then
        status="${GREEN}●${NC} Online"
        latency_str="${latency}ms"
    else
        status="${RED}●${NC} Offline"
        latency_str="N/A"
    fi
    
    printf "%-20s %-15s %-10s %-30s\n" "$name" "$port" "$status" "$latency_str"
done

echo ""

# MEV Readiness Check
echo -e "${YELLOW}▶ MEV EXECUTION READINESS${NC}"
echo -e "────────────────────────────────────────────────────────────────────────────────"

# Check if MEV-boost is accessible
mev_boost_check=$(curl -s http://localhost:18550/eth/v1/builder/status 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "MEV-Boost Status: ${GREEN}Connected${NC}"
else
    echo -e "MEV-Boost Status: ${RED}Disconnected${NC}"
fi

# Check transaction pool
if [ "$eth_status" == *"Running"* ]; then
    txpool_status=$(check_rpc_endpoint "http://localhost:8545" "txpool_status" "{}")
    if [ "$txpool_status" != "ERROR" ]; then
        pending=$(echo "$txpool_status" | jq -r '.result.pending' 2>/dev/null | wc -l)
        queued=$(echo "$txpool_status" | jq -r '.result.queued' 2>/dev/null | wc -l)
        echo -e "Transaction Pool: Pending: $pending, Queued: $queued"
    else
        echo -e "Transaction Pool: ${RED}Unavailable${NC}"
    fi
fi

echo ""

# Alerts and Recommendations
echo -e "${YELLOW}▶ ALERTS & RECOMMENDATIONS${NC}"
echo -e "────────────────────────────────────────────────────────────────────────────────"

alert_count=0

# Check system load
load_1=$(echo "$load" | awk '{print $1}' | sed 's/,//')
if (( $(echo "$load_1 > $cpu_count" | bc -l) )); then
    echo -e "${RED}⚠${NC}  High system load detected: $load_1 (threshold: $cpu_count)"
    ((alert_count++))
fi

# Check disk usage
disk_usage=$(df -h /data | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$disk_usage" -ge 80 ]; then
    echo -e "${RED}⚠${NC}  High disk usage: ${disk_usage}% (threshold: 80%)"
    ((alert_count++))
fi

# Check stopped nodes
for node in "ethereum-erigon" "arbitrum-node" "optimism-node" "base-node"; do
    if ! docker ps --format "{{.Names}}" | grep -q "^${node}$"; then
        echo -e "${RED}⚠${NC}  Node ${node} is not running"
        ((alert_count++))
    fi
done

if [ $alert_count -eq 0 ]; then
    echo -e "${GREEN}✓${NC} All systems operational"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "Press Ctrl+C to exit | Refresh: Run script again"