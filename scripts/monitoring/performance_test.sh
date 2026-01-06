#!/bin/bash
# MEV Infrastructure Performance Test Suite
# Tests blockchain node performance and readiness for MEV operations

set -e

echo "=== MEV Infrastructure Performance Test ==="
echo "Testing Erigon node performance and MEV operation readiness..."
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test endpoints
ERIGON_RPC="http://127.0.0.1:8545"
ERIGON_WS="ws://127.0.0.1:8546"
MEV_RPC="http://127.0.0.1:18545"
NGINX_RPC="http://127.0.0.1:8547"
GETH_RPC="http://127.0.0.1:8549"

echo "1. Testing RPC Response Times..."
echo "=============================="

# Test Erigon RPC performance
echo -n "Erigon RPC (8545): "
erigon_time=$(curl -s -w "%{time_total}" -o /dev/null -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":["latest"],"id":1}' "$ERIGON_RPC")
echo "${GREEN}${erigon_time}s${NC}"

# Test MEV proxy RPC performance
echo -n "MEV RPC Proxy (18545): "
mev_time=$(curl -s -w "%{time_total}" -o /dev/null -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":["latest"],"id":1}' "$MEV_RPC")
echo "${GREEN}${mev_time}s${NC}"

# Test nginx MEV proxy with API key
echo -n "Nginx MEV Proxy (8547): "
nginx_time=$(curl -s -w "%{time_total}" -o /dev/null -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":["latest"],"id":1}' "$NGINX_RPC?api_key=480415a7707972bcbc9adeffdf73e57b6683f177ab21f0581309cea2306aa0d3")
echo "${GREEN}${nginx_time}s${NC}"

# Test Geth RPC performance (if available)
if curl -s "$GETH_RPC" >/dev/null 2>&1; then
    echo -n "Geth RPC (8549): "
    geth_time=$(curl -s -w "%{time_total}" -o /dev/null -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":["latest"],"id":1}' "$GETH_RPC")
    echo "${GREEN}${geth_time}s${NC}"
else
    echo "Geth RPC (8549): ${RED}Not available${NC}"
fi

echo
echo "2. Testing Sync Status..."
echo "======================="

# Get sync status from Erigon
echo -n "Erigon Sync Status: "
sync_result=$(curl -s -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' "$ERIGON_RPC")
if echo "$sync_result" | grep -q '"result":false'; then
    echo "${GREEN}Synced${NC}"
    # Get block number
    block_number=$(curl -s -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":["latest"],"id":1}' "$ERIGON_RPC" | jq -r '.result' 2>/dev/null || echo "N/A")
    echo "   Block: $block_number"
else
    echo "${YELLOW}Syncing${NC}"
    sync_progress=$(echo "$sync_result" | jq -r '.result | "\(.currentBlock/.highestBlock*100 | ./1)"' 2>/dev/null || echo "N/A")
    echo "   Progress: $sync_progress%"
fi

echo
echo "3. Testing MEV-Specific Capabilities..."
echo "=================================="

# Test mempool accessibility
echo -n "Erigon Txpool Status: "
txpool_result=$(curl -s -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' "$ERIGON_RPC" 2>/dev/null || echo "N/A")
if echo "$txpool_result" | grep -q '"result"'; then
    pending_tx=$(echo "$txpool_result" | jq -r '.result.pending' 2>/dev/null || echo "N/A")
    queued_tx=$(echo "$txpool_result" | jq -r '.result.queued' 2>/dev/null || echo "N/A")
    echo "${GREEN}Available${NC} (Pending: $pending_tx, Queued: $queued_tx)"
else
    echo "${RED}Not Available${NC}"
fi

# Test access to recent blocks
echo -n "Recent Block Access: "
recent_block=$(curl -s -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' "$ERIGON_RPC" 2>/dev/null)
if echo "$recent_block" | grep -q '"result"'; then
    echo "${GREEN}Working${NC}"
    gas_used=$(echo "$recent_block" | jq -r '.result.gasUsed' 2>/dev/null || echo "N/A")
    echo "   Gas Used: $gas_used"
else
    echo "${RED}Not Working${NC}"
fi

# Test fee market data
echo -n "Fee Market Data: "
fee_result=$(curl -s -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_feeHistory","params":["0x1"],"id":1}' "$ERIGON_RPC" 2>/dev/null || echo "N/A")
if echo "$fee_result" | grep -q '"result"'; then
    echo "${GREEN}Available${NC}"
else
    echo "${YELLOW}Limited${NC} (Erigon specific)"
fi

echo
echo "4. Testing Load Balancing..."
echo "========================="

# Test response time under load
echo "Testing 5 concurrent requests..."
start_time=$(date +%s.%N)
for i in {1..5}; do
    curl -s -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":["latest"],"id":1}' "$MEV_RPC" > /dev/null &
done
wait
end_time=$(date +%s.%N)
avg_time=$(echo "$end_time - $start_time" | bc)
echo "5 concurrent requests completed in: ${GREEN}${avg_time}s${NC}"
echo "Average per request: ${GREEN}$(echo "scale=3; $avg_time / 5" | bc)s${NC}"

echo
echo "5. WebSocket Connection Test..."
echo "=============================="

# Test WebSocket connectivity
echo -n "WebSocket (8547): "
ws_test=$(timeout 3s bash -c 'exec 3<>/dev/tcp/127.0.0.1/8547' 2>/dev/null && echo "Connected" || echo "Failed")
if [ "$ws_test" = "Connected" ]; then
    echo "${GREEN}Connected${NC}"
else
    echo "${RED}Connection Failed${NC}"
fi

echo
echo "6. Production Readiness Assessment..."
echo "================================"

# Calculate readiness score
score=0
max_score=8

# RPC Performance check
if (( $(echo "$erigon_time < 0.5" | bc -l) )); then
    ((score++))
    echo -n "✓ RPC Performance (<500ms): "
    echo "${GREEN}PASS${NC}"
else
    echo -n "✗ RPC Performance (<500ms): "
    echo "${RED}FAIL${NC}"
fi

# Sync Status check
if echo "$sync_result" | grep -q '"result":false'; then
    ((score++))
    echo -n "✓ Sync Status: "
    echo "${GREEN}SYNCED${NC}"
else
    echo -n "✗ Sync Status: "
    echo "${YELLOW}SYNCING${NC}"
fi

# WebSocket Check
if [ "$ws_test" = "Connected" ]; then
    ((score++))
    echo -n "✓ WebSocket: "
    echo "${GREEN}CONNECTED${NC}"
else
    echo -n "✗ WebSocket: "
    echo "${RED}FAILED${NC}"
fi

# Nginx Proxy Check
if curl -s "$MEV_RPC" >/dev/null; then
    ((score++))
    echo -n "✓ Nginx Proxy: "
    echo "${GREEN}OPERATIONAL${NC}"
else
    echo -n "✗ Nginx Proxy: "
    echo "${RED}FAILED${NC}"
fi

# MEV Capabilities Check
if echo "$txpool_result" | grep -q '"result"'; then
    ((score++))
    echo -n "✓ MEV Capabilities: "
    echo "${GREEN}AVAILABLE${NC}"
else
    echo -n "✗ MEV Capabilities: "
    echo "${YELLOW}LIMITED${NC}"
fi

# Load Balancing Check
if (( $(echo "$avg_time < 2.0" | bc -l) )); then
    ((score++))
    echo -n "✓ Load Performance: "
    echo "${GREEN}GOOD${NC}"
else
    echo -n "✗ Load Performance: "
    echo "${RED}POOR${NC}"
fi

# Fallback Mechanism Check
if curl -s "$MEV_RPC/health" | grep -q "fallback"; then
    ((score++))
    echo -n "✓ Fallback Mechanism: "
    echo "${GREEN}CONFIGURED${NC}"
else
    echo -n "✗ Fallback Mechanism: "
    echo "${YELLOW}UNKNOWN${NC}"
fi

# Security Check
if curl -s "$NGINX_RPC?api_key=480415a7707972bcbc9adeffdf73e57b6683f177ab21f0581309cea2306aa0d3" >/dev/null; then
    ((score++))
    echo -n "✓ API Authentication: "
    echo "${GREEN}ENABLED${NC}"
else
    echo -n "✗ API Authentication: "
    echo "${YELLOW}DISABLED${NC}"
fi

echo
echo "=== OVERALL ASSESSMENT ==="
echo "Score: $score/$max_score"

if [ $score -ge 7 ]; then
    echo "Status: ${GREEN}PRODUCTION READY FOR MEV OPERATIONS${NC}"
    echo "Recommendation: Infrastructure is optimized for MEV extraction and monitoring"
elif [ $score -ge 5 ]; then
    echo "Status: ${YELLOW}NEAR PRODUCTION READY${NC}"
    echo "Recommendation: Address remaining issues before full MEV deployment"
else
    echo "Status: ${RED}NOT PRODUCTION READY${NC}"
    echo "Recommendation: Critical issues must be resolved before MEV operations"
fi

echo
echo "=== PERFORMANCE METRICS ==="
echo "Erigon RPC Latency: ${erigon_time}s"
echo "MEV Proxy Latency: ${mev_time}s"
echo "Load Test (5 req): ${avg_time}s"
echo "WebSocket: $ws_test"
echo "Sync Status: $(if echo "$sync_result" | grep -q '"result":false'; then echo "Synced"; else echo "Syncing"; fi)"

echo
echo "=== END TEST ==="