#!/bin/bash

# Erigon MEV-Optimized Restart Script
# This script stops the current Erigon instance and restarts with optimized settings

set -e

# Configuration
ERIGON_DIR="/data/blockchain/nodes/ethereum/erigon"
STORAGE_DIR="/data/blockchain/storage/erigon"
BINARY_PATH="/data/blockchain/nodes/ethereum/erigon/source/build/bin/erigon"
CONFIG_FILE="/data/blockchain/nodes/ethereum/erigon/config/erigon-mev-optimized.toml"
LOG_FILE="/data/blockchain/storage/erigon/logs/erigon-optimized.log"
PID_FILE="/data/blockchain/storage/erigon/erigon.pid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Erigon MEV-Optimized Restart${NC}"

# Function to check if Erigon is running
check_erigon_running() {
    if pgrep -f "erigon.*--datadir.*erigon" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to stop Erigon gracefully
stop_erigon() {
    echo -e "${YELLOW}Stopping current Erigon instance...${NC}"
    
    # Find and stop Erigon process
    ERIGON_PID=$(pgrep -f "erigon.*--datadir.*erigon" || echo "")
    
    if [ -n "$ERIGON_PID" ]; then
        echo "Found Erigon process with PID: $ERIGON_PID"
        
        # Send SIGTERM for graceful shutdown
        kill -TERM $ERIGON_PID
        
        # Wait for graceful shutdown (up to 60 seconds)
        for i in {1..60}; do
            if ! kill -0 $ERIGON_PID 2>/dev/null; then
                echo "Erigon stopped gracefully"
                break
            fi
            echo "Waiting for graceful shutdown... ($i/60)"
            sleep 1
        done
        
        # Force kill if still running
        if kill -0 $ERIGON_PID 2>/dev/null; then
            echo "Forcing Erigon shutdown..."
            kill -KILL $ERIGON_PID
            sleep 2
        fi
    else
        echo "No running Erigon process found"
    fi
}

# Function to start optimized Erigon
start_erigon_optimized() {
    echo -e "${GREEN}Starting Erigon with MEV-optimized configuration...${NC}"
    
    # Ensure directories exist
    mkdir -p "$STORAGE_DIR/logs"
    mkdir -p "$STORAGE_DIR/snapshots"
    
    # Generate JWT secret if it doesn't exist
    if [ ! -f "$STORAGE_DIR/jwt.hex" ]; then
        echo "Generating JWT secret..."
        openssl rand -hex 32 > "$STORAGE_DIR/jwt.hex"
    fi
    
    # Check available disk space
    AVAILABLE_SPACE=$(df /data | tail -1 | awk '{print $4}')
    if [ $AVAILABLE_SPACE -lt 107374182 ]; then  # Less than 100GB
        echo -e "${RED}WARNING: Less than 100GB available disk space!${NC}"
        echo "Current available: $(df -h /data | tail -1 | awk '{print $4}')"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting..."
            exit 1
        fi
    fi
    
    # Start Erigon with optimized settings
    nohup $BINARY_PATH \
        --config="$CONFIG_FILE" \
        --datadir="$STORAGE_DIR" \
        --chain=mainnet \
        --prune.mode=archive \
        --http \
        --http.addr=0.0.0.0 \
        --http.port=8545 \
        --http.vhosts=localhost,eth.rpc.lyftium.com \
        --http.api=eth,net,web3,txpool,erigon,debug,trace,engine,admin \
        --http.corsdomain="*" \
        --ws \
        --ws.addr=0.0.0.0 \
        --ws.port=8546 \
        --ws.api=eth,net,web3,txpool,erigon,debug,trace \
        --authrpc.addr=127.0.0.1 \
        --authrpc.port=8551 \
        --authrpc.jwtsecret="$STORAGE_DIR/jwt.hex" \
        --authrpc.vhosts=localhost \
        --port=30304 \
        --p2p.protocol=68,67 \
        --private.api.addr=127.0.0.1:9091 \
        --db.pagesize=64k \
        --maxpeers=100 \
        --txpool.accountslots=256 \
        --txpool.globalslots=50000 \
        --txpool.globalqueue=50000 \
        --txpool.pricelimit=1 \
        --txpool.pricebump=10 \
        --log.console.verbosity=info \
        --log.dir.path="$STORAGE_DIR/logs" \
        --log.dir.verbosity=3 \
        --torrent.upload.rate=1gb \
        --torrent.download.rate=2gb \
        --sync.bodydownloadtimeout=60s \
        --sync.receiptdownloadtimeout=60s \
        --sync.loop.throttle=100ms \
        --batchsize=2G \
        --db.read.concurrency=2048 \
        --db.size.limit=2TB \
        --snapshots.enabled=true \
        --snapshots.keep-blocks=256000 \
        --checkpoint.sync=true \
        --beacon.api.addr=127.0.0.1:5052 \
        --metrics \
        --metrics.addr=0.0.0.0 \
        --metrics.port=6060 \
        --pprof \
        --pprof.addr=127.0.0.1 \
        --pprof.port=6061 \
        > "$LOG_FILE" 2>&1 &
    
    # Get the PID and save it
    ERIGON_PID=$!
    echo $ERIGON_PID > "$PID_FILE"
    
    echo "Erigon started with PID: $ERIGON_PID"
    echo "Logs are being written to: $LOG_FILE"
    
    # Wait a moment and check if process is still running
    sleep 3
    if kill -0 $ERIGON_PID 2>/dev/null; then
        echo -e "${GREEN}Erigon is running successfully!${NC}"
        return 0
    else
        echo -e "${RED}Erigon failed to start!${NC}"
        echo "Check logs: tail -f $LOG_FILE"
        return 1
    fi
}

# Function to show sync status
show_sync_status() {
    echo -e "${YELLOW}Checking sync status...${NC}"
    
    # Wait for RPC to be available
    for i in {1..30}; do
        if curl -s -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
           http://localhost:8545 > /dev/null 2>&1; then
            break
        fi
        echo "Waiting for RPC to be available... ($i/30)"
        sleep 2
    done
    
    # Get sync status
    SYNC_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
                  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
                  http://localhost:8545 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "Sync Status: $SYNC_STATUS"
        
        # Get current block
        CURRENT_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
                       --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                       http://localhost:8545 2>/dev/null | jq -r '.result' 2>/dev/null)
        
        if [ "$CURRENT_BLOCK" != "null" ] && [ -n "$CURRENT_BLOCK" ]; then
            CURRENT_BLOCK_DEC=$(printf "%d" "$CURRENT_BLOCK" 2>/dev/null)
            echo "Current Block: $CURRENT_BLOCK_DEC"
        fi
        
        # Get network block
        NETWORK_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
                       --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                       https://ethereum.publicnode.com 2>/dev/null | jq -r '.result' 2>/dev/null)
        
        if [ "$NETWORK_BLOCK" != "null" ] && [ -n "$NETWORK_BLOCK" ]; then
            NETWORK_BLOCK_DEC=$(printf "%d" "$NETWORK_BLOCK" 2>/dev/null)
            echo "Network Block: $NETWORK_BLOCK_DEC"
            
            if [ -n "$CURRENT_BLOCK_DEC" ] && [ "$CURRENT_BLOCK_DEC" -gt 0 ]; then
                BLOCKS_BEHIND=$((NETWORK_BLOCK_DEC - CURRENT_BLOCK_DEC))
                echo "Blocks Behind: $BLOCKS_BEHIND"
                
                if [ $BLOCKS_BEHIND -lt 10 ]; then
                    echo -e "${GREEN}Node is synced!${NC}"
                else
                    SYNC_PERCENTAGE=$(echo "scale=2; $CURRENT_BLOCK_DEC * 100 / $NETWORK_BLOCK_DEC" | bc -l 2>/dev/null || echo "0")
                    echo -e "${YELLOW}Sync Progress: ${SYNC_PERCENTAGE}%${NC}"
                fi
            fi
        fi
    else
        echo "Unable to get sync status"
    fi
}

# Function to show system resources
show_resources() {
    echo -e "${YELLOW}System Resources:${NC}"
    echo "Memory Usage:"
    free -h
    echo
    echo "Disk Usage:"
    df -h /data
    echo
    echo "Erigon Process:"
    ps aux | grep erigon | grep -v grep || echo "Erigon not found in process list"
}

# Main execution
main() {
    echo "=== Erigon MEV-Optimized Restart ==="
    echo "Timestamp: $(date)"
    echo
    
    # Check if Erigon is currently running
    if check_erigon_running; then
        echo "Erigon is currently running"
        stop_erigon
    else
        echo "Erigon is not currently running"
    fi
    
    # Wait a moment
    sleep 2
    
    # Start optimized Erigon
    if start_erigon_optimized; then
        echo
        echo -e "${GREEN}=== Erigon MEV-Optimized Started Successfully ===${NC}"
        echo
        
        # Show initial status
        show_sync_status
        echo
        show_resources
        
        echo
        echo "Monitor logs with: tail -f $LOG_FILE"
        echo "Check sync status with: curl -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' http://localhost:8545"
        echo
        echo -e "${GREEN}Erigon is now running with MEV-optimized configuration!${NC}"
    else
        echo -e "${RED}Failed to start Erigon${NC}"
        exit 1
    fi
}

# Run main function
main "$@"