#!/bin/bash
# Quick Status Check - Simple monitoring without bc dependencies
# Provides essential node health information

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Blockchain Node Quick Status ===${NC}"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# System Resources
echo -e "${YELLOW}System Resources:${NC}"
echo "  CPU Load: $(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)"
echo "  Memory: $(free -h | awk 'NR==2{printf "%s/%s (%.0f%%)", $3, $2, $3*100/$2}')"
echo "  Disk: $(df -h /data | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
echo ""

# Node Status
echo -e "${YELLOW}Node Status:${NC}"

# Check each node
nodes=("ethereum-light:Ethereum:8545" "solana-dev:Solana:8899" "arbitrum-node:Arbitrum:8548")

for node_info in "${nodes[@]}"; do
    IFS=':' read -r container display port <<< "$node_info"
    
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        status="${GREEN}Running${NC}"
        
        # Quick RPC test
        if curl -s --max-time 2 -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
            "http://localhost:${port}" >/dev/null 2>&1; then
            rpc_status="${GREEN}RPC OK${NC}"
        else
            rpc_status="${YELLOW}RPC Pending${NC}"
        fi
    else
        status="${RED}Stopped${NC}"
        rpc_status="${RED}N/A${NC}"
    fi
    
    printf "  %-12s %s | %s\n" "$display:" "$status" "$rpc_status"
done

# MEV-Boost status
echo ""
if curl -s --max-time 2 http://localhost:18550/eth/v1/builder/status >/dev/null 2>&1; then
    echo -e "  MEV-Boost:   ${GREEN}Connected${NC}"
else
    echo -e "  MEV-Boost:   ${RED}Disconnected${NC}"
fi

echo ""

# Quick alerts
echo -e "${YELLOW}Quick Alerts:${NC}"

# Check disk space
disk_usage=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$disk_usage" -ge 85 ]; then
    echo -e "  ${RED}⚠${NC} Disk usage critical: ${disk_usage}%"
elif [ "$disk_usage" -ge 75 ]; then
    echo -e "  ${YELLOW}⚠${NC} Disk usage warning: ${disk_usage}%"
fi

# Check load
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
load_int=${load_avg%.*}
cpu_count=$(nproc)

if [ "$load_int" -gt "$cpu_count" ]; then
    echo -e "  ${RED}⚠${NC} High system load: ${load_avg}"
fi

# Check if Ethereum is syncing
if docker ps --format "{{.Names}}" | grep -q "^ethereum-light$"; then
    sync_response=$(curl -s --max-time 3 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null | jq -r '.result // "unknown"')
    
    if [ "$sync_response" != "false" ] && [ "$sync_response" != "unknown" ]; then
        echo -e "  ${BLUE}ℹ${NC} Ethereum still syncing"
    elif [ "$sync_response" = "false" ]; then
        echo -e "  ${GREEN}✓${NC} Ethereum fully synced"
    fi
fi

echo ""
echo -e "${BLUE}=== Status Check Complete ===${NC}"
echo "For detailed monitoring: /data/blockchain/nodes/monitoring/enhanced-dashboard.sh"