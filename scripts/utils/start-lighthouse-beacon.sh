#!/bin/bash
# Lighthouse Beacon Node Startup Script - Fixed Version
# Alternative to docker-compose setup with permission fixes

# Configuration
LIGHTHOUSE_BIN="/home/lyftium/.cargo/bin/lighthouse"
DATA_DIR="/data/blockchain/storage/lighthouse"
JWT_SECRET="/data/blockchain/storage/jwt-secret-common.hex"
HTTP_PORT="5052"
DISCOVERY_PORT="9001"
LOG_DIR="/var/log/lighthouse"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check if lighthouse binary exists
if [ ! -f "$LIGHTHOUSE_BIN" ]; then
    error "Lighthouse binary not found at $LIGHTHOUSE_BIN"
    exit 1
fi

# Check if JWT secret exists
if [ ! -f "$JWT_SECRET" ]; then
    error "JWT secret not found at $JWT_SECRET"
    warn "Creating JWT secret..."
    mkdir -p "$(dirname "$JWT_SECRET")"
    openssl rand -hex 32 > "$JWT_SECRET"
    chmod 600 "$JWT_SECRET"
    log "✅ Created JWT secret at $JWT_SECRET"
fi

# Create data directory
mkdir -p "$DATA_DIR"
mkdir -p "$LOG_DIR"
log "✅ Data directory: $DATA_DIR"

# Check if execution node is running
if ! timeout 5 curl -s http://localhost:8545 > /dev/null; then
    warn "Execution node may not be running on localhost:8545"
fi

# Create log directory structure
mkdir -p "$LOG_DIR/beacon"
log "✅ Log directory: $LOG_DIR"

# Start Lighthouse Beacon Node
log "🚀 Starting Lighthouse Beacon Node..."

# Start Lighthouse Beacon Node with primary and backup execution clients
exec "$LIGHTHOUSE_BIN" bn \
    --network mainnet \
    --datadir "$DATA_DIR" \
    --http \
    --http-address 127.0.0.1 \
    --http-port $HTTP_PORT \
    --execution-endpoint http://127.0.0.1:8554 \
    --execution-jwt "$JWT_SECRET" \
    --discovery-port $DISCOVERY_PORT \
    --port $DISCOVERY_PORT \
    --target-peers 50 \
    --disable-upnp \
    --checkpoint-sync-url https://beaconstate.ethstaker.cc \
    --disable-deposit-contract-sync \
    --validator-monitor-auto \
  