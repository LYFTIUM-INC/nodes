#!/bin/bash

# Optimize Ethereum node for MEV operations

echo "=== OPTIMIZING ETHEREUM FOR MEV ==="

# 1. Optimize Erigon for MEV
echo "Updating Erigon configuration for MEV..."
sudo systemctl stop erigon

# Create optimized MEV config
cat > /tmp/erigon-mev.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/data/blockchain/nodes/ethereum/erigon/bin/erigon \
  --datadir=/data/blockchain/storage/erigon-fresh \
  --chain=mainnet \
  --prune.mode=full \
  --http \
  --http.addr=0.0.0.0 \
  --http.port=8545 \
  --http.vhosts=localhost,eth.rpc.lyftium.com \
  --http.api=eth,net,web3,txpool,erigon,debug,engine,trace,admin \
  --ws \
  --ws.port=8546 \
  --authrpc.addr=127.0.0.1 \
  --authrpc.port=8551 \
  --authrpc.jwtsecret=/data/blockchain/storage/erigon-fresh/jwt.hex \
  --authrpc.vhosts=localhost \
  --port=30308 \
  --p2p.allowed-ports=30308,30309,30310,30311,30312 \
  --p2p.protocol=68,67 \
  --nat=extip:51.159.82.58 \
  --private.api.addr=127.0.0.1:9091 \
  --db.pagesize=16k \
  --maxpeers=100 \
  --txpool.accountslots=32 \
  --txpool.globalslots=20000 \
  --txpool.globalqueue=20000 \
  --txpool.pricelimit=0 \
  --txpool.pricebump=10 \
  --txpool.nolocals=false \
  --txpool.disable-blob-transactions=false \
  --rpc.batch.limit=1000 \
  --rpc.batch.concurrency=100 \
  --rpc.returndata.limit=1000000 \
  --trace.maxtraces=10000 \
  --log.console.verbosity=info \
  --log.dir.path=/data/blockchain/storage/erigon-fresh/logs \
  --log.dir.verbosity=3 \
  --torrent.upload.rate=512mb \
  --torrent.download.rate=1024mb
EOF

sudo cp /tmp/erigon-mev.conf /etc/systemd/system/erigon.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl start erigon

echo "✅ Erigon optimized for MEV"

# 2. Create MEV monitoring service
cat > /tmp/mev-monitor.service << 'EOF'
[Unit]
Description=MEV Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/data/blockchain/nodes/monitoring/mev-ethereum-monitor.sh
Restart=always
RestartSec=300
User=lyftium

[Install]
WantedBy=multi-user.target
EOF

sudo cp /tmp/mev-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mev-monitor.service

echo "✅ MEV monitoring service created"

# 3. Create MEV health check endpoint
cat > /data/blockchain/nodes/monitoring/mev-health-api.py << 'EOF'
#!/usr/bin/env python3
from fastapi import FastAPI
import requests
import json

app = FastAPI()

@app.get("/health")
async def health_check():
    try:
        # Check Erigon
        erigon_sync = requests.post("http://localhost:8545", 
            json={"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}).json()
        
        # Check Lighthouse
        lighthouse_sync = requests.get("http://localhost:5052/eth/v1/node/syncing").json()
        
        # Check mempool
        txpool = requests.post("http://localhost:8545",
            json={"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}).json()
        
        is_ready = (erigon_sync["result"] == False and 
                   lighthouse_sync["data"]["is_syncing"] == False)
        
        return {
            "ready_for_mev": is_ready,
            "erigon_synced": erigon_sync["result"] == False,
            "lighthouse_synced": lighthouse_sync["data"]["is_syncing"] == False,
            "pending_txs": int(txpool["result"]["pending"], 16) if "result" in txpool else 0
        }
    except Exception as e:
        return {"error": str(e), "ready_for_mev": False}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9999)
EOF

chmod +x /data/blockchain/nodes/monitoring/mev-health-api.py

echo "✅ MEV health API created"

echo ""
echo "=== MEV OPTIMIZATION COMPLETE ==="
echo ""
echo "Next steps:"
echo "1. Wait for Lighthouse to fully sync (monitor with: journalctl -f -u lighthouse)"
echo "2. Once synced, MEV operations will be ready"
echo "3. Monitor MEV readiness at: http://localhost:9999/health"
echo "4. Use the MEV monitor: /data/blockchain/nodes/monitoring/mev-ethereum-monitor.sh"