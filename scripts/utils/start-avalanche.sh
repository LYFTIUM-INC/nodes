#!/bin/bash

# Avalanche Node Startup Script
# This script starts avalanchego with C-Chain enabled on ports 8557/8558

# Set environment variables
export AVALANCHE_HOME="/data/blockchain/nodes/avalanche"
export AVALANCHE_DATA_DIR="${AVALANCHE_HOME}/data"
export AVALANCHE_LOG_DIR="${AVALANCHE_HOME}/logs"

# Create necessary directories
mkdir -p ${AVALANCHE_DATA_DIR} ${AVALANCHE_LOG_DIR}

# Check if avalanchego binary exists
if [ ! -f "/avalanchego/build/avalanchego" ]; then
    echo "Error: avalanchego binary not found at /avalanchego/build/avalanchego"
    echo "Please install avalanchego first"
    exit 1
fi

# Kill any existing avalanchego process
echo "Stopping any existing avalanchego process..."
pkill -9 avalanchego 2>/dev/null || true
sleep 2

# Start avalanchego with our configuration
echo "Starting Avalanche node with C-Chain on port 8557..."
nohup /avalanchego/build/avalanchego \
    --config-file=${AVALANCHE_HOME}/config/config.json \
    > ${AVALANCHE_LOG_DIR}/avalanche.log 2>&1 &

# Save PID
echo $! > ${AVALANCHE_HOME}/avalanche.pid

echo "Avalanche node started with PID: $(cat ${AVALANCHE_HOME}/avalanche.pid)"
echo "Log file: ${AVALANCHE_LOG_DIR}/avalanche.log"
echo ""
echo "Wait for the node to bootstrap..."
echo "You can check the status with:"
echo "  curl -X POST --data '{\"jsonrpc\":\"2.0\",\"method\":\"info.isBootstrapped\",\"params\":{\"chain\":\"C\"},\"id\":1}' -H \"Content-Type: application/json\" http://localhost:8557/ext/info"
echo ""
echo "Once bootstrapped, C-Chain RPC will be available at:"
echo "  HTTP: http://localhost:8557/ext/bc/C/rpc"
echo "  WebSocket: ws://localhost:8557/ext/bc/C/ws"