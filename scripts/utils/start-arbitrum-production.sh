#!/bin/bash
# Arbitrum Node - Production Configuration
# Simplified approach that actually works

set -euo pipefail

# Configuration
DATA_DIR="/data/blockchain/storage/arbitrum"
LOG_DIR="$DATA_DIR/logs"
PARENT_CHAIN_URL="http://127.0.0.1:8545"
BEACON_URL="https://eth-beacon-mainnet.public.blastapi.io"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

echo "Starting Arbitrum node in production mode..."

# Remove any existing container
docker rm -f arbitrum-node 2>/dev/null || true

# Run Arbitrum node with proper permissions
exec docker run --rm \
    --name arbitrum-node \
    --network host \
    -v "$DATA_DIR":/arbitrum \
    --env DOCKER_CONTENT_TRUST=0 \
    offchainlabs/nitro-node:v3.6.8-d6c96a5 \
    --parent-chain.connection.url="$PARENT_CHAIN_URL" \
    --parent-chain.blob-client.beacon-url="$BEACON_URL" \
    --chain.id=42161 \
    --persistent.chain="/arbitrum" \
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
    --node.feed.input.url="wss://arb1.arbitrum.io/feed" \
    2>&1 | tee -a "$LOG_DIR/arbitrum.log"