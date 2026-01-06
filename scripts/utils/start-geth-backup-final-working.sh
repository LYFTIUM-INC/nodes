#!/bin/bash
# Production Geth Backup Node - Final Working Configuration
# Optimized for MEV operations with proper port allocation

set -euo pipefail

# Configuration optimized for system resources
DATADIR="/data/blockchain/storage/geth-backup"
LOG_DIR="/var/log/geth-backup"
JWT_SECRET="/data/blockchain/storage/jwt-secret-common.hex"

# Port allocation (sequential backup configuration per official standards)
HTTP_PORT=8547       # Geth backup RPC (sequential backup)
WS_PORT=8548         # Geth backup WebSocket (sequential backup)
AUTH_PORT=8553       # Geth backup AuthRPC (sequential backup)
METRICS_PORT=6061    # Geth backup metrics (sequential)
P2P_PORT=30311       # Geth backup P2P (avoid primary/erigon conflicts)

# Resource optimization
CACHE_SIZE=4096
MAX_PEERS=100

# MEV performance optimization
RPC_GAS_CAP=50000000
RPC_TX_FEE_CAP=100
TXPOOL_SLOTS=32
TXPOOL_GLOBAL_SLOTS=8192
TXPOOL_GLOBAL_QUEUE=4096
TXPOOL_ACCOUNT_QUEUE=64
TXPOOL_PRICE_LIMIT=1000000000
TXPOOL_PRICE_BUMP=10

echo "🚀 Starting Production Geth Backup Node - Final Working Version"
echo "📊 System Resources:"
echo "  • Cache: ${CACHE_SIZE}MB (optimized for 16-core AMD EPYC)"
echo "  • Max Peers: ${MAX_PEERS}"
echo "  • Ports: RPC=${HTTP_PORT}, WS=${WS_PORT}, AuthRPC=${AUTH_PORT}, P2P=${P2P_PORT}"
echo "🌐 MEV Endpoints:"
echo "  • RPC: http://localhost:${HTTP_PORT}"
echo "  • WebSocket: ws://localhost:${WS_PORT}"
echo "  • AuthRPC: http://localhost:${AUTH_PORT}"

# Create directories
mkdir -p "$DATADIR" "$LOG_DIR"

# Start Geth with working configuration
exec /usr/bin/geth \
    --datadir="$DATADIR" \
    --mainnet \
    --syncmode=snap \
    --gcmode=full \
    --cache="$CACHE_SIZE" \
    --maxpeers="$MAX_PEERS" \
    \
    --http \
    --http.addr=127.0.0.1 \
    --http.port="$HTTP_PORT" \
    --http.api=eth,net,web3,debug,txpool \
    --http.vhosts=localhost,127.0.0.1 \
    \
    --ws \
    --ws.addr=127.0.0.1 \
    --ws.port="$WS_PORT" \
    --ws.api=eth,net,web3,debug,txpool \
    --ws.origins=* \
    \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port="$AUTH_PORT" \
    --authrpc.vhosts=localhost,127.0.0.1 \
    \
    --port="$P2P_PORT" \
    --discovery.port="$P2P_PORT" \
    \
    --metrics \
    --metrics.addr=127.0.0.1 \
    --metrics.port="$METRICS_PORT" \
    \
    --txlookuplimit=0 \
    --verbosity=3 \
    --log.rotate \
    --log.maxage=7 \
    \
    --rpc.gascap="$RPC_GAS_CAP" \
    --rpc.txfeecap="$RPC_TX_FEE_CAP" \
    --rpc.allow-unprotected-txs=false \
    \
    --txpool.accountslots="$TXPOOL_SLOTS" \
    --txpool.globalslots="$TXPOOL_GLOBAL_SLOTS" \
    --txpool.accountqueue="$TXPOOL_ACCOUNT_QUEUE" \
    --txpool.globalqueue="$TXPOOL_GLOBAL_QUEUE" \
    --txpool.pricelimit="$TXPOOL_PRICE_LIMIT" \
    --txpool.pricebump="$TXPOOL_PRICE_BUMP" \
    \
    --nat=extip:51.159.82.58 \
    --authrpc.jwtsecret="$JWT_SECRET" \
    \
    2>&1 | tee -a "$LOG_DIR/geth-backup.log"
