#!/bin/bash
# Lighthouse Beacon Node Startup Script - Connected to Erigon
# Updated 2026-03-01: Best practices configuration per Lighthouse documentation

set -euo pipefail

# Basic configuration
NETWORK="mainnet"
DATA_DIR="/data/blockchain/nodes/consensus/lighthouse"
# Canonical JWT path per configs/systemd/README.md
JWT_SECRET="/data/blockchain/storage/jwt-common/jwt-secret.hex"
ERIGON_ENDPOINT="http://127.0.0.1:8552"  # Erigon Engine API
P2P_PORT="9003"
QUIC_PORT="9004"
HTTP_PORT="5052"
METRICS_PORT="5054"
LIGHTHOUSE_BIN="/usr/local/bin/lighthouse"

# External IP for NAT traversal
EXTERNAL_IP="51.159.82.58"

# Checkpoint sync URLs (primary + fallbacks per MEV_OPTIMIZATION_PROPOSALS - 5 URLs for recovery)
# Sources: eth-clients checkpoint list, MEV best practices
CHECKPOINT_URLS=(
    "https://sync.invis.tools"
    "https://mainnet.checkpoint.sigp.io"
    "https://beaconstate.ethstaker.cc"
    "https://checkpoint.beaconcha.in"
    "https://checkpoint.stakely.io"
)

# Custom graffiti (optional - identifies your blocks)
GRAFFITI="LYFTIUM-MEV"

# MEV-Boost builder endpoint
# Fallback: if relays fail, Lighthouse builds locally (--builder-fallback-*). Test: docs/runbooks/BUILDER_FALLBACK_VERIFICATION.md
BUILDER_ENDPOINT="http://127.0.0.1:18551"

# Pre-check: JWT secret must exist before any other operations (fail fast)
if [[ ! -f "${JWT_SECRET}" ]]; then
    echo "❌ ERROR: JWT secret not found at ${JWT_SECRET}"
    echo "   Create or symlink to canonical path. See configs/systemd/README.md"
    exit 1
fi

echo "🔥 Starting Lighthouse Beacon Node for ${NETWORK}"
echo "📁 Data Directory: ${DATA_DIR}"
echo "🔗 Execution Endpoint: Erigon Engine API at ${ERIGON_ENDPOINT}"
echo "🌐 External IP: ${EXTERNAL_IP}"
echo "✅ JWT secret verified at ${JWT_SECRET}"

# Clean up stale lock files (in case of previous unclean shutdown)
find "${DATA_DIR}/beacon" -name "LOCK" -delete 2>/dev/null || true

# Check if we already have a valid database
if [[ -f "${DATA_DIR}/beacon/chain_db/CURRENT" ]] && [[ -s "${DATA_DIR}/beacon/chain_db/CURRENT" ]]; then
    echo "📊 Existing database found, resuming sync..."
else
    echo "🔄 No valid database found, will attempt checkpoint sync..."
fi

# Start Lighthouse with optimized configuration
exec "${LIGHTHOUSE_BIN}" beacon_node \
    --network "${NETWORK}" \
    --datadir "${DATA_DIR}" \
    --execution-endpoint "${ERIGON_ENDPOINT}" \
    --execution-jwt="${JWT_SECRET}" \
    --port "${P2P_PORT}" \
    --quic-port "${QUIC_PORT}" \
    --enr-address "${EXTERNAL_IP}" \
    --enr-tcp-port "${P2P_PORT}" \
    --enr-udp-port "${P2P_PORT}" \
    --target-peers 80 \
    --http \
    --http-address 127.0.0.1 \
    --http-port "${HTTP_PORT}" \
    --metrics \
    --metrics-address 127.0.0.1 \
    --metrics-port "${METRICS_PORT}" \
    --genesis-backfill \
    $(printf -- '--checkpoint-sync-url %s ' "${CHECKPOINT_URLS[@]}") \
    --checkpoint-sync-url-timeout 300 \
    --disable-backfill-rate-limiting \
    --graffiti "${GRAFFITI}" \
    --auto-compact-db true \
    --builder "${BUILDER_ENDPOINT}" \
    --builder-fallback-epochs-since-finalization 3 \
    --builder-fallback-skips 3
