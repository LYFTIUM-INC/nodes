#!/bin/bash

# Avalanche Node Diagnostic Script

echo "=== Avalanche Node Diagnostics ==="
echo "Timestamp: $(date)"
echo ""

# Check current process
echo "1. Current avalanchego process:"
ps aux | grep avalanchego | grep -v grep | head -1
echo ""

# Check port bindings
echo "2. Port bindings:"
netstat -tlnp 2>/dev/null | grep -E "9650|8557|9651" | head -10
echo ""

# Check disk space
echo "3. Disk space:"
df -h /data/blockchain/nodes/avalanche /root/.avalanchego 2>/dev/null | grep -v Filesystem
echo ""

# Test current instance on port 9650
echo "4. Testing current instance (port 9650):"
echo -n "  Node info: "
curl -s -X POST --data '{"jsonrpc":"2.0","method":"info.getNodeVersion","params":[],"id":1}' \
    -H "Content-Type: application/json" http://localhost:9650/ext/info >/dev/null 2>&1 && echo "OK" || echo "FAILED"

echo -n "  C-Chain bootstrap: "
result=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"info.isBootstrapped","params":{"chain":"C"},"id":1}' \
    -H "Content-Type: application/json" http://localhost:9650/ext/info 2>/dev/null | jq -r '.result.isBootstrapped' 2>/dev/null)
echo "${result:-FAILED}"

echo -n "  C-Chain RPC: "
curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    -H "Content-Type: application/json" http://localhost:9650/ext/bc/C/rpc >/dev/null 2>&1 && echo "OK" || echo "NOT AVAILABLE"

echo ""
echo "5. Configuration locations:"
echo "  Current config: $(ps aux | grep avalanchego | grep -v grep | grep -o '\--config-file=[^ ]*' | cut -d= -f2)"
echo "  New config: /data/blockchain/nodes/avalanche/config/config.json"

echo ""
echo "6. Recommendations:"
if [ -n "$(ps aux | grep 'avalanchego.*9650' | grep -v grep)" ]; then
    echo "  - Current avalanchego is using port 9650"
    echo "  - Our new configuration uses port 8557 to avoid conflicts"
    echo "  - You can either:"
    echo "    a) Stop the current instance and use our configuration"
    echo "    b) Start our instance on port 8557 (both can run simultaneously)"
fi

echo ""
echo "=== End Diagnostics ==="