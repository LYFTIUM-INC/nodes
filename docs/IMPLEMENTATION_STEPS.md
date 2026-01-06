# MEV Infrastructure Remediation - Step-by-Step Implementation
**Date:** $(date +"%Y-%m-%d %H:%M:%S")
**Execution Guide:** Detailed commands and steps

---

## Prerequisites

```bash
# 1. Verify infrastructure is operational
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r '.result'

curl -s http://127.0.0.1:5052/eth/v1/node/health

# 2. Check current service status
systemctl status mev-pipeline.service mev-execution.service
```

---

## STEP 1: Backup Everything (5 minutes)

```bash
# Create backup directory
BACKUP_DIR="/data/blockchain/nodes/backups/mev-services-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup service files
sudo cp /etc/systemd/system/mev-pipeline.service "$BACKUP_DIR/"
sudo cp /etc/systemd/system/mev-execution.service "$BACKUP_DIR/"

# Backup .env file
cp /opt/mev-lab/.env "$BACKUP_DIR/.env"

# Backup override directories
sudo cp -r /etc/systemd/system/mev-pipeline.service.d "$BACKUP_DIR/pipeline.d" 2>/dev/null || true
sudo cp -r /etc/systemd/system/mev-execution.service.d "$BACKUP_DIR/execution.d" 2>/dev/null || true

echo "✅ Backups created in: $BACKUP_DIR"
```

---

## STEP 2: Fix mev-execution.service (15 minutes)

### 2.1 Edit Service File

```bash
sudo nano /etc/systemd/system/mev-execution.service
```

### 2.2 Find This Line (around line 34):
```ini
EnvironmentFile=-/opt/mev-lab/.env
```

### 2.3 Add AFTER That Line:
```ini
# ============================================
# LOCAL NODE ENDPOINTS - HIGHEST PRIORITY
# These MUST come AFTER EnvironmentFile to override .env settings
# ============================================
Environment="ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_WS=ws://127.0.0.1:8546"
Environment="ERIGON_HTTP_DIRECT=http://127.0.0.1:8545"
Environment="ERIGON_WS_DIRECT=ws://127.0.0.1:8546"
Environment="LOCAL_ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_RPC_URL=http://127.0.0.1:8545"

Environment="GETH_HTTP=http://127.0.0.1:8549"
Environment="GETH_WS=ws://127.0.0.1:8550"
Environment="GETH_FALLBACK_HTTP_DIRECT=http://127.0.0.1:8549"
Environment="GETH_FALLBACK_WS_DIRECT=ws://127.0.0.1:8550"
Environment="LOCAL_GETH_HTTP=http://127.0.0.1:8549"
Environment="GETH_RPC_URL=http://127.0.0.1:8549"

Environment="LIGHTHOUSE_API=http://127.0.0.1:5052"
Environment="LIGHTHOUSE_BEACON_API=http://127.0.0.1:5052"

Environment="MEV_BOOST_URL=http://127.0.0.1:18551"
Environment="MEV_BOOST_WS=ws://127.0.0.1:18551"

Environment="PREFER_LOCAL_NODES=true"
Environment="LOCAL_NODE_PRIORITY=true"
Environment="ENABLE_LOCAL_ERIGON_EXTRACTION=true"
Environment="ENABLE_LOCAL_GETH_EXTRACTION=true"

Environment="ETHEREUM_RPC=http://127.0.0.1:8545"
Environment="ETH_WS_ORDER=local,127.0.0.1,localhost,alchemy,infura"
Environment="ETH_HTTP_ORDER=local,127.0.0.1,localhost,alchemy,infura"
```

### 2.4 Reload and Restart

```bash
sudo systemctl daemon-reload
sudo systemctl restart mev-execution.service
sudo systemctl status mev-execution.service
```

### 2.5 Verify

```bash
# Check environment variables
systemctl show mev-execution.service --property=Environment | \
  grep ERIGON_HTTP
# Should show: ERIGON_HTTP=http://127.0.0.1:8545

# Check service is running
systemctl is-active mev-execution.service
# Should show: active
```

---

## STEP 3: Analyze mev-pipeline.service (10 minutes)

### 3.1 Check Current Environment

```bash
# Verify systemd environment
systemctl show mev-pipeline.service --property=Environment | \
  grep -E "ERIGON_HTTP|127.0.0.1"
```

**Expected Output:**
```
ERIGON_HTTP=http://127.0.0.1:8545 ERIGON_WS=ws://127.0.0.1:8546 ...
```

### 3.2 Check for .env Loading in Code

```bash
# Search for python-dotenv
find /opt/mev-lab/src -name "*.py" -exec grep -l "load_dotenv\|python-dotenv" {} \;

# Check main service file
grep -r "load_dotenv\|from dotenv\|import dotenv" \
  /opt/mev-lab/src/services/mev_detection_service.py
```

### 3.3 Check Override Files

```bash
sudo ls -la /etc/systemd/system/mev-pipeline.service.d/
sudo cat /etc/systemd/system/mev-pipeline.service.d/*.conf 2>/dev/null | \
  grep -E "ERIGON|GETH|RPC"
```

**If override files exist and have external endpoints:**
- Either remove them OR update to local endpoints

---

## STEP 4: Update .env File (Only If Needed) (5 minutes)

**Only do this if Step 3.2 shows code loads .env directly**

### 4.1 Backup .env

```bash
cp /opt/mev-lab/.env /opt/mev-lab/.env.backup.$(date +%Y%m%d_%H%M%S)
```

### 4.2 Edit .env

```bash
sudo nano /opt/mev-lab/.env
```

### 4.3 Update These Lines:

```bash
# CHANGE FROM:
ERIGON_HTTP=https://mainnet.infura.io/v3/abcb3202fd8f4923bf589d0677ba3dd0
ERIGON_WS=wss://mainnet.infura.io/ws/v3/abcb3202fd8f4923bf589d0677ba3dd0
ENABLE_LOCAL_ERIGON_EXTRACTION=false
ENABLE_LOCAL_GETH_EXTRACTION=false

# CHANGE TO:
ERIGON_HTTP=http://127.0.0.1:8545
ERIGON_WS=ws://127.0.0.1:8546
ENABLE_LOCAL_ERIGON_EXTRACTION=true
ENABLE_LOCAL_GETH_EXTRACTION=true

# Keep Infura as fallback (optional):
ERIGON_FALLBACK_HTTP=https://mainnet.infura.io/v3/abcb3202fd8f4923bf589d0677ba3dd0
ERIGON_FALLBACK_WS=wss://mainnet.infura.io/ws/v3/abcb3202fd8f4923bf589d0677ba3dd0
```

---

## STEP 5: Fix Service Dependencies (10 minutes)

### 5.1 Update mev-pipeline.service

```bash
sudo nano /etc/systemd/system/mev-pipeline.service
```

**In [Unit] section, ensure:**
```ini
After=network-online.target erigon.service lighthouse.service mev-boost.service
Wants=network-online.target erigon.service lighthouse.service mev-boost.service
```

**In [Service] section, add health check:**
```ini
ExecStartPre=/bin/bash -c 'timeout 5 curl -s http://127.0.0.1:8545 >/dev/null || (echo "Erigon not ready"; exit 1)'
```

### 5.2 Update mev-execution.service

```bash
sudo nano /etc/systemd/system/mev-execution.service
```

**In [Unit] section:**
```ini
After=network-online.target mev-pipeline.service erigon.service
Wants=network-online.target mev-pipeline.service erigon.service
```

**In [Service] section:**
```ini
ExecStartPre=/bin/bash -c 'timeout 5 curl -s http://127.0.0.1:8545 >/dev/null || (echo "Erigon not ready"; exit 1)'
```

### 5.3 Reload

```bash
sudo systemctl daemon-reload
```

---

## STEP 6: Restart and Verify (15 minutes)

### 6.1 Restart Services

```bash
# Stop services
sudo systemctl stop mev-pipeline.service
sudo systemctl stop mev-execution.service

# Wait a moment
sleep 3

# Start in order
sudo systemctl start mev-pipeline.service
sleep 5
sudo systemctl start mev-execution.service
```

### 6.2 Check Service Status

```bash
systemctl status mev-pipeline.service --no-pager | head -15
systemctl status mev-execution.service --no-pager | head -15
```

### 6.3 Monitor Logs

```bash
# Monitor mev-pipeline for local endpoint usage
sudo journalctl -u mev-pipeline.service -f | \
  grep -E "127.0.0.1|8545|erigon_local|ethereum connected"

# In another terminal, monitor mev-execution
sudo journalctl -u mev-execution.service -f | \
  grep -E "127.0.0.1|8545|erigon_local|ethereum connected"
```

**What to Look For:**
- ✅ GOOD: "✅ ethereum connected via http://127.0.0.1:8545"
- ✅ GOOD: "erigon_local"
- ❌ BAD: "✅ ethereum connected via https://ethereum-rpc.publicnode.com"
- ❌ BAD: "infura" or external URLs

---

## STEP 7: Create Verification Script (10 minutes)

```bash
cat > /opt/mev-lab/scripts/verify-local-infrastructure.sh << 'EOF'
#!/bin/bash
# MEV Services Local Infrastructure Verification Script

echo "=== MEV Services Local Infrastructure Verification ==="
echo ""

# Check mev-pipeline
echo "1. mev-pipeline.service Configuration:"
PIPELINE_ENV=$(systemctl show mev-pipeline.service --property=Environment --no-pager)
if echo "$PIPELINE_ENV" | grep -q "ERIGON_HTTP=http://127.0.0.1:8545"; then
    echo "   ✅ Local endpoint configured correctly"
else
    echo "   ❌ Local endpoint NOT configured"
fi

PIPELINE_LOGS=$(journalctl -u mev-pipeline.service --since "5 minutes ago" --no-pager | tail -50)
if echo "$PIPELINE_LOGS" | grep -qE "127.0.0.1:8545|erigon_local"; then
    echo "   ✅ Logs show local endpoint usage"
else
    if echo "$PIPELINE_LOGS" | grep -q "ethereum connected via"; then
        echo "   ⚠️  Using external RPC (check logs)"
    else
        echo "   ⚠️  No connection logs found"
    fi
fi

echo ""
echo "2. mev-execution.service Configuration:"
EXECUTION_ENV=$(systemctl show mev-execution.service --property=Environment --no-pager)
if echo "$EXECUTION_ENV" | grep -q "ERIGON_HTTP=http://127.0.0.1:8545"; then
    echo "   ✅ Local endpoint configured correctly"
else
    echo "   ❌ Local endpoint NOT configured"
fi

EXECUTION_LOGS=$(journalctl -u mev-execution.service --since "5 minutes ago" --no-pager | tail -50)
if echo "$EXECUTION_LOGS" | grep -qE "127.0.0.1:8545|erigon_local"; then
    echo "   ✅ Logs show local endpoint usage"
else
    if echo "$EXECUTION_LOGS" | grep -q "ethereum connected via"; then
        echo "   ⚠️  Using external RPC (check logs)"
    else
        echo "   ⚠️  No connection logs found"
    fi
fi

echo ""
echo "3. Infrastructure Status:"
if curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 >/dev/null 2>&1; then
    BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      http://127.0.0.1:8545 | jq -r '.result' | xargs printf "%d\n" 2>/dev/null)
    echo "   ✅ Erigon RPC accessible (Block: $BLOCK)"
else
    echo "   ❌ Erigon RPC NOT accessible"
fi

if curl -s http://127.0.0.1:5052/eth/v1/node/health >/dev/null 2>&1; then
    echo "   ✅ Lighthouse Beacon API accessible"
else
    echo "   ❌ Lighthouse Beacon API NOT accessible"
fi

if timeout 1 nc -zv 127.0.0.1 18551 >/dev/null 2>&1; then
    echo "   ✅ MEV-Boost accessible"
else
    echo "   ❌ MEV-Boost NOT accessible"
fi

echo ""
echo "=== Verification Complete ==="
EOF

chmod +x /opt/mev-lab/scripts/verify-local-infrastructure.sh

# Run verification
/opt/mev-lab/scripts/verify-local-infrastructure.sh
```

---

## STEP 8: Monitor for 30 Minutes

```bash
# Continuous monitoring
watch -n 10 '/opt/mev-lab/scripts/verify-local-infrastructure.sh'

# Or check logs periodically
while true; do
    echo "=== $(date) ==="
    journalctl -u mev-pipeline.service --since "1 minute ago" --no-pager | \
      grep -E "connected via|127.0.0.1|erigon_local" | tail -3
    sleep 60
done
```

---

## Troubleshooting

### Issue: Service won't start

```bash
# Check logs
sudo journalctl -u mev-execution.service --no-pager | tail -30

# Check syntax
sudo systemd-analyze verify mev-execution.service

# Check environment
systemctl show mev-execution.service --property=Environment
```

### Issue: Still using external RPC

```bash
# Check if .env is being loaded
grep -r "load_dotenv" /opt/mev-lab/src/

# Check override files
sudo ls -la /etc/systemd/system/*.service.d/

# Verify environment precedence
systemctl show mev-pipeline.service --property=Environment | \
  grep ERIGON_HTTP
```

### Issue: Service dependency failures

```bash
# Check dependencies
systemctl list-dependencies mev-pipeline.service

# Verify infrastructure is running
systemctl status erigon.service lighthouse.service mev-boost.service
```

---

## Success Criteria

✅ All services start successfully
✅ Logs show "erigon_local" or "127.0.0.1:8545"
✅ NO external RPC connections in logs (unless local fails)
✅ Verification script shows all checks passing
✅ Services remain stable for 30+ minutes

---

## Rollback (If Needed)

```bash
# Restore service files
sudo cp "$BACKUP_DIR/mev-execution.service" \
       /etc/systemd/system/mev-execution.service

# Restore .env if modified
cp "$BACKUP_DIR/.env" /opt/mev-lab/.env

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart mev-pipeline.service
sudo systemctl restart mev-execution.service
```

---

**End of Implementation Steps**
