#!/bin/bash

# BSC Node Startup Script - Memory Optimized
# Optimized for 64GB RAM system with multiple nodes

BSC_BINARY="/data/blockchain/nodes/bsc/source/build/bin/geth"
DATA_DIR="/data/bsc"
LOG_DIR="/data/bsc/logs"

# Create directories if they don't exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Set memory limits to prevent OOM
export GOGC=50
export GOMEMLIMIT=16GiB

# Kill any existing processes on our ports
fuser -k 8555/tcp 8556/tcp 30313/tcp 2>/dev/null || true
sleep 2

# Start BSC node with memory-optimized settings
echo "Starting BSC node with memory optimization..."
exec $BSC_BINARY \
    --mainnet \
    --datadir "$DATA_DIR" \
    --port 30313 \
    --cache 2048 \
    --gcmode full \
    --syncmode snap \
    --maxpeers 30 \
    --http \
    --http.addr 0.0.0.0 \
    --http.port 8555 \
    --http.api eth,net,web3,txpool,debug \
    --http.corsdomain "*" \
    --http.vhosts "*" \
    --ws \
    --ws.addr 0.0.0.0 \
    --ws.port 8556 \
    --ws.api eth,net,web3,txpool,debug \
    --ws.origins "*" \
    --txpool.globalslots 20000 \
    --txpool.globalqueue 5000 \
    --txpool.accountslots 16 \
    --txpool.accountqueue 64 \
    --txpool.pricebump 5 \
    --txpool.lifetime 3h \
    --snapshot \
    --state.scheme=hash \
    --bootnodes "enode://433c8bfdf53a3e2268ccb1b829e47f629793291cbddf0c76ae626da802f90532251fc558e2e0d10d6725e759088439bf1cd4714716b03a259a35d4b2e4acfa7f@52.69.102.73:30311,enode://571bee8fb902a625942f10a770ccf727ae2ba1bab2a2b64e121594a99c9437317f6166a395670a00b7d93647eacafe598b6bbcef15b40b6d1a10243865a3e80f@35.73.84.120:30311,enode://fac42fb0ba082b7d1eebded216db42161163d42e4f52c9e47716946d64468a62da4ba0b1cac0df5e8bf1e5284861d757339751c33d51dfef318be5168803d0b5@18.203.152.54:30311,enode://3063d1c9e1b824cfbb7c7b6abafa34faec6bb4e7e06941d218d760acdd7963b274278c5c3e63914bd6d1b58504c59ec5522c56f883baceb8538674b92da48a96@34.250.32.100:30311,enode://ad78c64a4ade83692488aa42e4c94084516e555d3f340d9802c2bf106a3df8868bc46eae083d2de4018f40e8d9a9952c32a0943cd68855a9bc9fd07aac982a6d@34.204.214.24:30311" \
    2>&1 | tee -a "$LOG_DIR/bsc.log"