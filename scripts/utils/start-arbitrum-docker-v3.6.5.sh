#!/bin/bash
# Arbitrum Docker Startup Script - Updated v3.6.5
# Uses latest stable version with improved snapshot handling
set -euo pipefail

echo "Starting Arbitrum via Docker (v3.6.5)..."
source /opt/blockchain-data/.env/infura.env 2>/dev/null || true

mkdir -p /data/blockchain/storage/arbitrum

# Clean up any existing containers
docker rm -f arbitrum-node 2>/dev/null || true

# Pull latest image
echo "Pulling latest Arbitrum nitro image..."
docker pull --disable-content-trust offchainlabs/nitro-node:v3.6.5-89cef87

# Start with improved configuration
exec docker run --rm \
    --disable-content-trust \
    --name arbitrum-node \
    --network=host \
    --user 1001:1001 \
    -e HOME=/home/user \
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
    --http.port=8590 \
    --http.vhosts="*" \
    --ws.api=net,web3,eth,debug,arb \
    --ws.addr=127.0.0.1 \
    --ws.port=8591 \
    --ws.origins="*" \
    --metrics \
    --execution.caching.archive=false \
    --execution.rpc.gas-cap=0