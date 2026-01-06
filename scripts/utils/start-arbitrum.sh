#!/bin/bash
# Arbitrum Node Startup Script
# Optimized for MEV and high-performance trading

set -euo pipefail

# Configuration
DATA_DIR="/data/blockchain/storage/arbitrum"
LOG_DIR="$DATA_DIR/logs"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Kill any processes on our ports
fuser -k 8590/tcp 30307/tcp 2>/dev/null || true
sleep 2

echo "Starting Arbitrum node..."

# Start Arbitrum Nitro node
exec /usr/local/bin/arbitrum-node \
    --node.data-availability.enable \
    --core.cache.trie-time-limit=30m \
    --node.rpc.addr=0.0.0.0 \
    --node.rpc.port=8590 \
    --node.rpc.api=net,web3,eth,debug,arb \
    --node.rpc.cors-domain="*" \
    --node.ws.addr=0.0.0.0 \
    --node.ws.port=8590 \
    --node.ws.api=net,web3,eth,debug,arb \
    --node.ws.origins="*" \
    --persistent.chain=/usr/local/lib/arbitrum/arb1.json \
    --node.cache.archive \
    --core.checkpoint-gas-frequency=156250000 \
    --node.rpc.tx-aggregator.enable \
    --node.feed.output.enable \
    --node.feed.output.port=9642 \
    --node.p2p.host-port=30307 \
    --node.data-dir="$DATA_DIR" \
    --log-level=info \
    2>&1 | tee -a "$LOG_DIR/arbitrum-startup.log"