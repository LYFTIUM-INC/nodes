#!/bin/bash
# Polygon Secure Startup Script
# MEV-optimized configuration with security hardening

set -euo pipefail
set -x

# Configuration
DATA_DIR="/data/blockchain/storage/polygon"
LOG_DIR="$DATA_DIR/logs"
BOR_BINARY="/home/lyftium/go/bin/bor"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Kill any processes on our ports
fuser -k 8553/tcp 8554/tcp 30305/tcp 2>/dev/null || true
sleep 2

echo "Starting Polygon Bor node (secure)..."

# Check if binary exists
if [ ! -f "$BOR_BINARY" ]; then
    echo "Error: Bor binary not found at $BOR_BINARY"
    exit 1
fi

# Start Bor with secure configuration
exec "$BOR_BINARY" server \
    --datadir="$DATA_DIR" \
    --port=30305 \
    --http \
    --http.addr=127.0.0.1 \
    --http.port=8553 \
    --http.api=eth,net,web3,debug,txpool,bor \
    --http.vhosts=localhost,polygon.rpc.lyftium.com \
    --http.corsdomain=https://lyftium.com,https://polygon.rpc.lyftium.com \
    --ws \
    --ws.addr=127.0.0.1 \
    --ws.port=8554 \
    --ws.api=eth,net,web3,debug,txpool,bor \
    --ws.origins=https://lyftium.com,https://polygon.rpc.lyftium.com \
    --syncmode=full \
    --gcmode=full \
    --cache=1024 \
    --maxpeers=50 \
    --nat=extip:127.0.0.1 \
    --verbosity=3 \
    --bor.heimdall=http://localhost:1317 \
    --bor.heimdallgRPC=localhost:26656 \
    --bootnodes=enode://b8f1cc9c5d4403703fbf377116469667d2b1823c0daf16b7250aa576bacf399e42c3930ccfcb02c5df6879565a2b8931335565f0e8d3f8e72385ecf4a4bf160a@3.36.224.80:30303,enode://8729e0c825f3d9cad382555f3e46dcff21af323e89025a0e6312df541f4a9e73abfa562d64906f5e59c51fe6f0501b3e61b07979606c56329c020ed739910759@54.194.245.5:30303 \
    2>&1 | tee -a "$LOG_DIR/polygon.log"