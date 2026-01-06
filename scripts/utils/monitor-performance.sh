#!/bin/bash

# Solana Performance Monitoring Script
# Monitors health, resource usage, and key metrics

set -e

HEALTH_URL="http://localhost:8899/health"
RPC_URL="http://localhost:8899"

echo "🔍 Solana Node Performance Monitor"
echo "=================================="
echo "Timestamp: $(date)"
echo ""

# Health Check
echo "🏥 Health Status:"
if curl -sf "$HEALTH_URL" >/dev/null; then
    echo "✅ Health endpoint: RESPONSIVE"
else
    echo "❌ Health endpoint: UNRESPONSIVE"
    exit 1
fi

# Basic RPC Checks
echo ""
echo "🌐 RPC Status:"
SLOT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' "$RPC_URL" 2>/dev/null || echo "error")

if [[ "$SLOT_RESPONSE" == *"result"* ]]; then
    CURRENT_SLOT=$(echo "$SLOT_RESPONSE" | grep -o '"result":[0-9]*' | cut -d: -f2)
    echo "✅ Current slot: $CURRENT_SLOT"
else
    echo "❌ RPC calls failing"
fi

VERSION_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getVersion"}' "$RPC_URL" 2>/dev/null || echo "error")

if [[ "$VERSION_RESPONSE" == *"solana-core"* ]]; then
    VERSION=$(echo "$VERSION_RESPONSE" | grep -o '"solana-core":"[^"]*"' | cut -d'"' -f4)
    echo "✅ Solana version: $VERSION"
else
    echo "❌ Version check failed"
fi

# Container Resource Usage
echo ""
echo "💻 Resource Usage:"
if docker ps | grep -q solana-dev; then
    STATS=$(docker stats solana-dev --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}")
    echo "$STATS" | while IFS=$'\t' read -r cpu mem_usage mem_perc; do
        if [[ "$cpu" != "CPU %" ]]; then
            echo "📊 CPU: $cpu"
            echo "🧠 Memory: $mem_usage ($mem_perc)"
        fi
    done
else
    echo "❌ Solana container not found"
fi

# Performance Benchmarks
echo ""
echo "⚡ Performance Benchmarks:"

# Measure RPC response time
START_TIME=$(date +%s%N)
curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' "$RPC_URL" >/dev/null
END_TIME=$(date +%s%N)
RESPONSE_TIME_MS=$(( (END_TIME - START_TIME) / 1000000 ))

if [ $RESPONSE_TIME_MS -lt 100 ]; then
    echo "✅ RPC response time: ${RESPONSE_TIME_MS}ms (Excellent)"
elif [ $RESPONSE_TIME_MS -lt 500 ]; then
    echo "✅ RPC response time: ${RESPONSE_TIME_MS}ms (Good)"
elif [ $RESPONSE_TIME_MS -lt 2000 ]; then
    echo "⚠️  RPC response time: ${RESPONSE_TIME_MS}ms (Acceptable)"
else
    echo "❌ RPC response time: ${RESPONSE_TIME_MS}ms (Slow)"
fi

# Network connectivity check
echo ""
echo "🌍 Network Status:"
CONTAINER_LOGS=$(docker logs solana-dev --tail 10 2>/dev/null || echo "")
if echo "$CONTAINER_LOGS" | grep -q "gossip"; then
    echo "✅ Gossip network activity detected"
else
    echo "⚠️  Limited gossip activity (expected for test validator)"
fi

echo ""
echo "=================================="
echo "Monitor completed at $(date)"