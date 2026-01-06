#!/bin/bash
# Production Geth Backup Node - MEV Optimized Configuration v2.0
# Based on Geth v1.16.4 documentation and system resource analysis
# Optimized for 16-core AMD EPYC with 35GB available memory

set -euo pipefail

# Configuration optimized for system resources
DATADIR="/data/blockchain/storage/geth-backup"
LOG_DIR="/var/log/geth-backup"
JWT_SECRET="/data/blockchain/storage/erigon/jwt.hex"

# Port allocation (non-conflicting with Erigon)
HTTP_PORT=8547       # Geth backup RPC (different from Erigon 8545)
WS_PORT=8548         # Geth backup WebSocket (different from Erigon 8546)
AUTH_PORT=8553       # Geth backup AuthRPC (different from Erigon 8552)
METRICS_PORT=6068    # Geth backup metrics
P2P_PORT=30310       # Geth backup P2P (different from Erigon 30303)

# Resource optimization based on 16-core AMD EPYC
CACHE_SIZE=2048      # 2GB cache (of 35GB available)
MAX_PEERS=50         # Conservative for backup role (uses default 50)
# CONCURRENCY REMOVED - Geth v1.16.4 auto-optimizes for available cores

echo "🚀 Starting Production Geth Backup Node v2.0"
echo "📊 Resource Optimization:"
echo "   • Cache: ${CACHE_SIZE}MB (2GB of 35GB available)"
echo "   • Max Peers: ${MAX_PEERS} (default for light client)"
echo "   • CPU: Auto-optimizes for 16 cores AMD EPYC"
echo "   • Memory: Conservative allocation for backup role"
echo "🌐 Endpoints:"
echo "   • RPC: http://localhost:${HTTP_PORT}"
echo "   • WebSocket: ws://localhost:${WS_PORT}"
echo "   • AuthRPC: http://localhost:${AUTH_PORT}"
echo "📈 MEV Features:"
echo "   • Real-time transaction monitoring"
echo "   • WebSocket subscriptions"
echo "   • Low-latency RPC responses"
echo "   • TxPool optimization for arbitrage"

# Create directories
mkdir -p "$DATADIR" "$LOG_DIR"

# Start Geth with MEV optimization (v1.16.4 compatible)
exec /usr/bin/geth \
    --datadir="$DATADIR" \
    --mainnet \
    --syncmode=light \
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
    --rpc.gascap=50000000 \
    --rpc.txfeecap=100 \
    --rpc.allow-unprotected-txs=false \
    \
    --txpool.accountslots=16 \
    --txpool.globalslots=2048 \
    --txpool.accountqueue=64 \
    --txpool.globalqueue=1024 \
    --txpool.pricelimit=1000000000 \
    --txpool.pricebump=10 \
    \
    --nat=extip:51.159.82.58 \
    \
    --bootnodes=enode://d860a01f9722d78051619d1e2351aba3f43f943f6f00718d1b9baa4101932a1f5011f16bb2b1bb35db20d6fe28fa0bf09636d26a87d31de9ec6203eeedb1f666@18.138.108.67:30303,enode://22a8232c3abc76a16ae9d6c3b164f98775fe226f0911b7ca871128a74a8e9630b458460865bab457221f1d448dd9791d24c4e5d88786180ac185df813a68d4de@3.209.45.79:30303 \
    \
    2>&1 | tee -a "$LOG_DIR/geth-backup.log"
