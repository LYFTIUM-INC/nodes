#!/bin/bash
# Lighthouse beacon node startup script for mainnet (Fixed)

set -euo pipefail

# Configuration
DATADIR="/data/blockchain/storage/lighthouse"
JWT_SECRET="/data/blockchain/storage/jwt-secret-common.hex"
LOG_DIR="/data/blockchain/nodes/logs"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Ensure directories exist
mkdir -p "$DATADIR" "$LOG_DIR"

# Check if JWT secret exists
if [[ ! -f "$JWT_SECRET" ]]; then
    error "JWT secret not found at $JWT_SECRET"
    exit 1
fi

log "Starting Lighthouse beacon node for mainnet..."
log "Data directory: $DATADIR"
log "Execution endpoint: http://localhost:8552"

# Start Lighthouse beacon node (minimal arguments for stability)
exec /home/lyftium/.cargo/bin/lighthouse beacon_node \
    --network mainnet \
    --datadir "$DATADIR" \
    --http \
    --http-address 127.0.0.1 \
    --http-port 5052 \
    --execution-endpoint http://127.0.0.1:8551 \
    --execution-endpoint http://127.0.0.1:8553 \
    --execution-jwt "$JWT_SECRET" \
    --checkpoint-sync-url https://mainnet.checkpoint.sigp.io \
    --disable-deposit-contract-sync \
    --disable-upnp \
    --target-peers 10 \
    --state-cache-size 2 \
    --slots-per-restore-point 2048 \
    --historic-state-cache-size 1 \
    --disable-log-timestamp \
    --debug-level error \
    --logfile "$LOG_DIR/lighthouse-beacon.log"
