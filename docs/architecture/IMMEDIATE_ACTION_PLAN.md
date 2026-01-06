# 🚨 IMMEDIATE ACTION PLAN - MEV INFRASTRUCTURE
## Critical Issues & Quick Fixes

### 🔴 CRITICAL STATUS SUMMARY
- **RPC Endpoints**: ALL PORTS CLOSED (8545, 8546, 8548) - No blockchain connectivity
- **MEV Detection**: Running but cannot connect to blockchain
- **Profit Generation**: $0 - No opportunities detected
- **System Load**: Reduced (10.8% CPU) after Erigon issues

---

## 🎯 PRIORITY 1: RESTORE RPC CONNECTIVITY (15 minutes)

### Issue: All RPC ports showing as closed despite services running

**Quick Fix Commands:**
```bash
# 1. Check what's actually listening
sudo netstat -tlnp | grep -E "854[5-9]"

# 2. Restart Erigon with correct binding
sudo systemctl stop erigon.service
sudo /data/blockchain/nodes/ethereum/erigon/bin/erigon \
  --datadir=/data/blockchain/storage/erigon \
  --chain=mainnet \
  --http --http.addr=127.0.0.1 --http.port=8545 \
  --http.api=eth,net,web3,txpool,trace,debug \
  --maxpeers=50 --metrics --metrics.addr=127.0.0.1 &

# 3. Test connectivity
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545
```

---

## 🎯 PRIORITY 2: ENABLE MEV PROFIT DETECTION (30 minutes)

### Issue: MEV services running but no opportunities detected

**Immediate Actions:**
```bash
# 1. Install Python dependencies for profit enabler
pip3 install web3 websockets redis asyncio

# 2. Start Redis for caching (if not running)
sudo apt install redis-server -y
sudo systemctl start redis-server

# 3. Run the MEV profit enabler with ultra-low thresholds
python3 /data/blockchain/nodes/scripts/emergency-fixes/enable-mev-profits.py
```

**Manual MEV Test:**
```python
# Quick profitability test
from web3 import Web3
w3 = Web3(Web3.HTTPProvider('http://127.0.0.1:8545'))

# Get latest block
block = w3.eth.get_block('latest')
print(f"Latest block: {block.number}")

# Check mempool
pending = w3.eth.get_block('pending', full_transactions=True)
print(f"Pending transactions: {len(pending.transactions)}")
```

---

## 🎯 PRIORITY 3: MONITORING & ALERTS (1 hour)

### Quick Monitoring Setup

**1. Simple Dashboard (5 minutes):**
```bash
# Create simple web dashboard
cat > /data/blockchain/nodes/monitoring/mev-dashboard.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>MEV Dashboard</title>
    <meta http-equiv="refresh" content="5">
</head>
<body>
    <h1>MEV Infrastructure Status</h1>
    <iframe src="http://localhost:8080/health" width="100%" height="300"></iframe>
    <iframe src="http://localhost:3000/dashboard" width="100%" height="500"></iframe>
</body>
</html>
EOF

# Start simple HTTP server
cd /data/blockchain/nodes/monitoring
python3 -m http.server 8080 &
```

**2. Real-time Logs (2 minutes):**
```bash
# Create log aggregator
cat > /tmp/watch-mev.sh << 'EOF'
#!/bin/bash
watch -n 1 '
echo "=== MEV STATUS ==="
echo "Processes:" $(pgrep -f "mev" | wc -l)
echo "Last Opportunity:" $(grep -i opportunity /data/blockchain/nodes/logs/*.log | tail -1)
echo ""
echo "=== RPC STATUS ==="
curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
  | jq -r ".result" | xargs printf "Ethereum Block: %d\n"
echo ""
echo "=== SYSTEM LOAD ==="
uptime
'
EOF
bash /tmp/watch-mev.sh
```

---

## 🎯 PRIORITY 4: PROFIT GENERATION (2 hours)

### Enable Immediate MEV Profits

**1. Ultra-Low Threshold Config:**
```javascript
// /tmp/mev-config.json
{
  "min_profit_usd": 0.01,  // $0.01 minimum
  "gas_buffer": 1.1,       // 10% buffer
  "slippage": 0.003,       // 0.3%
  "strategies": ["arbitrage", "sandwich", "liquidation"],
  "dex_list": ["uniswap_v2", "uniswap_v3", "sushiswap"],
  "max_gas_price": "200"   // 200 gwei max
}
```

**2. Test Transaction:**
```python
# Test MEV execution
from web3 import Web3
w3 = Web3(Web3.HTTPProvider('http://127.0.0.1:8545'))

# Find a DEX transaction
uniswap_router = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'
pending = w3.eth.get_block('pending', full_transactions=True)

for tx in pending.transactions[:10]:
    if tx['to'] == uniswap_router:
        print(f"Found DEX tx: {tx['hash'].hex()}")
        # Simulate sandwich attack
        print(f"Gas price: {tx['gasPrice']}")
        print(f"Value: {w3.from_wei(tx['value'], 'ether')} ETH")
```

---

## 📊 SUCCESS METRICS

### Within 1 Hour:
- [ ] All RPC endpoints responding (8545-8549)
- [ ] MEV processes detecting opportunities
- [ ] At least 1 profitable opportunity logged
- [ ] Basic monitoring dashboard accessible

### Within 24 Hours:
- [ ] First profitable MEV transaction executed
- [ ] $100+ in daily profits
- [ ] Automated alerts configured
- [ ] All L2 networks synced

### Within 1 Week:
- [ ] $1,000+ daily profits
- [ ] Cross-chain arbitrage active
- [ ] Advanced strategies deployed
- [ ] Full monitoring suite operational

---

## 🆘 EMERGENCY CONTACTS

If issues persist:
1. Check logs: `journalctl -u erigon -f`
2. System resources: `htop`
3. Network status: `netstat -tlnp`
4. MEV logs: `tail -f /data/blockchain/nodes/logs/mev*.log`

---

## 🚀 QUICK START COMMANDS

```bash
# Complete recovery sequence
cd /data/blockchain/nodes

# 1. Fix Erigon
bash scripts/emergency-fixes/fix-erigon-performance.sh

# 2. Enable profits
python3 scripts/emergency-fixes/enable-mev-profits.py &

# 3. Monitor
bash scripts/monitoring/quick-health-check.sh

# 4. Watch profits
tail -f logs/mev-profits.log
```

**Time to First Profit: ~30 minutes with these fixes**

---
*Action Plan Generated: 2025-07-09 13:35:00 PDT*
*Execute immediately for fastest results*