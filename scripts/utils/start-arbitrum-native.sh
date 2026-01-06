#!/bin/bash
# Arbitrum Native Binary Startup Script
# Uses native arbitrum-node binary instead of Docker

set -euo pipefail

echo "Starting Arbitrum via native binary..."

# Configuration
DATA_DIR="/data/blockchain/storage/arbitrum"
LOG_DIR="$DATA_DIR/logs"
JWT_SECRET="$DATA_DIR/jwt.hex"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Generate JWT secret if it doesn't exist
if [ ! -f "$JWT_SECRET" ]; then
    openssl rand -hex 32 > "$JWT_SECRET"
    chmod 600 "$JWT_SECRET"
fi

# Fix permissions
chown -R lyftium:lyftium "$DATA_DIR"

echo "Starting Arbitrum node with native binary..."

# Start Arbitrum with native binary
exec /usr/local/bin/arbitrum-node \
    --parent-chain.connection.url="http://127.0.0.1:8545" \
    --parent-chain.blob-client.beacon-url="http://127.0.0.1:5052" \
    --chain.id=42161 \
    --node.data-dir="$DATA_DIR" \
    --auth.jwtsecret="$JWT_SECRET" \
    --http.api=net,web3,eth,debug,arb \
    --http.corsdomain="*" \
    --http.addr=127.0.0.1 \
    --http.port=8547 \
    --http.vhosts="*" \
    --ws.api=net,web3,eth,debug,arb \
    --ws.addr=127.0.0.1 \
    --ws.port=8557 \
    --ws.origins="*" \
    --metrics \
    --metrics.addr=127.0.0.1 \
    --metrics.port=6066 \
    --node.staker.enable=false \
    --execution.caching.archive=false \
    --execution.rpc.gas-cap=0 \
    --log-level=info \
    2>&1 | tee -a "$LOG_DIR/arbitrum.log"