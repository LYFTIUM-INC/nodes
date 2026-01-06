#!/bin/bash
# Erigon Startup Script for Ethereum Mainnet
# Optimized for MEV and high-performance trading
# Fixed version with proper process management

set -euo pipefail

ERIGON_BINARY="/usr/local/bin/erigon"
DATA_DIR="/data/blockchain/storage/erigon"
LOG_DIR="/var/log/erigon"
LOCK_FILE="$DATA_DIR/LOCK"
PID_FILE="/data/blockchain/storage/erigon/erigon.pid"
JWT_SECRET="/data/blockchain/storage/jwt-secret-common.hex"

# Function to check if Erigon is already running
is_erigon_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
    fi
    # Also check for any Erigon process using our datadir
    if pgrep -f "erigon.*datadir=$DATA_DIR" > /dev/null; then
        return 0
    fi
    # Check if LOCK file exists
    if [ -f "$LOCK_FILE" ]; then
        return 0
    fi
    return 1
}

# Function to clean up stale processes and locks
cleanup_stale_processes() {
    echo "[$(date)] Cleaning up stale processes and locks..."

    # Kill any existing Erigon processes using our datadir
    local pids=$(pgrep -f "erigon.*datadir=$DATA_DIR")
    if [ -n "$pids" ]; then
        echo "[$(date)] Found stale Erigon processes: $pids"
        echo "$pids" | xargs -r kill -TERM 2>/dev/null || true
        sleep 5
        # Force kill if still running
        echo "$pids" | xargs -r kill -KILL 2>/dev/null || true
    fi

    # Kill processes on our ports
    for port in 8545 8546 8552 30303 9091 6062; do
        fuser -k ${port}/tcp 2>/dev/null || true
    done

    # Remove lock files
    rm -f "$LOCK_FILE" "$DATA_DIR/erigon.lock" "$PID_FILE" 2>/dev/null || true

    # Wait for ports to be released
    sleep 3
}

# Main startup logic
echo "[$(date)] Starting Erigon startup script..." | tee -a "$LOG_DIR/erigon-startup.log"

# Check if already running
if is_erigon_running; then
    echo "[$(date)] WARNING: Erigon appears to be running, attempting cleanup..." | tee -a "$LOG_DIR/erigon-startup.log"
    cleanup_stale_processes
    sleep 5
    # Re-check after cleanup
    if is_erigon_running; then
        echo "[$(date)] ERROR: Erigon is still running after cleanup!" | tee -a "$LOG_DIR/erigon-startup.log"
        echo "[$(date)] Please stop it first with: sudo systemctl stop erigon-mainnet" | tee -a "$LOG_DIR/erigon-startup.log"
        exit 1
    fi
fi

# Ensure directories exist (directories should already exist with proper permissions)
mkdir -p "$DATA_DIR" "$LOG_DIR" 2>/dev/null || true
# Note: Directory permissions should be set up beforehand by system admin

# Generate JWT secret if needed
if [ ! -f "$JWT_SECRET" ]; then
    openssl rand -hex 32 > "$JWT_SECRET"
    chmod 644 "$JWT_SECRET"
fi

# Clean up any stale processes
cleanup_stale_processes

# Start Erigon with optimized settings for MEV
echo "[$(date)] Starting Erigon for Ethereum mainnet..." | tee -a "$LOG_DIR/erigon-startup.log"

# Save PID for proper process management
echo $$ > "$PID_FILE"

# Use exec to replace the shell process with Erigon
exec $ERIGON_BINARY \
    --datadir="$DATA_DIR" \
    --chain=mainnet \
    --prune.mode=full \
    --http \
    --http.addr=127.0.0.1 \
    --http.port=8545 \
    --http.vhosts="localhost,127.0.0.1" \
    --http.api=eth,net,web3,txpool,erigon,debug \
    --ws \
    --ws.port=8546 \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port=8552 \
    --authrpc.jwtsecret="$JWT_SECRET" \
    --authrpc.vhosts="*" \
    --port=30303 \
    --private.api.addr=127.0.0.1:9091 \
    --db.size.limit=2TB \
    --maxpeers=120 \
    --batchSize=512m \
    --db.read.concurrency=512 \
    --sync.loop.block.limit=4000 \
    --torrent.download.rate=60mb \
    --torrent.upload.rate=30mb \
    --torrent.conns.perfile=12 \
    --torrent.download.slots=6 \
    --txpool.accountslots=32 \
    --txpool.globalslots=8192 \
    --txpool.accountqueue=64 \
    --txpool.globalqueue=4096 \
    --txpool.pricelimit=1000000000 \
    --txpool.pricebump=10 \
    --rpc.gascap=50000000 \
    --rpc.txfeecap=100 \
    --rpc.allow-unprotected-txs=false \
    --log.console.verbosity=info \
    --log.dir.path="$LOG_DIR" \
    --log.dir.verbosity=2 \
    --metrics \
    --metrics.addr=127.0.0.1 \
    --metrics.port=6062 \
    --externalcl \
    --nat=extip:51.159.82.58 \
    --bootnodes=enode://d860a01f9722d78051619d1e2351aba3f43f943f6f00718d1b9baa4101932a1f5011f16bb2b1bb35db20d6fe28fa0bf09636d26a87d31de9ec6203eeedb1f666@18.138.108.67:30303,enode://22a8232c3abc76a16ae9d6c3b164f98775fe226f0917b0ca871128a74a8e9630b458460865bab457221f1d448dd9791d24c4e5d88786180ac185df813a68d4de@3.209.45.79:30303 \
    2>&1 | tee -a "$LOG_DIR/erigon.log"
