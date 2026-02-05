# Erigon v3.2.0 Remediation Plan

**Date:** 2026-01-06
**Issue:** Erigon startup hang at "adjusting receipt current version to v1.1"
**Version:** Erigon v3.2.0-3418e071 (v3.2.0 "Quirky Quests")
**Database Size:** 37GB mdbx.dat (830GB total directory)

---

## Executive Summary

Erigon v3.2.0 fails to start due to a database configuration mismatch related to receipt storage. The database was created with `persist.receipts=false` but Erigon v3.2.0 defaults to `persist.receipts=true`, causing an incompatible state transition during startup.

---

## Problem Analysis

### Root Cause
```
[WARN] --persist.receipt changed since the last run, enabling historical receipts cache.
       full resync will be required to use the new configuration.
       inDB=false inConfig=true
[INFO] adjusting receipt current version to v1.1
[EROR] Process hangs for 5-10 seconds, then killed by systemd
```

### What's Happening
1. **Database Metadata**: The Erigon database (MDBX) stores receipt domain configuration
2. **Version Mismatch**: Database was created with `persist.receipts=false`
3. **Runtime Detection**: Erigon v3.2.0 detects this mismatch and attempts to "adjust" the receipt domain
4. **Hang Condition**: The adjustment operation hangs indefinitely (likely due to large database size - 830GB)

### Historical Context
- **October 2025**: Issue first appeared; Erigon would run ~15 minutes before being killed
- **During this period**: Erigon successfully synced to **99.5%** (block 23,578,999 / ~23.6M)
- **January 2026**: Issue persists; Erigon cannot get past startup

---

## Related Issues

| Issue | Link | Status |
|-------|------|--------|
| #7355 | [Mismatched receipt headers](https://github.com/erigontech/erigon/issues/7355) | Closed as "not planned" |
| #9895 | [Mismatched receipt headers for block 16468656](https://github.com/erigontech/erigon/issues/9895) | Unknown |
| #14371 | [Receipt RPC latency](https://github.com/erigontech/erigon/issues/14371) | Open |

---

## Remediation Options

### Option A: Update to Erigon v3.3.x "Rocky Romp" (Recommended)

**Rationale:** Newer versions may include fixes for receipt handling.

**Steps:**
```bash
# 1. Backup current database
sudo systemctl stop erigon.service
sudo mv /data/blockchain/storage/erigon /data/blockchain/storage/erigon_backup_20260106

# 2. Download latest Erigon v3.3.x
cd /tmp
wget https://github.com/erigontech/erigon/releases/download/v3.3.2/erigon_3.3.2_amd64.deb
sudo dpkg -i erigon_3.3.2_amd64.deb

# 3. Verify version
/usr/local/bin/erigon --version

# 4. Start with new data directory (will resync from snapshots)
sudo systemctl start erigon.service
```

**Pros:**
- Latest bug fixes and improvements
- Potentially resolves receipt domain issue
- Better sync performance

**Cons:**
- Requires full resync (830GB lost)
- Takes 1-2 days with snapshots

**Estimated Time:** 1-2 days

---

### Option B: Reset Receipt Domain with Database Surgery

**Rationale:** Manually reset the receipt domain configuration in the database.

**Steps:**
```bash
# 1. Stop Erigon and backup
sudo systemctl stop erigon.service
sudo cp -a /data/blockchain/storage/erigon /data/blockchain/storage/erigon_backup_before_fix

# 2. Use Erigon's snapshots command to rebuild receipt domain
/usr/local/bin/erigon --datadir /data/blockchain/storage/erigon snapshots \
    rebuild-receipt-domain --force

# 3. Start Erigon
sudo systemctl start erigon.service
```

**Pros:**
- Preserves existing sync data
- Potentially faster than full resync

**Cons:**
- Experimental (may not work)
- Risk of database corruption

**Estimated Time:** Unknown (could fail)

---

### Option C: Disable Receipt Processing Entirely

**Rationale:** Skip receipt domain processing by using a configuration that avoids it.

**Steps:**
```bash
# Update Erigon service to use minimal mode
sudo tee /etc/systemd/system/erigon.service.d/10-combined.conf > /dev/null << 'EOF'
[Unit]
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
ExecStart=
ExecStart=/usr/local/bin/erigon \
    --datadir=/data/blockchain/storage/erigon \
    --chain=mainnet \
    --prune.mode=minimal \
    --http.addr=127.0.0.1 \
    --http.port=8545 \
    --http.api=eth,net,web3 \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port=8552 \
    --authrpc.jwtsecret=/data/blockchain/storage/erigon/jwt.hex \
    --maxpeers=100 \
    --snap.skip-state-snapshot-download=false

CPUQuota=400%
MemoryMax=48G
Restart=always
RestartSec=60
TimeoutStartSec=30min
EOF

sudo systemctl daemon-reload
sudo systemctl start erigon.service
```

**Pros:**
- Preserves existing data
- Avoids receipt domain processing

**Cons:**
- Loses receipt historical data
- `eth_getBlockReceipts` will have higher latency

**Estimated Time:** 30-60 minutes testing

---

### Option D: Start Fresh with Snapshot Sync (Fastest)

**Rationale:** Use Erigon's snapshot download to get a fresh, clean database.

**Steps:**
```bash
# 1. Stop Erigon and backup current database
sudo systemctl stop erigon.service
sudo mv /data/blockchain/storage/erigon /data/blockchain/storage/erigon_old_20260106

# 2. Create fresh data directory
sudo mkdir -p /data/blockchain/storage/erigon

# 3. Initialize with snapshots
/usr/local/bin/erigon --datadir /data/blockchain/storage/erigon snapshots download

# 4. Start Erigon
sudo systemctl start erigon.service
```

**Pros:**
- Clean database with known good state
- Fastest path to operational Erigon
- Avoids configuration mismatches

**Cons:**
- Loses 99.5% sync progress
- Requires downloading 800GB+ of snapshots

**Estimated Time:** 6-12 hours (snapshot download)

---

### Option E: Continue Using Geth (Current Status)

**Rationale:** Geth is working and properly connected to Lighthouse.

**Status:**
- Geth v1.16.4: Running, syncing from genesis
- Lighthouse v7.0.1: Running, connected to Geth
- Both are properly configured with JWT authentication

**Configuration:**
- Execution: Geth (HTTP 8549, Engine API 8554)
- Consensus: Lighthouse (HTTP 5052)
- JWT: `/data/blockchain/storage/jwt-secret-common.hex`

**Pros:**
- Already working
- No additional setup required
- Stable, battle-tested software

**Cons:**
- Syncing from genesis takes 2-3 weeks
- Geth uses more disk space than Erigon

**Estimated Time:** 2-3 weeks to full sync

---

## Recommended Action Plan

### Phase 1: Immediate (Today)
**Action:** Continue with Geth + Lighthouse
- Geth is already running and syncing
- Lighthouse is connected properly
- Focus on getting other infrastructure ready while syncing

### Phase 2: Short-term (This Week)
**Action:** Try Option C (Disable Receipt Processing)
1. Update Erigon service with `--prune.mode=minimal`
2. Test if Erigon starts successfully
3. If successful, Erigon can serve as backup/archive node

### Phase 3: Medium-term (Next 1-2 Weeks)
**Action:** If Option C fails, implement Option D (Fresh Snapshot Sync)
1. Download Erigon v3.3.2 for latest improvements
2. Use snapshot sync for fastest deployment
3. Run parallel to Geth for redundancy

### Phase 4: Long-term (After Sync Complete)
**Action:** Evaluate and choose primary execution client
- Compare performance: Geth vs Erigon
- Consider MEV operations requirements
- Keep both for redundancy

---

## Configuration Files

### Current Working Configuration (Geth + Lighthouse)

**`/etc/systemd/system/geth.service`:**
```ini
[Unit]
Description=Geth Ethereum Client (Execution Layer)
Conflicts=erigon.service reth.service

[Service]
Type=simple
User=lyftium
ExecStart=/usr/bin/geth \
    --datadir /data/blockchain/storage/geth \
    --mainnet \
    --syncmode=snap \
    --gcmode=full \
    --cache=4096 \
    --maxpeers=75 \
    --http.addr 127.0.0.1 \
    --http.port 8549 \
    --http.api eth,net,web3,debug,txpool,admin \
    --authrpc.addr 127.0.0.1 \
    --authrpc.port 8554 \
    --authrpc.jwtsecret /data/blockchain/storage/jwt-secret-common.hex

Restart=always
RestartSec=30
```

**`/data/blockchain/nodes/consensus/lighthouse/start-lighthouse-beacon.sh`:**
```bash
#!/bin/bash
NETWORK="mainnet"
DATA_DIR="/data/blockchain/nodes/consensus/lighthouse"
JWT_SECRET="/data/blockchain/storage/jwt-secret-common.hex"
GETH_ENDPOINT="http://127.0.0.1:8554"

exec /home/lyftium/.cargo/bin/lighthouse beacon_node \
    --network "${NETWORK}" \
    --datadir "${DATA_DIR}" \
    --execution-endpoint "${GETH_ENDPOINT}" \
    --execution-jwt="${JWT_SECRET}" \
    --port 9003 \
    --http \
    --http-address 127.0.0.1 \
    --http-port 5052 \
    --http-allow-origin "*" \
    --allow-insecure-genesis-sync \
    --metrics
```

---

## Monitoring Commands

### Check Geth Status
```bash
systemctl status geth.service
curl -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://127.0.0.1:8549
```

### Check Lighthouse Status
```bash
systemctl status lighthouse-beacon.service
curl http://127.0.0.1:5052/eth/v1/node/syncing
```

### Check Erigon Logs
```bash
journalctl -u erigon.service -f
tail -f /data/blockchain/storage/erigon/logs/erigon.log
```

---

## Success Criteria

- [ ] Geth syncing without errors
- [ ] Lighthouse connected to Geth (el_offline: false)
- [ ] Both services stable for 24+ hours
- [ ] MEV operations ready once fully synced

---

## Rollback Plan

If any remediation attempt fails:
```bash
# Stop affected service
sudo systemctl stop erigon.service

# Restore backup
sudo rm -rf /data/blockchain/storage/erigon
sudo mv /data/blockchain/storage/erigon_backup_YYYYMMDD /data/blockchain/storage/erigon

# Restart
sudo systemctl start erigon.service
```

---

## Sources

- [Erigon Issue #7355 - Mismatched receipt headers](https://github.com/erigontech/erigon/issues/7355)
- [Erigon Releases](https://github.com/erigontech/erigon/releases)
- [Erigon Documentation](https://docs.erigon.tech/)
- [Erigon Options v3.1](https://docs.erigon.tech/erigon/v3.1/advanced/options)
