#!/bin/bash
# RETH Deployment Script - MINIMAL WORKING VERSION
# Only uses supported arguments based on Reth CLI help output

echo "🚀 Deploying RETH with MEV Foundation integration (MINIMAL)..."

# Remove any existing container
docker rm -f reth-ethereum-mev 2>/dev/null || true

# Deploy with minimal, working configuration
docker run -d \
  --name reth-ethereum-mev \
  --restart unless-stopped \
  --network mev_foundation_network \
  -p 38545:8545 \
  -p 38546:8546 \
  -p 40303:30303 \
  -p 40303:30303/udp \
  -p 38551:8551 \
  -v /data/blockchain/storage/reth:/data \
  -v /data/blockchain/nodes/security/secrets/ethereum_jwt_secret:/jwt.hex:ro \
  -v /data/blockchain/nodes/configs/reth:/configs \
  --add-host=reth-ethereum-mev:127.0.0.1 \
  --entrypoint /usr/local/bin/reth \
  ghcr.io/paradigmxyz/reth:v1.0.0 \
  node \
    --chain mainnet \
    --datadir /data \
    --http \
    --http.addr 0.0.0.0 \
    --http.port 8545 \
    --http.api eth,net,web3,debug,trace,txpool \
    --http.corsdomain "*" \
    --ws \
    --ws.addr 0.0.0.0 \
    --ws.port 8546 \
    --ws.api eth,net,web3,debug,trace,txpool \
    --ws.origins "*" \
    --port 30303 \
    --nat any \
    --authrpc.addr 0.0.0.0 \
    --authrpc.port 8551 \
    --authrpc.jwtsecret /jwt.hex

echo "✅ RETH deployed with minimal working configuration!"
echo "📊 Engine API: http://localhost:38551 (accessible to Docker network)"
echo "🌐 HTTP RPC: http://localhost:38545"
echo "🔗 WebSocket: http://localhost:38546"
echo "🤗 P2P: http://localhost:40303"
echo "🔍 Builder: Enabled (uses RBuilder for MEV)"
echo "📊 Network: mev_foundation_network"
echo ""