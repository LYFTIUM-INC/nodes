#!/bin/bash
# Geth Backup Node Configuration
# Secure MEV-ready setup with company domain integration

set -euo pipefail

# Configuration
DATADIR="/data/blockchain/storage/geth-backup"
LOG_DIR="/var/log/geth-backup"
JWT_SECRET="/data/blockchain/storage/erigon/jwt.hex"

# Company domain configuration (replace with actual domain)
COMPANY_DOMAIN="geth.rpc.lyftium.com"

# Create directories
sudo mkdir -p "$DATADIR" "$LOG_DIR"
sudo chown -R lyftium:lyftium "$DATADIR" "$LOG_DIR"

# Port allocation (non-conflicting)
HTTP_PORT=8570      # Geth backup RPC
WS_PORT=8571        # Geth backup WebSocket  
AUTH_PORT=8572      # Geth backup AuthRPC
METRICS_PORT=6068   # Geth backup metrics
P2P_PORT=30310      # Geth backup P2P

echo "Starting Geth Backup Node..."
echo "Company Domain: $COMPANY_DOMAIN"
echo "RPC Endpoint: http://localhost:$HTTP_PORT"
echo "WebSocket: ws://localhost:$WS_PORT"

# Start Geth with security hardening
exec /usr/bin/geth \
    --datadir="$DATADIR" \
    --mainnet \
    --syncmode=snap \
    --gcmode=full \
    --cache=3072 \
    --maxpeers=30 \
    \
    --http \
    --http.addr=127.0.0.1 \
    --http.port="$HTTP_PORT" \
    --http.api=eth,net,web3,debug,txpool \
    --http.vhosts="localhost,$COMPANY_DOMAIN,geth.$COMPANY_DOMAIN" \
    --http.corsdomain="https://$COMPANY_DOMAIN,https://geth.$COMPANY_DOMAIN" \
    \
    --ws \
    --ws.addr=127.0.0.1 \
    --ws.port="$WS_PORT" \
    --ws.api=eth,net,web3,debug,txpool \
    --ws.origins="https://$COMPANY_DOMAIN,https://geth.$COMPANY_DOMAIN" \
    \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port="$AUTH_PORT" \
    --authrpc.jwtsecret="$JWT_SECRET" \
    --authrpc.vhosts="localhost,$COMPANY_DOMAIN" \
    \
    --port="$P2P_PORT" \
    --discovery.port="$P2P_PORT" \
    \
    --metrics \
    --metrics.addr=127.0.0.1 \
    --metrics.port="$METRICS_PORT" \
    \
    --txlookuplimit=0 \
    --verbosity=3 \
    --log.rotate \
    --log.maxage=7 \
    \
    --rpc.gascap=25000000 \
    --rpc.txfeecap=100 \
    --rpc.allow-unprotected-txs=false \
    \
    --txpool.accountslots=16 \
    --txpool.globalslots=8192 \
    --txpool.accountqueue=64 \
    --txpool.globalqueue=2048 \
    --txpool.pricelimit=1000000000 \
    --txpool.pricebump=10 \
    \
    --nat=extip:127.0.0.1 \
    --netrestrict=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.0/8 \
    2>&1 | tee -a "$LOG_DIR/geth-backup.log"