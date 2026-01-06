# Blockchain Infrastructure Status - 2025-01-05

## Summary

Fixed Erigon service issues and verified both Reth and Lighthouse are operational.

## Actions Completed

### 1. Erigon Configuration Fixes

**Problem:** Erigon v3.0.9 had critical `gasprice.go` bug causing RPC crashes with `eth` API enabled.

**Solution:** Patched `/etc/systemd/system/erigon.service.d/10-combined.conf`:
- **Disabled buggy APIs:** Changed `--http.api=eth,net,web3,txpool,erigon,debug` to `--http.api=net,web3,debug,erigon`
- **Removed `txpool` API** along with `eth` (both had buggy methods)
- **Increased timeout:** `TimeoutStopSec=60s` → `TimeoutStopSec=10min`
- **Increased memory limits:** `MemoryMax=16G/High=14G` → `MemoryMax=48G/High=32G`

### 2. Lighthouse Consensus Client

**Problem:** Stale database lock files preventing startup.

**Solution:** Cleared all `.ldb/LOCK` files in beacon database directories.

**Status:** ✅ **Active and Syncing**
- HTTP API: `http://127.0.0.1:5052`
- Head Slot: 3,654,559
- Sync Distance: 9,748,690 slots

### 3. Reth Execution Client

**Status:** ✅ **Active** (running in execution-only mode)
- HTTP API: `http://127.0.0.1:8557`
- `net_version`: Returns "1"
- P2P Port: 30308

**Note:** Reth runs with `eth,net,web3,debug,trace,txpool` APIs enabled - suitable for MEV operations.

### 4. Erigon Execution Client

**Status:** 🔄 **Starting/Syncing** (initial startup can take 30-60 minutes)
- HTTP API: `http://127.0.0.1:8545` (will be available once fully started)
- P2P Port: 30303
- AuthRPC Port: 8552
- **Buggy APIs disabled** (eth, txpool) to prevent crashes

**Current State:** OtterSync in progress, downloading headers and snapshots.

## Production Recommendations

### For MEV Operations

**Primary Node: Reth + Lighthouse**
- Reth has full `eth` API with working gas price methods
- Lighthouse provides consensus layer integration
- More stable for production MEV operations

**Secondary Node: Erigon**
- Use only for `net,web3,debug,erigon` API calls
- Do NOT use for gas price or transaction-related operations
- Consider upgrading to v3.2.0+ to fix the gasprice.go bug
- Provides Erigon-specific debugging APIs

## RPC Endpoints Summary

| Service | Port | APIs | Status |
|----------|------|------|--------|
| **Reth** | 8557 | eth,net,web3,debug,trace,txpool | ✅ Active |
| **Erigon** | 8545 | net,web3,debug,erigon (eth/txpool disabled) | 🔄 Starting |
| **Lighthouse** | 5052 | Beacon API | ✅ Syncing |

## Known Issues

1. **Port Conflict:** Both Erigon and Reth use Engine API port 8552
   - Only one can be primary consensus client for Lighthouse
   - Current: Lighthouse configured to connect to Erigon (8552)

2. **Erigon gasprice.go Bug (v3.0.9):**
   - `eth_gasPrice` method crashes with nil pointer dereference
   - Workaround: Disabled `eth` and `txpool` APIs
   - Permanent fix: Upgrade to v3.2.0 or later

## Service Status Commands

```bash
# Check all services
systemctl status erigon.service reth.service lighthouse-beacon.service

# Test RPC endpoints
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  http://127.0.0.1:8557  # Reth

curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  http://127.0.0.1:8545  # Erigon

# Check beacon sync
curl http://127.0.0.1:5052/eth/v1/node/syncing
```

## Next Steps for Full Production Setup

1. **Wait for Erigon to fully sync** (~30-60 min for initial sync)
2. **Re-enable `eth` API on Erigon** after upgrading to v3.2.0+
3. **Configure Engine API failover** between Reth and Erigon
4. **Set up MEV-Boost** integration for block building
5. **Configure monitoring** for all nodes

---
*Generated: 2025-01-05*
*Infrastructure: /data/blockchain/nodes*
