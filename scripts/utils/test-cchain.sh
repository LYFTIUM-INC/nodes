#!/bin/bash

# Test Avalanche C-Chain Connectivity

echo "=== Testing Avalanche C-Chain Connectivity ==="
echo ""

# Define endpoints
HTTP_ENDPOINT="http://localhost:8557/ext/bc/C/rpc"
WS_ENDPOINT="ws://localhost:8557/ext/bc/C/ws"

# Test HTTP RPC
echo "1. Testing HTTP RPC Endpoint: $HTTP_ENDPOINT"
echo "----------------------------------------"

# Test eth_chainId
echo "Getting Chain ID..."
response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    -H "Content-Type: application/json" $HTTP_ENDPOINT)
if [ -n "$response" ] && [ "$response" != "404 page not found" ]; then
    chain_id=$(echo $response | jq -r '.result' 2>/dev/null)
    echo "✓ Chain ID: $chain_id ($(printf "%d" $chain_id))"
else
    echo "✗ Failed to get chain ID"
    exit 1
fi

# Test eth_blockNumber
echo ""
echo "Getting Latest Block Number..."
response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    -H "Content-Type: application/json" $HTTP_ENDPOINT)
if [ -n "$response" ]; then
    block_hex=$(echo $response | jq -r '.result' 2>/dev/null)
    block_dec=$((16#${block_hex#0x}))
    echo "✓ Latest Block: $block_dec"
else
    echo "✗ Failed to get block number"
fi

# Test eth_gasPrice
echo ""
echo "Getting Gas Price..."
response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}' \
    -H "Content-Type: application/json" $HTTP_ENDPOINT)
if [ -n "$response" ]; then
    gas_hex=$(echo $response | jq -r '.result' 2>/dev/null)
    gas_gwei=$(awk "BEGIN {printf \"%.2f\", $(printf "%d" $gas_hex)/1000000000}")
    echo "✓ Gas Price: $gas_gwei Gwei"
else
    echo "✗ Failed to get gas price"
fi

# Test net_version
echo ""
echo "Getting Network Version..."
response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
    -H "Content-Type: application/json" $HTTP_ENDPOINT)
if [ -n "$response" ]; then
    net_version=$(echo $response | jq -r '.result' 2>/dev/null)
    echo "✓ Network Version: $net_version"
else
    echo "✗ Failed to get network version"
fi

# Test eth_syncing
echo ""
echo "Checking Sync Status..."
response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    -H "Content-Type: application/json" $HTTP_ENDPOINT)
if [ -n "$response" ]; then
    sync_result=$(echo $response | jq -r '.result' 2>/dev/null)
    if [ "$sync_result" = "false" ]; then
        echo "✓ Node is fully synced"
    else
        echo "⏳ Node is syncing..."
        echo $response | jq '.result' 2>/dev/null
    fi
else
    echo "✗ Failed to get sync status"
fi

# Test getting a recent block
echo ""
echo "Getting Latest Block Details..."
response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
    -H "Content-Type: application/json" $HTTP_ENDPOINT)
if [ -n "$response" ]; then
    block=$(echo $response | jq '.result' 2>/dev/null)
    if [ "$block" != "null" ]; then
        echo "✓ Successfully retrieved block data"
        echo "  Hash: $(echo $block | jq -r '.hash')"
        echo "  Number: $(printf "%d" $(echo $block | jq -r '.number'))"
        echo "  Timestamp: $(date -d @$(printf "%d" $(echo $block | jq -r '.timestamp')))"
    else
        echo "✗ Failed to get block data"
    fi
else
    echo "✗ Failed to query block"
fi

# Test WebSocket endpoint
echo ""
echo "2. Testing WebSocket Endpoint: $WS_ENDPOINT"
echo "----------------------------------------"

# Simple WebSocket test using curl (checking if endpoint responds)
ws_test=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Upgrade: websocket" \
    -H "Connection: Upgrade" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    -H "Sec-WebSocket-Version: 13" \
    ${WS_ENDPOINT/ws:/http:})

if [ "$ws_test" = "101" ] || [ "$ws_test" = "426" ]; then
    echo "✓ WebSocket endpoint is responding"
else
    echo "✗ WebSocket endpoint is not responding (HTTP $ws_test)"
fi

echo ""
echo "=== Test Complete ==="
echo ""
echo "Connection Details:"
echo "  HTTP RPC: $HTTP_ENDPOINT"
echo "  WebSocket: $WS_ENDPOINT"
echo ""
echo "To use with web3 libraries:"
echo "  const web3 = new Web3('$HTTP_ENDPOINT');"
echo "  const web3ws = new Web3('$WS_ENDPOINT');"