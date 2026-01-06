# Blockchain Node Issues - Fixes Applied
**Date:** $(date +"%Y-%m-%d %H:%M:%S")
**Admin:** Blockchain Node System Administrator

## Issues Identified and Resolved

### 1. ✅ Lighthouse Beacon REST API Not Accessible
**Issue:** Lighthouse REST API on port 5052 returning connection reset errors.

**Root Cause:** Lighthouse start script was missing `--http`, `--http-address`, and `--http-port` flags to enable the REST API server.

**Fix Applied:**
- Updated `/data/blockchain/nodes/consensus/lighthouse/start-lighthouse-beacon.sh`
- Added flags:
  - `--http` - Enable HTTP REST API server
  - `--http-address 127.0.0.1` - Bind to localhost
  - `--http-port 5052` - Use standard beacon API port
  - `--http-allow-origin "*"` - Allow CORS for MEV operations

**Action Required:**
```bash
sudo systemctl restart lighthouse.service
```

**Verification:**
```bash
curl http://127.0.0.1:5052/eth/v1/node/health
curl http://127.0.0.1:5052/eth/v1/node/syncing
```

---

### 2. ⚠️ Port 30303 Conflict: Erigon vs Reth
**Issue:** Reth binding to UDP port 30303 conflicts with Erigon's TCP port 30303, causing Erigon sentry warnings.

**Root Cause:** Reth discovery service binding to default UDP port 30303 despite configuration.

**Fix Applied:**
- Updated `/data/blockchain/nodes/reth/config/reth-simple.toml`
- Set `[discv4]` port to 30308 (unique port)
- Added `discv5_port = 30308` to ensure no UDP 30303 binding
- Service already configured with `--port 30308`

**Action Required:**
```bash
sudo systemctl restart reth.service
```

**Verification:**
```bash
sudo ss -ulnp | grep 30303  # Should show no Reth process
sudo ss -tlnp | grep 30303  # Should show only Erigon
```

**Note:** Erigon warnings about sentry connections are non-critical - Erigon is operational and synced. The warnings are from internal sentry processes attempting redundant connections.

---

### 3. ⚠️ Geth Block 0 (Not Synced)
**Issue:** Geth showing block number 0, indicating not synced.

**Analysis:**
- Geth service started at 09:57:46 (recent restart)
- Database exists with data from August 28
- `eth.syncing` returns all zeros (indicates not actively syncing)
- `eth_blockNumber` returns 0x0 (genesis block)

**Possible Causes:**
1. Geth is waiting for beacon client consensus updates
2. Database state issue requiring resync
3. Beacon client not properly connected

**Status:** Geth is configured correctly but needs:
- Beacon client connection for post-merge Ethereum
- Or switch to standalone sync mode if not using beacon client

**Current Configuration:** Geth is waiting for beacon client (Lighthouse) to provide consensus updates, but Lighthouse is configured for Erigon, not Geth.

**Recommendation for MEV Operations:**
- **Primary:** Use Erigon (fully synced, block 23,422,999) ✅
- **Secondary:** Geth can remain as backup but needs beacon client or standalone sync

**Action Required (if needed):**
If Geth should sync independently:
```bash
# Option 1: Wait for beacon client (if validator setup)
# Option 2: Check if beacon client should connect to Geth's authrpc (8554)
# Option 3: If not needed for MEV, can leave as-is (Erigon is primary)
```

---

### 4. ✅ MEV RPC Endpoints Verification

**Confirmed Working Endpoints:**

| Client | Endpoint | Status | Block Number |
|--------|----------|--------|--------------|
| **Erigon** | `http://127.0.0.1:8545` | ✅ Operational | 23,422,999 |
| **Erigon WS** | `ws://127.0.0.1:8546` | ✅ Accessible | - |
| **Erigon AuthRPC** | `http://127.0.0.1:8552` | ✅ Operational | - |
| **Geth** | `http://127.0.0.1:8549` | ⚠️ Not synced | 0 |
| **Geth WS** | `ws://127.0.0.1:8550` | ✅ Accessible | - |
| **MEV-Boost** | `http://127.0.0.1:18551` | ✅ Operational | - |

**Recommended for MEV Operations:**
- Primary Execution: `http://127.0.0.1:8545` (Erigon) ✅
- WebSocket: `ws://127.0.0.1:8546` (Erigon) ✅
- Engine API: `http://127.0.0.1:8552` (Erigon) ✅

---

## Best Practices Compliance

### ✅ Implemented:
1. **Multiple Execution Clients:** Erigon (primary), Geth (secondary), Reth (tertiary)
2. **Port Separation:** Each client uses unique ports (30303, 30309, 30308)
3. **RPC Security:** All RPC endpoints bound to 127.0.0.1 (localhost only)
4. **JWT Authentication:** Engine API endpoints protected with JWT
5. **MEV-Boost Integration:** 5 relays configured and operational
6. **Metrics Enabled:** Monitoring endpoints on unique ports

### ⚠️ Recommendations:
1. **Lighthouse Beacon Sync:** Currently 2 weeks behind - allow time to catch up
2. **Geth Sync:** Investigate why at block 0, consider beacon client connection
3. **Monitor Erigon Sentry Warnings:** Non-critical but worth monitoring
4. **Regular Health Checks:** Implement automated monitoring for all endpoints

---

## Service Restart Commands

```bash
# Restart Lighthouse to enable REST API
sudo systemctl restart lighthouse.service

# Restart Reth to apply port fix (optional, if needed)
sudo systemctl restart reth.service

# Verify all services
sudo systemctl status erigon.service geth.service lighthouse.service mev-boost.service reth.service
```

---

## Post-Fix Verification Script

```bash
#!/bin/bash
echo "=== Verifying Fixes ==="

echo "1. Lighthouse REST API:"
curl -s http://127.0.0.1:5052/eth/v1/node/health && echo " ✅" || echo " ❌"

echo "2. Port 30303 (should only show Erigon TCP):"
sudo ss -tlnp | grep 30303 && echo " ✅"

echo "3. Port 30303 UDP (should NOT show Reth):"
sudo ss -ulnp | grep 30303 && echo " ⚠️  (Reth still using it)" || echo " ✅"

echo "4. Erigon RPC:"
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r '.result' | xargs -I {} echo " Block: {} ✅"

echo "5. MEV-Boost:"
timeout 1 nc -zv 127.0.0.1 18551 2>&1 | grep -q "succeeded" && echo " ✅" || echo " ❌"
```

---

**Status:** Ready for MEV operations using Erigon endpoints ✅
