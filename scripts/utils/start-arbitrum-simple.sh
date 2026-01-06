#!/bin/bash
# Arbitrum Node - Simple Working Configuration
# Based on Official Arbitrum Documentation

set -euo pipefail

# Configuration
DATA_DIR="/data/blockchain/storage/arbitrum"
LOG_DIR="$DATA_DIR/logs"
PARENT_CHAIN_URL="http://127.0.0.1:8545"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Fix permissions
chown -R lyftium:lyftium "$DATA_DIR"

echo "Starting Arbitrum node with simplified configuration..."

# Remove any existing container
docker rm -f arbitrum-node 2>/dev/null || true

# Run Arbitrum node with minimal configuration
exec docker run --rm \
    --name arbitrum-node \
    --network host \
    -v "$DATA_DIR":/home/user/.arbitrum \
    -u "1001:1001" \
    --env DOCKER_CONTENT_TRUST=0 \
    offchainlabs/nitro-node:v3.6.8-d6c96a5 \
    --parent-chain.connection.url="$PARENT_CHAIN_URL" \
    --chain.id=42161 \
    --http.addr=0.0.0.0 \
    --http.port=8547 \
    --http.api=net,web3,eth,arb \
    --http.corsdomain="*" \
    --http.vhosts="*" \
    --ws.addr=0.0.0.0 \
    --ws.port=8557 \
    --ws.api=net,web3,eth,arb \
    --ws.origins="*" \
    --metrics \
    --metrics-server.addr=0.0.0.0 \
    --metrics-server.port=6066 \
    --log-level=info \
    2>&1 | tee -a "$LOG_DIR/arbitrum.log"