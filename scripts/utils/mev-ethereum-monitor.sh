#!/bin/bash

# MEV Ethereum Node Monitor
# Critical monitoring for MEV operations

echo "=== MEV ETHEREUM NODE STATUS ==="
echo "Timestamp: $(date)"
echo ""

# Check Erigon sync status
echo "EXECUTION LAYER (Erigon):"
SYNC_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://localhost:8545)

if [ "$(echo $SYNC_STATUS | jq -r '.result')" == "false" ]; then
    echo "✅ Fully synced!"
    CURRENT_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 | jq -r '.result' | xargs printf "%d\n")
    echo "Current block: $CURRENT_BLOCK"
else
    CURRENT=$(echo $SYNC_STATUS | jq -r '.result.currentBlock' | xargs printf "%d\n")
    HIGHEST=$(echo $SYNC_STATUS | jq -r '.result.highestBlock' | xargs printf "%d\n")
    BEHIND=$((HIGHEST - CURRENT))
    PERCENT=$((CURRENT * 100 / HIGHEST))
    echo "⏳ Syncing: $PERCENT% complete"
    echo "Current block: $CURRENT"
    echo "Target block: $HIGHEST"
    echo "Blocks behind: $BEHIND"
fi

# Check peer count
PEERS=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://localhost:8545 | jq -r '.result' | xargs printf "%d\n")
echo "Connected peers: $PEERS"

echo ""
echo "CONSENSUS LAYER (Lighthouse):"
BEACON_STATUS=$(curl -s http://localhost:5052/eth/v1/node/syncing)
IS_SYNCING=$(echo $BEACON_STATUS | jq -r '.data.is_syncing')
EL_OFFLINE=$(echo $BEACON_STATUS | jq -r '.data.el_offline')

if [ "$IS_SYNCING" == "false" ]; then
    echo "✅ Fully synced!"
else
    echo "⏳ Syncing..."
    SYNC_DISTANCE=$(echo $BEACON_STATUS | jq -r '.data.sync_distance')
    echo "Slots behind: $SYNC_DISTANCE"
fi

echo "Execution layer connection: $([ "$EL_OFFLINE" == "false" ] && echo "✅ Connected" || echo "❌ Offline")"

# Check MEV readiness
echo ""
echo "MEV READINESS:"
if [ "$IS_SYNCING" == "false" ] && [ "$(echo $SYNC_STATUS | jq -r '.result')" == "false" ]; then
    echo "✅ READY FOR MEV OPERATIONS"
    
    # Check mempool
    PENDING_TXS=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' \
        http://localhost:8545 | jq -r '.result.pending' | xargs printf "%d\n" 2>/dev/null || echo "0")
    echo "Pending transactions: $PENDING_TXS"
    
    # Check gas price
    GAS_PRICE=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}' \
        http://localhost:8545 | jq -r '.result' | xargs printf "%d\n")
    GAS_GWEI=$((GAS_PRICE / 1000000000))
    echo "Current gas price: $GAS_GWEI Gwei"
else
    echo "⚠️  NOT READY - Node still syncing"
    if [ "$BEHIND" -gt 0 ]; then
        # Estimate sync time (assuming 1 block per second)
        EST_MINUTES=$((BEHIND / 60))
        EST_HOURS=$((EST_MINUTES / 60))
        echo "Estimated sync time: ~$EST_HOURS hours"
    fi
fi

# Check system resources
echo ""
echo "SYSTEM RESOURCES:"
MEM_USAGE=$(ps aux | grep erigon | grep -v grep | awk '{print $6/1024/1024}' | head -1)
CPU_USAGE=$(ps aux | grep erigon | grep -v grep | awk '{print $3}' | head -1)
echo "Erigon Memory: ${MEM_USAGE%.*} GB"
echo "Erigon CPU: $CPU_USAGE%"

# Check disk usage
DISK_USAGE=$(df -h /data/blockchain/storage | awk 'NR==2 {print $5}')
echo "Disk usage: $DISK_USAGE"

echo ""
echo "================================="