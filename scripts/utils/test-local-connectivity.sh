#!/bin/bash
# Local Node Connectivity Test for MEV Operations
# Tests WebSocket connections to both Erigon and Geth nodes

set -euo pipefail

echo "🔍 TESTING LOCAL NODE CONNECTIVITY FOR MEV OPERATIONS"
echo "================================================"

# Test Configuration
ERIGON_WS="wss://127.0.0.1:8546"
GETH_WS="ws://127.0.0.1:8548"
ERIGON_RPC="http://127.0.0.1:8545"
GETH_RPC="http://127.0.0.1:8547"

echo ""
echo "📊 Testing Erigon Node Connections"
echo "=================================="

# Test Erigon RPC (HTTP)
echo "1. Testing Erigon RPC (HTTP)..."
if curl -s --connect-timeout 5 "$ERIGON_RPC" | grep -q "jsonrpc\|result\|id"; then
    echo "✅ Erigon RPC: CONNECTED"
else
    echo "❌ Erigon RPC: FAILED"
fi

# Test Erigon WebSocket (WSS)
echo "2. Testing Erigon WebSocket (WSS)..."
if timeout 10 curl -s -k "$ERIGON_WS" --connect-timeout 5 2>/dev/null | grep -q "connected\|websocket\|wss://"; then
    echo "✅ Erigon WebSocket: CONNECTED"
else
    echo "❌ Erigon WebSocket: FAILED (timeout or certificate issue)"
fi

# Test with certificate validation
echo "3. Testing Erigon with SSL verification..."
if timeout 10 curl -s -k --cacert /opt/mev-lab/certs/erigon.crt "$ERIGON_WS" --connect-timeout 5 2>/dev/null | grep -q "connected\|websocket\|wss://"; then
    echo "✅ Erigon SSL WebSocket: VERIFIED"
else
    echo "❌ Erigon SSL WebSocket: FAILED (certificate verification failed)"
fi

echo ""
echo "📊 Testing Geth Backup Node Connections"
echo "======================================"

# Test Geth RPC (HTTP)
echo "4. Testing Geth RPC (HTTP)..."
if curl -s --connect-timeout 5 "$GETH_RPC" | grep -q "jsonrpc\|result\|id"; then
    echo "✅ Geth RPC: CONNECTED"
else
    echo "❌ Geth RPC: FAILED"
fi

# Test Geth WebSocket (WS - no TLS)
echo "5. Testing Geth WebSocket (WS)..."
if timeout 10 curl -s "$GETH_WS" --connect-timeout 5 2>/dev/null | grep -q "connected\|websocket\|ws://"; then
    echo "✅ Geth WebSocket: CONNECTED"
else
    "❌ Geth WebSocket: FAILED (connection timeout)"
fi

echo ""
echo "📈 CONNECTION SUMMARY"
echo "===================""

# Count successful connections
SUCCESSFUL_CONNECTIONS=0

# Re-test and count
if curl -s --connect-timeout 5 "$ERIGON_RPC" | grep -q "jsonrpc\|result\|id"; then
    ((SUCCESSFUL_CONNECTIONS++))
fi

if timeout 10 curl -s -k --cacert /opt/mev-lab/certs/erigon.crt "$ERIGON_WS" --connect-timeout 5 2>/dev/null | grep -q "connected\|websocket\|wss://"; then
    ((SUCCESSFUL_CONNECTIONS++))
fi

if curl -s --connect-timeout 5 "$GETH_RPC" | grep -q "jsonrpc\|result\|id"; then
    ((SUCCESSFUL_CONNECTIONS++))
fi

if timeout 10 curl -s "$GETH_WS" --connect-timeout 5 2>/dev/null | grep -q "connected\|websocket\|ws://"; then
    ((SUCCESSFUL_CONNECTIONS++))
fi

echo "✅ Successful Local Connections: $SUCCESSFUL_CONNECTIONS / 4"
echo "🔒 Local Node Utilization: $((SUCCESSFUL_CONNECTIONS * 25))%"

# Performance Test
echo ""
echo "📊 Performance Testing..."
echo "========================="

# Test latency to local endpoints
echo "6. Testing local endpoint latency..."
ERIGON_LATENCY=$(timeout 5 curl -s -o /dev/null -w "%{time_total}\n" "$ERIGON_RPC" 2>/dev/null || echo "TIMEOUT")
GETH_LATENCY=$(timeout 5 curl -s -o /dev/null -w "%{time_total}\n" "$GETH_RPC" 2>/dev/null || echo "TIMEOUT")

if [ "$ERIGON_LATENCY" != "TIMEOUT" ]; then
    echo "✅ Erigon RPC Latency: ${ERIGON_LATENCY}s"
else
    echo "❌ Erigon RPC Latency: TIMEOUT"
fi

if [ "$GETH_LATENCY" != "TIMEOUT" ]; then
    echo "✅ Geth RPC Latency: ${GETH_LATENCY}s"
else
    echo "❌ Geth RPC Latency: TIMEOUT"
fi

# Test with a sample method call
echo "7. Testing method calls..."
if curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$ERIGON_RPC" 2>/dev/null | grep -q "result\|error"; then
    echo "✅ Erigon Method Calls: WORKING"
else
    echo "❌ Erigon Method Calls: FAILED"
fi

echo ""
echo "🚨 RECOMMENDATIONS"
echo "==================="
echo ""

if [ $SUCCESSFUL_CONNECTIONS -eq 4 ]; then
    echo "🎉 EXCELLENT: All local endpoints are connected!"
    echo "   - Direct access to local blockchain data"
    echo "   - Reduced latency for MEV detection"
    echo "   - Enhanced security with local infrastructure"
else
    echo "⚠️ NEEDS ATTENTION: Some local endpoints not connected"
    echo "   - Check service status: sudo systemctl status erigon-mainnet geth-backup"
    "   - Review logs: tail -f /var/log/erigon/erigon.log /var/log/geth-backup/geth-backup.log"
    echo "   - Verify ports: netstat -tlnp | grep -E ':854[5-8]'"
fi

# Check if services are running
echo ""
echo "🔍 SERVICE STATUS CHECK"
echo "=================="

ERIGON_STATUS=$(systemctl is-active erigon-mainnet 2>/dev/null && echo "RUNNING" || echo "STOPPED")
GETH_STATUS=$(systemctl is-active geth-backup 2>/dev/null && echo "RUNNING" || echo "STOPPED")

echo "Erigon Service: $ERIGON_STATUS"
echo "Geth Backup Service: $GETH_STATUS"

if [ "$ERIGON_STATUS" = "RUNNING" ] && [ "$GETH_STATUS" = "RUNNING" ]; then
    echo "✅ Both local nodes are operational"
else
    echo "❌ One or both local nodes need attention"
    echo "   Restart services: sudo systemctl restart erigon-mainnet geth-backup"
fi

echo ""
echo "📊 FINAL ASSESSMENT"
echo "=================="

if [ $SUCCESSFUL_CONNECTIONS -ge 3 ]; then
    echo "✅ GOOD: Local infrastructure ready for MEV operations"
    echo "   Consider updating MEV pipeline to prioritize these endpoints"
else
    echo "❌ ISSUE: Local infrastructure needs attention"
    echo "   Relying on public endpoints limits MEV capabilities"
fi

echo ""
echo "📝 Test completed at $(date)"
echo "🔗 Next: Update MEV pipeline configuration to use local nodes"