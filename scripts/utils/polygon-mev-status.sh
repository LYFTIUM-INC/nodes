#!/bin/bash

# Polygon MEV Node Status Script
# Shows current status of the optimized Polygon deployment

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=== POLYGON MEV NODE STATUS ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Container Status
echo -e "${CYAN}=== Container Status ===${NC}"
if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "(polygon-|NAMES)"; then
    echo ""
else
    echo -e "${RED}No Polygon containers running${NC}"
fi

# Network Tests
echo -e "${CYAN}=== Network Connectivity ===${NC}"

# Test Heimdall
if HEIMDALL_RESULT=$(curl -s http://localhost:1317/status 2>/dev/null); then
    NETWORK=$(echo "$HEIMDALL_RESULT" | jq -r '.result.node_info.network // "unknown"')
    CATCHING_UP=$(echo "$HEIMDALL_RESULT" | jq -r '.result.sync_info.catching_up // "unknown"')
    LATEST_HEIGHT=$(echo "$HEIMDALL_RESULT" | jq -r '.result.sync_info.latest_block_height // "0"')
    
    if [ "$CATCHING_UP" = "false" ]; then
        echo -e "Heimdall (port 1317): ${GREEN}Synced${NC} - Network: $NETWORK, Block: $LATEST_HEIGHT"
    elif [ "$CATCHING_UP" = "true" ]; then
        echo -e "Heimdall (port 1317): ${YELLOW}Syncing${NC} - Network: $NETWORK, Block: $LATEST_HEIGHT"
    else
        echo -e "Heimdall (port 1317): ${YELLOW}Starting${NC} - Network: $NETWORK"
    fi
else
    echo -e "Heimdall (port 1317): ${RED}Not responding${NC}"
fi

# Test Bor
if BOR_RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
   --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
   http://localhost:8547 2>/dev/null); then
    
    CHAIN_ID=$(echo "$BOR_RESULT" | jq -r '.result // "unknown"')
    
    # Get block number
    BLOCK_RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
       --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
       http://localhost:8547 2>/dev/null)
    BLOCK_NUMBER=$(echo "$BLOCK_RESULT" | jq -r '.result // "0x0"')
    BLOCK_DECIMAL=$((BLOCK_NUMBER))
    
    # Get sync status
    SYNC_RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
       --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
       http://localhost:8547 2>/dev/null)
    SYNCING=$(echo "$SYNC_RESULT" | jq -r '.result')
    
    if [ "$CHAIN_ID" = "0x89" ]; then
        NETWORK_NAME="Polygon Mainnet"
    else
        NETWORK_NAME="Chain ID: $CHAIN_ID"
    fi
    
    if [ "$SYNCING" = "false" ]; then
        echo -e "Bor (port 8547): ${GREEN}Synced${NC} - $NETWORK_NAME, Block: $BLOCK_DECIMAL"
    else
        echo -e "Bor (port 8547): ${YELLOW}Syncing${NC} - $NETWORK_NAME, Block: $BLOCK_DECIMAL"
    fi
else
    echo -e "Bor (port 8547): ${RED}Not responding${NC}"
fi

# Peer Count
echo ""
echo -e "${CYAN}=== Peer Connectivity ===${NC}"
if PEER_RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
   --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
   http://localhost:8547 2>/dev/null); then
    PEER_COUNT_HEX=$(echo "$PEER_RESULT" | jq -r '.result // "0x0"')
    PEER_COUNT=$((PEER_COUNT_HEX))
    
    if [ $PEER_COUNT -gt 10 ]; then
        echo -e "Bor peers: ${GREEN}$PEER_COUNT connected${NC}"
    elif [ $PEER_COUNT -gt 0 ]; then
        echo -e "Bor peers: ${YELLOW}$PEER_COUNT connected${NC}"
    else
        echo -e "Bor peers: ${RED}No peers connected${NC}"
    fi
else
    echo -e "Bor peers: ${RED}Unable to check${NC}"
fi

# Resource Usage
echo ""
echo -e "${CYAN}=== Resource Usage ===${NC}"

# System Memory
TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
AVAILABLE_MEM=$(grep MemAvailable /proc/meminfo | awk '{print int($2/1024)}')
USED_MEM=$((TOTAL_MEM - AVAILABLE_MEM))
USAGE_PCT=$((USED_MEM * 100 / TOTAL_MEM))

if [ $USAGE_PCT -gt 90 ]; then
    MEM_COLOR=$RED
elif [ $USAGE_PCT -gt 80 ]; then
    MEM_COLOR=$YELLOW
else
    MEM_COLOR=$GREEN
fi

echo -e "System Memory: ${MEM_COLOR}${USED_MEM}MB / ${TOTAL_MEM}MB (${USAGE_PCT}%)${NC}"

# Docker Container Resources
if docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep polygon &>/dev/null; then
    echo "Container Resources:"
    docker stats --no-stream --format "  {{.Name}}: CPU {{.CPUPerc}}, Memory {{.MemUsage}}" | grep polygon
fi

# Port Status
echo ""
echo -e "${CYAN}=== Port Status ===${NC}"
PORTS=("8547:Bor RPC" "8549:Bor WebSocket" "1317:Heimdall API" "6063:Bor Metrics" "26657:Heimdall RPC" "30307:Bor P2P")

for port_info in "${PORTS[@]}"; do
    IFS=':' read -r port desc <<< "$port_info"
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "Port $port ($desc): ${GREEN}Open${NC}"
    else
        echo -e "Port $port ($desc): ${RED}Closed${NC}"
    fi
done

# Connection Details
echo ""
echo -e "${CYAN}=== Connection Details ===${NC}"
echo "Bor RPC: http://localhost:8547"
echo "Bor WebSocket: ws://localhost:8549"
echo "Heimdall API: http://localhost:1317"
echo "Heimdall RPC: http://localhost:26657"
echo "Metrics: http://localhost:6063/metrics"
echo ""

# Management Commands
echo -e "${CYAN}=== Management Commands ===${NC}"
echo "View logs: docker logs polygon-bor -f"
echo "           docker logs polygon-heimdall -f"
echo "Stop:      docker stop polygon-bor polygon-heimdall"
echo "Start:     docker start polygon-heimdall && sleep 10 && docker start polygon-bor"
echo "Restart:   docker restart polygon-heimdall polygon-bor"
echo "Status:    $0"
echo ""

# MEV Configuration Summary
echo -e "${CYAN}=== MEV Configuration Summary ===${NC}"
echo "Archive Mode: Enabled (full historical data)"
echo "Cache Size: 8192MB (optimized for MEV operations)"
echo "Transaction Pool: 81,920 global slots, 128 account slots"
echo "Memory Limits: Bor 12GB, Heimdall 3GB (total 15GB allocation)"
echo "API Access: Full debug, trace, and admin APIs enabled"
echo "State Scheme: Hash (required for archive mode)"
echo ""

# Sync Progress Indicator
echo -e "${CYAN}=== Sync Progress ===${NC}"
if [ "$BLOCK_DECIMAL" -gt 0 ]; then
    # Rough estimate of Polygon mainnet block (as of 2024)
    ESTIMATED_LATEST=65000000
    PROGRESS=$((BLOCK_DECIMAL * 100 / ESTIMATED_LATEST))
    if [ $PROGRESS -gt 100 ]; then PROGRESS=100; fi
    
    echo "Current block: $BLOCK_DECIMAL"
    echo "Estimated progress: ~${PROGRESS}%"
else
    echo "Node is initializing..."
fi

echo ""
echo -e "${BLUE}For detailed health monitoring, run: ./polygon-health-check.sh${NC}"
echo -e "${BLUE}For memory monitoring, run: ./monitor-polygon-memory.sh -c${NC}"