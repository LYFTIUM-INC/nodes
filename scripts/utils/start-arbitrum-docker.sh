#!/bin/bash
# Arbitrum Docker Startup Script
set -euo pipefail

echo "Starting Arbitrum via Docker..."
source /opt/blockchain-data/.env/infura.env 2>/dev/null || true

mkdir -p /data/blockchain/storage/arbitrum

# Clean up any existing containers
docker rm -f arbitrum-node 2>/dev/null || true

exec docker run --rm \
    --name arbitrum-node \
    --network=host \
    -v /data/blockchain/storage/arbitrum:/home/user/.arbitrum \
    offchainlabs/nitro-node:v3.2.1-d81324d \
    --parent-chain.connection.url="https://ethereum-rpc.publicnode.com" \
    --parent-chain.blob-client.beacon-url="https://ethereum-beacon-api.publicnode.com" \
    --chain.id=42161 \
    --init.latest=pruned \
    --http.api=net,web3,eth,debug,arb \
    --http.corsdomain="http://localhost" \
    --http.addr=127.0.0.1 \
    --http.port=8590 \
    --http.vhosts="localhost" \
    --ws.api=net,web3,eth,debug,arb \
    --ws.addr=127.0.0.1 \
    --ws.port=8591 \
    --ws.origins="*" \
    --metrics
