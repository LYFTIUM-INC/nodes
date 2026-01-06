#!/bin/bash
# Lighthouse Deployment Script - FIXED VERSION
# Removed invalid --log-level argument

set -e

echo "🚀 Deploying Lighthouse Consensus Client (Fixed)..."

# Stop existing container
docker rm -f lighthouse-mev-foundation 2>/dev/null || true

# Deploy with correct arguments
docker run -d \
  --name lighthouse-mev-foundation \
  --restart unless-stopped \
  --network mev_foundation_network \
  -p 5052:5052 \
  -p 5054:5054 \
  -v /data/blockchain/storage/lighthouse:/data \
  -v /data/blockchain/nodes/security/secrets/ethereum_jwt_secret:/jwt.hex:ro \
  -v /data/blockchain/nodes/configs/lighthouse:/configs \
  sigp/lighthouse:latest \
  lighthouse beacon_node \
    --execution-endpoint http://host.docker.internal:8551 \
    --execution-jwt /jwt.hex \
    --network mainnet \
    --datadir /data \
    --http \
    --http-address 0.0.0.0 \
    --http-port 5052 \
    --http-allow-origin "*" \
    --metrics \
    --metrics-address 0.0.0.0 \
    --metrics-port 5054

echo "✅ Lighthouse deployment initiated (fixed)..."
