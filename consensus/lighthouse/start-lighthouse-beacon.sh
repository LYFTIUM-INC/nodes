#!/bin/bash
# Lighthouse Beacon Node Startup Script - Connected to Geth
# Updated 2025-01-06: Use Geth (8554) as execution client - running and stable

set -euo pipefail

# Basic configuration
NETWORK="mainnet"
DATA_DIR="/data/blockchain/nodes/consensus/lighthouse"
JWT_SECRET="/data/blockchain/storage/jwt-common/jwt-secret.hex"
GETH_ENDPOINT="http://127.0.0.1:8554"  # Geth Engine API (running)
P2P_PORT="9003"
HTTP_PORT="5052"

echo "🔥 Starting Lighthouse Beacon Node for ${NETWORK}"
echo "📁 Data Directory: ${DATA_DIR}"
echo "🔗 Execution Endpoint: Geth Engine API at ${GETH_ENDPOINT}"

# Verify JWT secret
if [[ ! -f "${JWT_SECRET}" ]]; then
    echo "❌ ERROR: JWT secret not found at ${JWT_SECRET}"
    exit 1
fi

echo "✅ JWT secret verified"

# Checkpoint sync enabled for fast sync
# This syncs from a recent checkpoint instead of genesis
echo "🚀 Starting Lighthouse beacon node with CHECKPOINT SYNC..."

# Start Lighthouse with Geth as execution client
exec /home/lyftium/.cargo/bin/lighthouse beacon_node \
    --network "${NETWORK}" \
    --datadir "${DATA_DIR}" \
    --execution-endpoint "${GETH_ENDPOINT}" \
    --execution-jwt="${JWT_SECRET}" \
    --port "${P2P_PORT}" \
    --http \
    --http-address 127.0.0.1 \
    --http-port "${HTTP_PORT}" \
    --http-allow-origin "*" \
    --checkpoint-sync-url https://sync.infradanko.org \
    --disable-deposit-contract-sync \
    --metrics \
    --metrics-port=5054
