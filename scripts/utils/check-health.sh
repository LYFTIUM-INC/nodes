#!/bin/bash

# Avalanche Node Health Check Script

echo "=== Avalanche Node Health Check ==="
echo "Timestamp: $(date)"
echo ""

# Check if process is running
if pgrep -f avalanchego > /dev/null; then
    echo "✓ Avalanchego process is running"
    echo "  PID: $(pgrep -f avalanchego)"
else
    echo "✗ Avalanchego process is NOT running"
    exit 1
fi

# Check node version
echo ""
echo "Node Version:"
curl -s -X POST --data '{"jsonrpc":"2.0","method":"info.getNodeVersion","params":[],"id":1}' \
    -H "Content-Type: application/json" http://localhost:8557/ext/info | jq '.result'

# Check if node is healthy
echo ""
echo "Health Status:"
curl -s -X POST --data '{"jsonrpc":"2.0","method":"health.health","params":[],"id":1}' \
    -H "Content-Type: application/json" http://localhost:8557/ext/health | jq '.result.healthy'

# Check bootstrap status for all chains
echo ""
echo "Bootstrap Status:"
for chain in P X C; do
    echo -n "  $chain-Chain: "
    curl -s -X POST --data "{\"jsonrpc\":\"2.0\",\"method\":\"info.isBootstrapped\",\"params\":{\"chain\":\"$chain\"},\"id\":1}" \
        -H "Content-Type: application/json" http://localhost:8557/ext/info | jq -r '.result.isBootstrapped'
done

# Check C-Chain specific
echo ""
echo "C-Chain Status:"
response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    -H "Content-Type: application/json" http://localhost:8557/ext/bc/C/rpc 2>/dev/null)

if [ -n "$response" ] && [ "$response" != "404 page not found" ]; then
    echo "  ✓ C-Chain RPC is responding"
    echo "  Chain ID: $(echo $response | jq -r '.result' 2>/dev/null || echo 'Not available')"
    
    # Get latest block
    block_response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        -H "Content-Type: application/json" http://localhost:8557/ext/bc/C/rpc 2>/dev/null)
    
    if [ -n "$block_response" ]; then
        block_hex=$(echo $block_response | jq -r '.result' 2>/dev/null || echo "0x0")
        block_dec=$((16#${block_hex#0x}))
        echo "  Latest Block: $block_dec"
    fi
else
    echo "  ✗ C-Chain RPC is NOT responding yet"
    echo "  The node may still be bootstrapping..."
fi

# Check peer count
echo ""
echo "Network Peers:"
curl -s -X POST --data '{"jsonrpc":"2.0","method":"info.peers","params":[],"id":1}' \
    -H "Content-Type: application/json" http://localhost:8557/ext/info | jq '.result.numPeers // 0'

echo ""
echo "=== End Health Check ==="