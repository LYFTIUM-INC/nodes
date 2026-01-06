#!/bin/bash
# Base Node Startup Script - Fixed for proper mainnet sync
# Includes proper L2 configuration for Base mainnet

set -euo pipefail

# Configuration
DATA_DIR="/data/blockchain/storage/base"
LOG_DIR="$DATA_DIR/logs"
JWT_SECRET="$DATA_DIR/jwt.hex"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Generate JWT secret if it doesn't exist
if [ ! -f "$JWT_SECRET" ]; then
    openssl rand -hex 32 > "$JWT_SECRET"
fi

echo "Starting Base node with proper mainnet configuration..."

# Start op-geth (execution layer) with corrected settings for Base
exec /usr/local/bin/op-geth \
    --datadir="$DATA_DIR" \
    --op-network=base-mainnet \
    --syncmode=snap \
    --gcmode=full \
    --http \
    --http.addr=127.0.0.1 \
    --http.port=8548 \
    --http.api=eth,net,web3,debug,txpool,admin \
    --http.vhosts="*" \
    --http.corsdomain="*" \
    --ws \
    --ws.addr=127.0.0.1 \
    --ws.port=8558 \
    --ws.api=eth,net,web3,debug,txpool \
    --ws.origins="*" \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port=8562 \
    --authrpc.jwtsecret="$JWT_SECRET" \
    --authrpc.vhosts="*" \
    --port=30306 \
    --discovery.port=30306 \
    --maxpeers=50 \
    --cache=2048 \
    --txlookuplimit=0 \
    --metrics \
    --metrics.addr=127.0.0.1 \
    --metrics.port=6064 \
    --log.format=json \
    --verbosity=3 \
    --rollup.sequencerhttp=https://mainnet-sequencer.base.org \
    --rollup.halt=major \
    2>&1 | tee -a "$LOG_DIR/base.log"