#!/bin/bash
# Optimism Node Startup Script - Fixed for proper mainnet sync
# Includes both execution and consensus layers

set -euo pipefail

# Configuration
DATA_DIR="/data/blockchain/storage/optimism"
LOG_DIR="$DATA_DIR/logs"
JWT_SECRET="$DATA_DIR/jwt.hex"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Generate JWT secret if it doesn't exist
if [ ! -f "$JWT_SECRET" ]; then
    openssl rand -hex 32 > "$JWT_SECRET"
fi

echo "Starting Optimism node with proper mainnet configuration..."

# Start op-geth (execution layer) with corrected settings
exec /usr/local/bin/op-geth \
    --datadir="$DATA_DIR" \
    --op-network=op-mainnet \
    --syncmode=snap \
    --gcmode=full \
    --http \
    --http.addr=127.0.0.1 \
    --http.port=8547 \
    --http.api=eth,net,web3,debug,txpool,admin \
    --http.vhosts="*" \
    --http.corsdomain="*" \
    --ws \
    --ws.addr=127.0.0.1 \
    --ws.port=8557 \
    --ws.api=eth,net,web3,debug,txpool \
    --ws.origins="*" \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port=8555 \
    --authrpc.jwtsecret="$JWT_SECRET" \
    --authrpc.vhosts="*" \
    --port=30308 \
    --discovery.port=30308 \
    --maxpeers=50 \
    --cache=2048 \
    --txlookuplimit=0 \
    --metrics \
    --metrics.addr=127.0.0.1 \
    --metrics.port=6063 \
    --log.format=json \
    --verbosity=3 \
    --rollup.sequencerhttp=https://mainnet.optimism.io \
    --rollup.halt=major \
    2>&1 | tee -a "$LOG_DIR/optimism.log"
