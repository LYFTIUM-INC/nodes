#!/bin/bash
# Arbitrum Docker Startup Script - Direct execution without trust verification
set -euo pipefail

echo "Starting Arbitrum via Docker (Direct)..."
source /opt/blockchain-data/.env/infura.env 2>/dev/null || true

mkdir -p /data/blockchain/storage/arbitrum

# Clean up any existing containers
docker rm -f arbitrum-node 2>/dev/null || true

# Set environment to disable content trust
export DOCKER_CONTENT_TRUST=0

# Pull latest image without content trust
echo "Pulling latest Arbitrum nitro image..."
docker pull offchainlabs/nitro-node:v3.6.5-89cef87 || {
    echo "Failed to pull image, trying alternative version..."
    docker pull offchainlabs/nitro-node:latest
}

# Start with improved configuration
exec docker run --rm \
    --name arbitrum-node \
    --network=host \
    --user 1001:1001 \
    -e HOME=/home/user \
    -e DOCKER_CONTENT_TRUST=0 \
    -v /data/blockchain/storage/arbitrum:/home/user/.arbitrum \
    offchainlabs/nitro-node:v3.6.5-89cef87 \
    --parent-chain.connection.url="http://127.0.0.1:8545" \
    --parent-chain.blob-client.beacon-url="http://127.0.0.1:5052" \
    --auth.jwtsecret=/home/user/.arbitrum/jwtsecret \
    --chain.id=42161 \
    --init.force \
    --init.latest=pruned \
    --node.staker.enable=false \
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
    --execution.caching.archive=false \
    --execution.rpc.gas-cap=0