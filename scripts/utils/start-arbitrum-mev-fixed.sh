#!/bin/bash
# Arbitrum Node - MEV Fixed Configuration
# Fixes WebSocket port conflict for MEV Artemis integration

set -euo pipefail

# Configuration
DATA_DIR="/data/blockchain/storage/arbitrum"
LOG_DIR="$DATA_DIR/logs"
NITRO_DIR="$DATA_DIR/nitro"

# Ensure directories exist with correct permissions
echo "Setting up directories..."
sudo mkdir -p "$DATA_DIR" "$LOG_DIR"
sudo chown -R lyftium:lyftium "$DATA_DIR"
sudo chmod -R 755 "$DATA_DIR"

echo "Starting Arbitrum node with MEV-compatible configuration..."

# Remove any existing container
docker rm -f arbitrum-node 2>/dev/null || true

# Clean up any temporary files that might cause initialization errors
sudo rm -rf "$DATA_DIR/nitro/tmp" 2>/dev/null || true

# Run Arbitrum node with MEV-compatible ports
# HTTP: 8560 (available port for Arbitrum RPC)
# WebSocket: 8557 (expected by MEV Artemis and available)
docker run --rm \
    --name arbitrum-node \
    --network host \
    --user $(id -u lyftium):$(id -g lyftium) \
    -v "$DATA_DIR":/home/user/.arbitrum \
    --env DOCKER_CONTENT_TRUST=0 \
    --env HOME=/home/user \
    offchainlabs/nitro-node:v3.6.8-d6c96a5 \
    --parent-chain.connection.url="http://127.0.0.1:8545" \
    --parent-chain.blob-client.beacon-url="https://eth-beacon-mainnet.public.blastapi.io" \
    --chain.id=42161 \
    --persistent.chain="/home/user/.arbitrum" \
    --init.latest="pruned" \
    --http.addr=0.0.0.0 \
    --http.port=8560 \
    --http.api=net,web3,eth,arb \
    --http.corsdomain="*" \
    --http.vhosts="*" \
    --ws.addr=0.0.0.0 \
    --ws.port=8557 \
    --ws.api=net,web3,eth,arb \
    --ws.origins="*" \
    --metrics \
    --metrics-server.addr=0.0.0.0 \
    --metrics-server.port=6067 \
    --log-level=info \
    > "$LOG_DIR/arbitrum.log" 2>&1