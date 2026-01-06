#!/bin/bash
# MEV-Geth Startup Script for Bundle Processing
# Flashbots-optimized Ethereum client for MEV bundle reception and execution

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# MEV-Geth Configuration
MEV_GETH_BINARY="/data/blockchain/nodes/mev-geth/build/bin/geth"
DATA_DIR="/data/blockchain/storage/mev-geth"
LOG_DIR="/var/log/mev-geth"
LOCK_FILE="$DATA_DIR/LOCK"
PID_FILE="/data/blockchain/nodes/mev-geth/mev-geth.pid"

# MEV-Specific Ports (non-conflicting)
HTTP_PORT=8549       # MEV-Geth RPC
WS_PORT=8550         # MEV-Geth WebSocket
AUTH_PORT=8554       # MEV-Geth AuthRPC
METRICS_PORT=6070    # MEV-Geth metrics
P2P_PORT=30311       # MEV-Geth P2P

# MEV Optimization Settings
CACHE_SIZE=4096      # 4GB for MEV operations
MAX_PEERS=100         # Strategic peer connections
SYNC_MODE="snap"        # Fast sync for MEV
BUILDER_API="https://builder-relay.flashbots.net"
MEV_API="https://mev.flashbots.net"

echo "🚀 Starting MEV-Geth Node (Flashbots Optimized)"
echo "=================================="
echo "Purpose: MEV Bundle Processing & Flashbots Integration"
echo "Data Dir: $DATA_DIR"
echo "Binary: $MEV_GETH_BINARY"
echo "Ports: RPC=$HTTP_PORT, WS=$WS_PORT, Auth=$AUTH_PORT"
echo "Timestamp: $(date -Iseconds)"
echo "=================================="

# Create directories
mkdir -p "$DATADIR" "$LOG_DIR"

# Function to check if MEV-Geth is already running
is_mev_geth_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
    fi
    if pgrep -f "mev-geth.*datadir=$DATA_DIR" > /dev/null; then
        return 0
    fi
    return 1
}

# Function to clean up stale processes and locks
cleanup_stale_mev_processes() {
    echo "[$(date)] Cleaning up stale MEV-Geth processes..."

    # Kill any existing MEV-Geth processes
    local pids=$(pgrep -f "mev-geth.*datadir=$DATA_DIR")
    if [ -n "$pids" ]; then
        echo "[$(date)] Found stale MEV-Geth processes: $pids"
        echo "$pids" | xargs -r kill -TERM 2>/dev/null || true
        sleep 5
        echo "$pids" | xargs -r kill -KILL 2>/dev/null || true
    fi

    # Kill processes on our ports
    for port in $HTTP_PORT $WS_PORT $AUTH_PORT $P2P_PORT; do
        fuser -k ${port}/tcp 2>/dev/null || true
    done

    # Remove lock files
    rm -f "$LOCK_FILE" "$DATA_DIR/LOCK" "$PID_FILE" 2>/dev/null || true

    # Wait for ports to be released
    sleep 3
}

# Check if already running
if is_mev_geth_running; then
    echo "[$(date)] WARNING: MEV-Geth appears to be running, attempting cleanup..."
    cleanup_stale_mev_processes
    sleep 5
    # Re-check after cleanup
    if is_mev_geth_running; then
        echo "[$(date)] ERROR: MEV-Geth is still running after cleanup!"
        echo "[$(date)] Please stop it first with: sudo systemctl stop mev-geth"
        exit 1
    fi
fi

# Clean up any stale processes
cleanup_stale_mev_processes

# Generate JWT secret if needed
JWT_SECRET="/data/blockchain/nodes/jwt-secret-common.hex"
if [ ! -f "$JWT_SECRET" ]; then
    openssl rand -hex 32 > "$JWT_SECRET"
    chmod 644 "$JWT_SECRET"
fi

# Start MEV-Geth with MEV optimization
echo "[$(date)] Starting MEV-Geth for Ethereum mainnet..."
echo "🎯 MEV Features:"
echo "   • Bundle processing for MEV-Boost"
echo "   • Direct Flashbots builder integration"
echo "   • Enhanced mempool monitoring"
echo "   • Low-latency execution"
echo ""
echo "🌐 MEV Endpoints:"
echo "   • RPC: http://localhost:$HTTP_PORT"
echo "   • WebSocket: ws://localhost:$WS_PORT"
echo "   • AuthRPC: http://localhost:$AUTH_PORT"
echo ""

# Save PID for proper process management
echo $$ > "$PID_FILE"

# Use exec to replace the shell process with MEV-Geth
exec $MEV_GETH_BINARY \
    --datadir="$DATA_DIR" \
    --mainnet \
    --syncmode=light \
    --gcmode=full \
    --cache="$CACHE_SIZE" \
    --maxpeers="$MAX_PEERS" \
    \
    --http \
    --http.addr=127.0.0.1 \
    --http.port="$HTTP_PORT" \
    --http.vhosts="localhost,127.0.0.1" \
    --http.api=eth,net,web3,debug,txpool,mev \
    \
    --ws \
    --ws.addr=127.0.0.1 \
    --ws.port="$WS_PORT" \
    --ws.api=eth,net,web3,debug,txpool,mev \
    --ws.origins=* \
    \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port="$AUTH_PORT" \
    --authrpc.jwtsecret="$JWT_SECRET" \
    --authrpc.vhosts="localhost,127.0.0.1" \
    \
    --port="$P2P_PORT" \
    --discovery.port="$P2P_PORT" \
    \
    --nat=extip:51.159.82.58 \
    \
    --rpc.gascap=100000000 \
    --rpc.txfeecap=100 \
    --rpc.allow-unprotected-txs=false \
    \
    --txpool.accountslots=64 \
    --txpool.globalslots=8192 \
    --txpool.accountqueue=128 \
    --txpool.globalqueue=2048 \
    --txpool.pricelimit=1000000000 \
    --txpool.pricebump=10 \
    \
    --builder.api.url="$BUILDER_API" \
    --mev.api.url="$MEV_API" \
    \
    --verbosity=4 \
    --log.rotate \
    --log.maxage=7 \
    \
    2>&1 | tee -a "$LOG_DIR/mev-geth.log"