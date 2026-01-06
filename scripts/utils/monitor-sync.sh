#!/bin/bash
# Erigon Sync Progress Monitor
# Tracks both execution and consensus layer sync status

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

while true; do
    clear
    echo -e "${BLUE}=== Erigon Sync Monitor ===${NC}"
    echo "Time: $(date)"
    echo ""
    
    # Service status
    SERVICE_STATUS=$(systemctl is-active erigon.service)
    if [ "$SERVICE_STATUS" = "active" ]; then
        echo -e "Service Status: ${GREEN}$SERVICE_STATUS${NC}"
    else
        echo -e "Service Status: ${RED}$SERVICE_STATUS${NC}"
    fi
    
    # Get latest execution block from logs
    EXEC_BLOCK=$(grep -E "blk=" /data/blockchain/storage/erigon-fresh/logs/erigon.log 2>/dev/null | tail -1 | grep -oP 'blk=\K[0-9]+' || echo "0")
    echo -e "${YELLOW}Execution Layer:${NC}"
    echo "  Latest Block: $EXEC_BLOCK"
    
    # Get current stage
    CURRENT_STAGE=$(grep -E "\[[0-9]/[0-9]" /data/blockchain/storage/erigon-fresh/logs/erigon.log 2>/dev/null | tail -1 | grep -oP '\[\K[0-9]/[0-9]' || echo "Unknown")
    echo "  Current Stage: $CURRENT_STAGE"
    
    # Get Caplin (beacon chain) progress
    echo -e "${YELLOW}Beacon Chain (Caplin):${NC}"
    CAPLIN_PROGRESS=$(grep -E "Caplin.*progress=" /data/blockchain/storage/erigon-fresh/logs/erigon.log 2>/dev/null | tail -1 | grep -oP 'progress=\K[0-9]+' || echo "0")
    CAPLIN_DISTANCE=$(grep -E "distance-from-chain-tip=" /data/blockchain/storage/erigon-fresh/logs/erigon.log 2>/dev/null | tail -1 | grep -oP 'distance-from-chain-tip=\K[^s]+' || echo "Unknown")
    echo "  Progress: $CAPLIN_PROGRESS"
    echo "  Distance from tip: $CAPLIN_DISTANCE"
    
    # Peer count
    PEER_COUNT=$(grep -E "peers=[0-9]+" /data/blockchain/storage/erigon-fresh/logs/erigon.log 2>/dev/null | tail -1 | grep -oP 'peers=\K[0-9]+' || echo "0")
    echo -e "${YELLOW}Network:${NC}"
    echo "  Connected Peers: $PEER_COUNT"
    
    # Memory usage
    MEM_INFO=$(systemctl status erigon.service --no-pager 2>/dev/null | grep "Memory:" | head -1 | sed 's/^[[:space:]]*//')
    echo -e "${YELLOW}Resources:${NC}"
    echo "  $MEM_INFO"
    
    # RPC check
    echo -e "${YELLOW}RPC Status:${NC}"
    RPC_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null | jq -r '.result' 2>/dev/null || echo "0x0")
    RPC_BLOCK_DEC=$((RPC_BLOCK))
    if [ "$RPC_BLOCK_DEC" -gt 0 ]; then
        echo -e "  RPC Block: ${GREEN}$RPC_BLOCK_DEC${NC}"
    else
        echo -e "  RPC Block: ${RED}$RPC_BLOCK_DEC (Syncing...)${NC}"
    fi
    
    # Check for recent errors
    ERROR_COUNT=$(tail -1000 /data/blockchain/storage/erigon-fresh/logs/erigon.log 2>/dev/null | grep -c "ERROR" || echo "0")
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo -e "${RED}Recent Errors: $ERROR_COUNT${NC}"
    fi
    
    echo ""
    echo "Press Ctrl+C to exit. Refreshing in 30 seconds..."
    sleep 30
done