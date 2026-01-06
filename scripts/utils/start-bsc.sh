#!/bin/bash

# BSC Node Startup Script

BSC_BINARY="/data/blockchain/nodes/bsc/source/build/bin/geth"
DATA_DIR="/data/bsc"
CONFIG_FILE="/data/blockchain/nodes/bsc/config/bsc.toml"
LOG_DIR="/data/bsc/logs"
GENESIS_FILE="/data/blockchain/nodes/bsc/config/genesis.json"

# Create directories if they don't exist
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Check if BSC is already initialized
if [ ! -d "$DATA_DIR/geth" ]; then
    echo "Initializing BSC with genesis..."
    
    # Initialize with local genesis file
    if [ -f "$GENESIS_FILE" ]; then
        $BSC_BINARY init --datadir "$DATA_DIR" "$GENESIS_FILE"
    else
        echo "No genesis file found, starting without initialization (will use built-in BSC mainnet config)"
    fi
fi

# Start BSC node
echo "Starting BSC node..."
exec $BSC_BINARY \
    --mainnet \
    --datadir "$DATA_DIR" \
    --cache 4096 \
    --gcmode archive \
    --syncmode snap \
    --maxpeers 50 \
    --http \
    --http.addr 0.0.0.0 \
    --http.port 8555 \
    --http.api eth,net,web3,txpool,debug,trace,parlia \
    --http.corsdomain "*" \
    --http.vhosts "*" \
    --ws \
    --ws.addr 0.0.0.0 \
    --ws.port 8556 \
    --ws.api eth,net,web3,txpool,debug,trace,parlia \
    --ws.origins "*" \
    --metrics \
    --metrics.addr 0.0.0.0 \
    --metrics.port 9554 \
    --pprof \
    --pprof.addr 0.0.0.0 \
    --pprof.port 9555 \
    --bootnodes "enode://433c8bfdf53a3e2268ccb1b829e47f629793291cbddf0c76ae626da802f90532251fc558e2e0d10d6725e759088439bf1cd4714716b03a259a35d4b2e4acfa7f@52.69.102.73:30311,enode://571bee8fb902a625942f10a770ccf727ae2ba1bab2a2b64e121594a99c9437317f6166a395670a00b7d93647eacafe598b6bbcef15b40b6d1a10243865a3e80f@35.73.84.120:30311,enode://fac42fb0ba082b7d1eebded216db42161163d42e4f52c9e47716946d64468a62da4ba0b1cac0df5e8bf1e5284861d757339751c33d51dfef318be5168803d0b5@18.203.152.54:30311,enode://3063d1c9e1b824cfbb7c7b6abafa34faec6bb4e7e06941d218d760acdd7963b274278c5c3e63914bd6d1b58504c59ec5522c56f883baceb8538674b92da48a96@34.250.32.100:30311,enode://ad78c64a4ade83692488aa42e4c94084516e555d3f340d9802c2bf106a3df8868bc46eae083d2de4018f40e8d9a9952c32a0943cd68855a9bc9fd07aac982a6d@34.204.214.24:30311" \
    2>&1 | tee -a "$LOG_DIR/bsc.log"