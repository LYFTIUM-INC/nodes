#!/bin/bash

# Optimized Avalanche Node Startup Script
# CPU throttled configuration for bootstrap phase

echo "Starting Avalanche node with CPU-optimized configuration..."

# Stop existing container if running
docker stop avalanche-node 2>/dev/null || true
docker rm avalanche-node 2>/dev/null || true

# Start with optimized settings
docker run -d \
  --name avalanche-node \
  --restart unless-stopped \
  --network blockchain_network \
  -p 9650:9650 \
  -p 9651:9651 \
  --memory=2g \
  --cpu-period=100000 \
  --cpu-quota=40000 \
  --oom-kill-disable=false \
  -v /data/blockchain/storage/avalanche:/root/.avalanchego \
  -v /data/blockchain/nodes/avalanche/config/avalanche.json:/root/.avalanchego/configs/node.json \
  avaplatform/avalanchego:latest \
  /avalanchego/build/avalanchego \
  --config-file=/root/.avalanchego/configs/node.json \
  --network-id=mainnet \
  --http-host=0.0.0.0 \
  --http-port=9650 \
  --db-type=leveldb \
  --consensus-app-concurrency=1 \
  --snow-optimal-processing=25 \
  --snow-max-processing=512 \
  --bootstrap-ancestors-max-containers-sent=1000 \
  --bootstrap-ancestors-max-containers-received=1000 \
  --system-tracker-processing-halflife=30s \
  --throttler-inbound-cpu-max-non-validator-usage=6.4 \
  --throttler-inbound-cpu-max-non-validator-node-usage=1.6

echo "Avalanche node started with optimized configuration"
echo "Monitor CPU usage with: docker stats avalanche-node"
echo "View logs with: docker logs -f avalanche-node"