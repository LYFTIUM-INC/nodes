# MEV Services Quick Fix Guide
**Priority Actions to Get Services Using Local Infrastructure**

---

## ⚡ Quick Fix (30 minutes)

### Step 1: Fix mev-execution.service (10 min)

```bash
# Backup
sudo cp /etc/systemd/system/mev-execution.service \
       /etc/systemd/system/mev-execution.service.backup.$(date +%Y%m%d_%H%M%S)

# Edit file
sudo nano /etc/systemd/system/mev-execution.service

# Add AFTER line 34 (after EnvironmentFile=-/opt/mev-lab/.env):
```

**Paste this block:**
```ini
# LOCAL NODE ENDPOINTS - HIGHEST PRIORITY
Environment="ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_WS=ws://127.0.0.1:8546"
Environment="GETH_HTTP=http://127.0.0.1:8549"
Environment="GETH_WS=ws://127.0.0.1:8550"
Environment="LIGHTHOUSE_API=http://127.0.0.1:5052"
Environment="MEV_BOOST_URL=http://127.0.0.1:18551"
Environment="PREFER_LOCAL_NODES=true"
Environment="LOCAL_NODE_PRIORITY=true"
Environment="ENABLE_LOCAL_ERIGON_EXTRACTION=true"
Environment="ETHEREUM_RPC=http://127.0.0.1:8545"
```

### Step 2: Check Override Files (5 min)

```bash
# Check mev-pipeline override
sudo cat /etc/systemd/system/mev-pipeline.service.d/10-env.conf

# Check mev-execution override  
sudo cat /etc/systemd/system/mev-execution.service.d/env.conf
sudo cat /etc/systemd/system/mev-execution.service.d/override.conf
```

**If these contain external endpoints, update them or remove them.**

### Step 3: Reload and Restart (5 min)

```bash
sudo systemctl daemon-reload
sudo systemctl restart mev-pipeline.service
sudo systemctl restart mev-execution.service
```

### Step 4: Verify (10 min)

```bash
# Check environment
systemctl show mev-execution.service --property=Environment | grep ERIGON_HTTP

# Monitor logs
sudo journalctl -u mev-pipeline.service -f | grep -E "127.0.0.1|8545|erigon_local"
sudo journalctl -u mev-execution.service -f | grep -E "127.0.0.1|8545|erigon_local"
```

**Success indicators:**
- ✅ Logs show "127.0.0.1:8545" or "erigon_local"
- ❌ NOT showing external URLs like "publicnode.com" or "infura.io"

---

## 📋 Full Documentation

See detailed plans:
- `MEV_INFRASTRUCTURE_REMEDIATION_PLAN.md` - Complete analysis and plan
- `IMPLEMENTATION_STEPS.md` - Step-by-step guide with all commands
