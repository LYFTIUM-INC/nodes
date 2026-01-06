#!/bin/bash
# Arbitrum Node - Simple Working Configuration

set -euo pipefail

# Configuration
DATA_DIR="/data/blockchain/storage/arbitrum"
LOG_DIR="$DATA_DIR/logs"

# Ensure directories exist with correct permissions
mkdir -p "$DATA_DIR" "$LOG_DIR"
chmod 777 "$DATA_DIR"
chmod 777 "$LOG_DIR"

echo "Starting Arbitrum node..."

# Remove any existing container
docker rm -f arbitrum-node 2>/dev/null || true

# Run Arbitrum node with minimal configuration that works
exec docker run --rm \
    --name arbitrum-node \
    --network host \
    -v "$DATA_DIR":/data \
    --env DOCKER_CONTENT_TRUST=0 \
    offchainlabs/nitro-node:v3.6.8-d6c96a5 \
    --parent-chain.connection.url="http://127.0.0.1:8545" \
    --parent-chain.blob-client.beacon-url="https://eth-beacon-mainnet.public.blastapi.io" \
    --chain.id=42161 \
    --persistent.chain="/data" \
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