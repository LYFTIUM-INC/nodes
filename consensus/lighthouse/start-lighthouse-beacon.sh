#!/bin/bash
# Lighthouse Beacon Node Startup Script - Connected to Erigon
# Updated 2026-01-12: Reconfigured to use Erigon execution client

set -euo pipefail

# Basic configuration
NETWORK="mainnet"
DATA_DIR="/data/blockchain/nodes/consensus/lighthouse"
JWT_SECRET="/data/blockchain/storage/erigon/jwt.hex"
ERIGON_ENDPOINT="http://127.0.0.1:8552"  # Erigon Engine API
P2P_PORT="9003"
HTTP_PORT="5052"

echo "🔥 Starting Lighthouse Beacon Node for ${NETWORK}"
echo "📁 Data Directory: ${DATA_DIR}"
echo "🔗 Execution Endpoint: Erigon Engine API at ${ERIGON_ENDPOINT}"
echo "⚠️  CHECKPOINT SYNC DISABLED - syncing from genesis"

# Verify JWT secret
if [[ ! -f "${JWT_SECRET}" ]]; then
    echo "❌ ERROR: JWT secret not found at ${JWT_SECRET}"
    exit 1
fi

echo "✅ JWT secret verified"

# Start Lighthouse with Erigon as execution client
exec /home/lyftium/.cargo/bin/lighthouse beacon_node \
    --network "${NETWORK}" \
    --datadir "${DATA_DIR}" \
    --execution-endpoint "${ERIGON_ENDPOINT}" \
    --execution-jwt="${JWT_SECRET}" \
    --port "${P2P_PORT}" \
    --http \
    --http-address 127.0.0.1 \
    --http-port "${HTTP_PORT}" \
    --http-allow-origin "*" \
    --allow-insecure-genesis-sync \
    --disable-deposit-contract-sync \
    --metrics \
    --metrics-port=5054
