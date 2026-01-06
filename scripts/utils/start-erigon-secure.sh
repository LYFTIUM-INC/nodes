#!/bin/bash
# Secure Erigon startup script for MEV operations
# This script starts Erigon with localhost-only RPC binding for security

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Configuration
DATADIR="/data/blockchain/storage/erigon"
LOG_DIR="/data/blockchain/nodes/logs"
JWT_SECRET="/data/blockchain/storage/erigon/jwt.hex"

# Ensure directories exist
mkdir -p "$DATADIR" "$LOG_DIR"

# Check if JWT secret exists
if [[ ! -f "$JWT_SECRET" ]]; then
    error "JWT secret not found at $JWT_SECRET"
    exit 1
fi

log "🚀 Starting Erigon (secure configuration)..."

# Check if already running
if pgrep -f "erigon --datadir" >/dev/null; then
    error "Erigon is already running!"
    log "Stop it first with: sudo pkill -f 'erigon --datadir'"
    exit 1
fi

# Start Erigon with secure configuration
exec /data/blockchain/nodes/ethereum/erigon/bin/erigon \
    --datadir="$DATADIR" \
    --chain=mainnet \
    --prune.mode=full \
    --http \
    --http.addr=127.0.0.1 \
    --http.port=8545 \
    --http.vhosts="*" \
    --http.api=eth,net,web3,txpool,erigon,debug,trace,engine \
    --ws \
    --ws.port=8546 \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port=8551 \
    --authrpc.jwtsecret="$JWT_SECRET" \
    --authrpc.vhosts="*" \
    --port=30309 \
    --p2p.protocol=68,67 \
    --private.api.addr=127.0.0.1:9091 \
    --maxpeers=50 \
    --txpool.accountslots=64 \
    --txpool.globalslots=50000 \
    --txpool.globalqueue=50000 \
    --txpool.pricelimit=1 \
    --txpool.pricebump=1 \
    --rpc.gascap=50000000 \
    --rpc.txfeecap=0 \
    --rpc.allow-unprotected-txs \
    --log.console.verbosity=info \
    --log.dir.path="$LOG_DIR" \
    --log.dir.verbosity=info \
    --metrics \
    --metrics.addr=127.0.0.1 \
    --metrics.port=6062 \
    --externalcl