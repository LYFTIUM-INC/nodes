#!/bin/bash
# Erigon Startup Script - SYNC ACCELERATION WITHOUT CAPLIN
# Optimized for fastest sync and MEV performance

ERIGON_BINARY="/data/blockchain/nodes/ethereum/erigon/bin/erigon"
DATA_DIR="/data/blockchain/storage/erigon"
LOG_DIR="$DATA_DIR/logs"

# Ensure directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Ensure JWT secret exists
if [ ! -f "$DATA_DIR/jwt.hex" ]; then
    openssl rand -hex 32 > "$DATA_DIR/jwt.hex"
fi

echo "Starting Erigon with SYNC ACCELERATION (Caplin disabled to avoid port conflicts)"
echo "Optimizations: 2048mb download, 100 peers, 4GB cache, no Caplin/beacon"

# Kill any existing erigon processes
pkill -f "erigon.*datadir=/data/blockchain/storage/erigon"
sleep 3

# Kill any process using port 4000 (Caplin conflict)
fuser -k 4000/udp 2>/dev/null || true

# Start Erigon with SYNC ACCELERATION settings (no Caplin)
exec $ERIGON_BINARY \
    --datadir="$DATA_DIR" \
    --chain=mainnet \
    --prune.mode=full \
    --http \
    --http.addr=0.0.0.0 \
    --http.port=8545 \
    --http.vhosts="*" \
    --http.api=eth,net,web3,txpool,erigon,debug,trace,engine \
    --ws \
    --ws.port=8546 \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port=8551 \
    --authrpc.jwtsecret="$DATA_DIR/jwt.hex" \
    --authrpc.vhosts="localhost" \
    --port=30304 \
    --p2p.protocol=68,67 \
    --private.api.addr=127.0.0.1:9091 \
    --db.pagesize=16k \
    --maxpeers=100 \
    --txpool.accountslots=16 \
    --txpool.globalslots=10000 \
    --txpool.globalqueue=10000 \
    --txpool.pricelimit=1 \
    --txpool.pricebump=10 \
    --log.console.verbosity=info \
    --log.dir.path="$LOG_DIR" \
    --log.dir.verbosity=3 \
    --torrent.upload.rate=1024mb \
    --torrent.download.rate=2048mb \
    --state.cache=4GB \
    --db.size.limit=2TB \
    --downloader.verify=false \
    --nat=extip:51.159.82.58 \
    --metrics \
    --metrics.addr=0.0.0.0 \
    --metrics.port=6060 \
    --caplin=false \
    2>&1 | tee -a "$LOG_DIR/erigon-no-caplin-startup.log"