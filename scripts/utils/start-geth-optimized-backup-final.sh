#!/bin/bash
# Production Geth Backup Node - Final Optimized Configuration
# Based on comprehensive documentation and system resource analysis
# Optimized for 16-core AMD EPYC with 62GB RAM, 463GB disk

set -euo pipefail

# Configuration optimized for system resources
DATADIR="/data/blockchain/storage/geth-backup"
LOG_DIR="/var/log/geth-backup"
JWT_SECRET="/data/blockchain/storage/erigon/jwt.hex"

# Port allocation (non-conflicting with Erigon)
HTTP_PORT=8547       # Geth backup RPC
WS_PORT=8548         # Geth backup WebSocket  
AUTH_PORT=8553       # Geth backup AuthRPC
METRICS_PORT=6068    # Geth backup metrics
P2P_PORT=30310       # Geth backup P2P

# Resource optimization for 16-core AMD EPYC
CACHE_SIZE=4096      # 4GB cache (of 35GB available)
MAX_PEERS=100        # Higher for sync performance
DISK_USAGE=200GB      # Conservative disk usage limit

# MEV performance optimization
RPC_GAS_CAP=25000000
RPC_TX_FEE_CAP=100
TXPOOL_SLOTS=32
TXPOOL_GLOBAL_SLOTS=8192
TXPOOL_GLOBAL_QUEUE=4096

echo "🚀 Starting Production Geth Backup Node - Final Version"
echo "📊 System Resources Utilization:" && echo "  • Cache: ${CACHE_SIZE}MB (11% of 35GB)" && echo "  • Max Peers: ${MAX_PEERS} (higher for sync performance)" && echo "  • Disk Usage: ${DISK_USAGE}GB (43% of 463GB)" && echo "  • CPU: Auto-optimizes for 16 cores AMD EPYC" && echo "  • Network: All required ports configured" && echo "🌐 Endpoints Ready for MEV Operations" && echo "  • RPC: http://localhost:${HTTP_PORT}" && echo "  • WebSocket: ws://localhost:${WS_PORT}" && echo "  • AuthRPC: http://localhost:${AUTH_PORT}"

# Create directories
mkdir -p "$DATADIR" "$LOG_DIR"

# Start Geth with snap sync (recommended for backup)
exec /usr/bin/geth \
    --datadir="$DATADIR" \
    --mainnet \
    --syncmode=snap \
    --gcmode=full \
    --cache="$CACHE_SIZE" \
    --maxpeers="$MAX_PEERS" \
    --datadir.limit="$DISK_USAGE" \
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
    --authrpc.jwtsecret="$JWT_SECRET" \
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
    --txpool.pricelimit=1000000000 \
    --txpool.pricebump=10 \
    \
    --nat=extip:51.159.82.58 \
    \
    2>&1 | tee -a "$LOG_DIR/geth-backup.log"
