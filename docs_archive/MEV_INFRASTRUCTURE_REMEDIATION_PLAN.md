# MEV Infrastructure Remediation Plan
**Date:** $(date +"%Y-%m-%d %H:%M:%S")
**Role:** Blockchain Node System Administrator
**Objective:** Ensure mev-pipeline and mev-execution services properly use local infrastructure

---

## Executive Summary

This remediation plan addresses critical issues preventing MEV services from using local blockchain infrastructure. The plan includes detailed analysis, root cause identification, and step-by-step implementation instructions.

**Current Status:**
- ✅ Local infrastructure is operational (Erigon, Lighthouse, MEV-Boost)
- ❌ MEV services are NOT using local infrastructure
- ⚠️ Services are using external RPC providers instead

**Goal:**
- ✅ All MEV services use local Erigon (127.0.0.1:8545) as primary
- ✅ Local Lighthouse Beacon API (127.0.0.1:5052) integrated
- ✅ MEV-Boost (127.0.0.1:18551) properly configured
- ✅ Proper fallback chain established

---

## Part 1: Current State Analysis

### 1.1 Infrastructure Status

#### Local Infrastructure (Available & Operational)
```
✅ Erigon HTTP RPC:      http://127.0.0.1:8545  (Block: 23,422,999)
✅ Erigon WebSocket:     ws://127.0.0.1:8546
✅ Erigon Engine API:    http://127.0.0.1:8552
✅ Geth HTTP RPC:        http://127.0.0.1:8549  (Backup - Block 0)
✅ Geth WebSocket:        ws://127.0.0.1:8550
✅ Lighthouse Beacon:    http://127.0.0.1:5052  (Operational)
✅ MEV-Boost:            http://127.0.0.1:18551  (5 relays configured)
```

#### Service Status
```
✅ erigon.service:       Active (running)
✅ lighthouse.service:   Active (running)
✅ mev-boost.service:    Active (running)
⚠️ mev-pipeline.service: Failed (timeout)
⚠️ mev-execution.service: Inactive (dead)
```

### 1.2 Configuration Analysis

#### mev-pipeline.service
**Current Configuration:**
- ✅ Environment variables correctly set for local endpoints
- ✅ `ERIGON_HTTP=http://127.0.0.1:8545` in service file
- ✅ `PREFER_LOCAL_NODES=true` configured
- ✅ `LOCAL_NODE_PRIORITY=true` configured

**Issue Identified:**
- Code uses `os.getenv()` to read environment variables
- Systemd shows environment variables are set correctly
- BUT: Application logs show external RPC usage
- **Root Cause:** Code-level RPC pool configuration may prioritize differently

**Evidence:**
- Logs: "✅ ethereum connected via https://ethereum-rpc.publicnode.com"
- NOT showing: "erigon_local" or "127.0.0.1:8545"

#### mev-execution.service
**Current Configuration:**
- ❌ NO RPC endpoint environment variables
- ❌ NO Erigon/Geth/Lighthouse configuration
- ❌ NO MEV-Boost configuration
- ⚠️ Service is inactive

**Issue Identified:**
- Completely missing local infrastructure configuration
- Relies on `.env` file which has external endpoints

### 1.3 Root Cause Analysis

#### Issue #1: Environment Variable Precedence
**Problem:**
- Systemd loads environment in this order:
  1. `EnvironmentFile=` directives (processed first)
  2. `Environment=` directives (processed after, can override)
- `.env` file at `/opt/mev-lab/.env` has external endpoints
- Application may also load `.env` directly via `python-dotenv`

**Impact:**
- Even if systemd sets correct variables, `.env` file may override
- Application code loads `.env` during startup

#### Issue #2: RPC Pool Priority Logic
**Problem:**
- `rpc_pool.py` has hardcoded `BASE_PRODUCTION_RPC_CONFIG`
- Local providers are added via `_collect_local_ethereum_providers()`
- BUT: Code checks environment variables, and `.env` has wrong values
- Fallback public RPCs may be tried first if local connection fails

**Code Flow:**
```python
# rpc_pool.py line 492-517
def _collect_local_ethereum_providers():
    env_candidates = [
        (os.getenv("ERIGON_HTTP"), "erigon_local"),
        (os.getenv("GETH_HTTP"), "geth_local"),
        ...
    ]
```

If `ERIGON_HTTP` from `.env` is Infura, it won't use local!

#### Issue #3: Missing Configuration in mev-execution.service
**Problem:**
- No RPC endpoints configured in service file
- Service relies on `.env` file which has external endpoints

---

## Part 2: Detailed Remediation Plan

### Phase 1: Immediate Fixes (Critical)

#### Task 1.1: Fix mev-execution.service Configuration
**Priority:** 🔴 CRITICAL
**Time Estimate:** 15 minutes

**Steps:**

1. **Backup current service file:**
   ```bash
   sudo cp /etc/systemd/system/mev-execution.service \
          /etc/systemd/system/mev-execution.service.backup.$(date +%Y%m%d_%H%M%S)
   ```

2. **Edit service file:**
   ```bash
   sudo nano /etc/systemd/system/mev-execution.service
   ```

3. **Add after line 34 (after `EnvironmentFile=-/opt/mev-lab/.env`):**
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
   
   # Priority and enablement flags
   Environment="PREFER_LOCAL_NODES=true"
   Environment="LOCAL_NODE_PRIORITY=true"
   Environment="ENABLE_LOCAL_ERIGON_EXTRACTION=true"
   Environment="ENABLE_LOCAL_GETH_EXTRACTION=true"
   
   # Primary RPC selection
   Environment="ETHEREUM_RPC=http://127.0.0.1:8545"
   Environment="ETH_WS_ORDER=local,127.0.0.1,localhost,alchemy,infura"
   Environment="ETH_HTTP_ORDER=local,127.0.0.1,localhost,alchemy,infura"
   ```

4. **Reload systemd and restart:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart mev-execution.service
   ```

**Verification:**
```bash
# Check environment is set correctly
systemctl show mev-execution.service --property=Environment | grep ERIGON_HTTP
# Should show: ERIGON_HTTP=http://127.0.0.1:8545

# Check logs for local endpoint usage
sudo journalctl -u mev-execution.service -f | grep -E "127.0.0.1|8545|erigon_local"
```

---

#### Task 1.2: Verify mev-pipeline.service Environment Precedence
**Priority:** 🔴 CRITICAL
**Time Estimate:** 10 minutes

**Analysis Required:**

1. **Check if application loads .env directly:**
   ```bash
   # Search for python-dotenv usage
   grep -r "load_dotenv\|python-dotenv\|from dotenv" /opt/mev-lab/src/
   
   # Check main application entry points
   grep -r "if __name__\|uvicorn\|main" /opt/mev-lab/src/services/mev_detection_service.py
   ```

2. **Verify systemd environment is correct:**
   ```bash
   systemctl show mev-pipeline.service --property=Environment | \
     grep -E "ERIGON_HTTP|127.0.0.1"
   ```

3. **Check override files:**
   ```bash
   sudo ls -la /etc/systemd/system/mev-pipeline.service.d/
   sudo cat /etc/systemd/system/mev-pipeline.service.d/*.conf
   ```

**If .env is being loaded:**
- Option A: Prevent application from loading `.env` (modify code)
- Option B: Update `.env` file to use local endpoints
- Option C: Ensure systemd environment takes precedence

---

#### Task 1.3: Update .env File (If Application Loads It)
**Priority:** ⚠️ MEDIUM (Only if Task 1.2 confirms .env loading)
**Time Estimate:** 5 minutes

**If application code loads `.env` directly:**

1. **Backup .env file:**
   ```bash
   cp /opt/mev-lab/.env /opt/mev-lab/.env.backup.$(date +%Y%m%d_%H%M%S)
   ```

2. **Update local endpoint configuration:**
   ```bash
   sudo nano /opt/mev-lab/.env
   ```

3. **Change these lines:**
   ```bash
   # BEFORE:
   ERIGON_HTTP=https://mainnet.infura.io/v3/abcb3202fd8f4923bf589d0677ba3dd0
   ERIGON_WS=wss://mainnet.infura.io/ws/v3/abcb3202fd8f4923dd0
   ENABLE_LOCAL_ERIGON_EXTRACTION=false
   ENABLE_LOCAL_GETH_EXTRACTION=false
   
   # AFTER:
   ERIGON_HTTP=http://127.0.0.1:8545
   ERIGON_WS=ws://127.0.0.1:8546
   ENABLE_LOCAL_ERIGON_EXTRACTION=true
   ENABLE_LOCAL_GETH_EXTRACTION=true
   ```

4. **Keep Infura as fallback (optional):**
   ```bash
   ERIGON_FALLBACK_HTTP=https://mainnet.infura.io/v3/abcb3202fd8f4923bf589d0677ba3dd0
   ERIGON_FALLBACK_WS=wss://mainnet.infura.io/ws/v3/abcb3202fd8f4923bf589d0677ba3dd0
   ```

---

### Phase 2: Code-Level Fixes (If Needed)

#### Task 2.1: Verify RPC Pool Priority
**Priority:** ⚠️ MEDIUM
**Time Estimate:** 20 minutes

**Analysis:**

1. **Review RPC pool initialization:**
   ```bash
   grep -A 30 "build_production_rpc_config\|BASE_PRODUCTION_RPC_CONFIG" \
     /opt/mev-lab/src/core/config/rpc_pool.py
   ```

2. **Verify local providers are first in priority:**
   - Code should add local providers BEFORE public providers
   - Check `build_production_rpc_config()` function

**If issue found:**

1. **Edit RPC pool configuration:**
   ```bash
   sudo nano /opt/mev-lab/src/core/config/rpc_pool.py
   ```

2. **Ensure local providers are added first:**
   ```python
   def build_production_rpc_config():
       config = {}
       for network, providers in BASE_PRODUCTION_RPC_CONFIG.items():
           if network == "ethereum":
               # CRITICAL: Local providers MUST be added FIRST
               local_providers = _collect_local_ethereum_providers()
               # Local providers come first, then public fallbacks
               config[network] = _unique_providers(
                   local_providers + providers  # Local first!
               )
   ```

3. **Verify priority in BASE_PRODUCTION_RPC_CONFIG:**
   - Line 435-446: Should show local endpoints as priority 1

---

#### Task 2.2: Add Connection Health Checks
**Priority:** ⚠️ LOW (Enhancement)
**Time Estimate:** 30 minutes

**Goal:** Ensure local endpoints are tested before fallback

**Implementation:**

1. **Add startup health check:**
   - Verify Erigon is accessible before starting service
   - Fail fast if local endpoint unavailable

2. **Add periodic health monitoring:**
   - Monitor local endpoint availability
   - Log when fallback to external RPC occurs

---

### Phase 3: Service Optimization

#### Task 3.1: Fix Service Dependencies
**Priority:** ⚠️ MEDIUM
**Time Estimate:** 10 minutes

**Current Issues:**
- Services may start before infrastructure is ready
- No health checks for dependencies

**Fixes:**

1. **Update mev-pipeline.service:**
   ```ini
   [Unit]
   After=network-online.target erigon.service lighthouse.service mev-boost.service
   Wants=network-online.target erigon.service lighthouse.service mev-boost.service
   # Add startup check
   ExecStartPre=/bin/bash -c 'timeout 5 curl -s http://127.0.0.1:8545 >/dev/null || exit 1'
   ```

2. **Update mev-execution.service:**
   ```ini
   [Unit]
   After=network-online.target mev-pipeline.service erigon.service
   Wants=network-online.target mev-pipeline.service erigon.service
   ExecStartPre=/bin/bash -c 'timeout 5 curl -s http://127.0.0.1:8545 >/dev/null || exit 1'
   ```

---

#### Task 3.2: Add MEV-Boost Integration
**Priority:** ⚠️ MEDIUM
**Time Estimate:** 15 minutes

**Configuration:**

1. **Add to both services:**
   ```ini
   Environment="MEV_BOOST_URL=http://127.0.0.1:18551"
   Environment="MEV_BOOST_WS=ws://127.0.0.1:18551"
   Environment="ENABLE_MEV_BOOST=true"
   ```

2. **Verify MEV-Boost is accessible:**
   ```bash
   curl http://127.0.0.1:18551/eth/v1/builder/status
   ```

---

### Phase 4: Monitoring & Verification

#### Task 4.1: Create Monitoring Script
**Priority:** ⚠️ LOW (Post-implementation)
**Time Estimate:** 20 minutes

**Script to verify local endpoint usage:**

```bash
#!/bin/bash
# /opt/mev-lab/scripts/verify-local-endpoints.sh

echo "=== MEV Services Local Endpoint Verification ==="

# Check mev-pipeline
echo ""
echo "1. mev-pipeline.service:"
systemctl show mev-pipeline.service --property=Environment | \
  grep -q "ERIGON_HTTP=http://127.0.0.1:8545" && \
  echo "   ✅ Local endpoint configured" || \
  echo "   ❌ Local endpoint NOT configured"

journalctl -u mev-pipeline.service --since "5 minutes ago" | \
  grep -q "127.0.0.1:8545\|erigon_local" && \
  echo "   ✅ Using local endpoint" || \
  echo "   ⚠️  May be using external RPC"

# Check mev-execution
echo ""
echo "2. mev-execution.service:"
systemctl show mev-execution.service --property=Environment | \
  grep -q "ERIGON_HTTP=http://127.0.0.1:8545" && \
  echo "   ✅ Local endpoint configured" || \
  echo "   ❌ Local endpoint NOT configured"

# Check infrastructure
echo ""
echo "3. Infrastructure Status:"
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 >/dev/null && \
  echo "   ✅ Erigon RPC accessible" || \
  echo "   ❌ Erigon RPC NOT accessible"

curl -s http://127.0.0.1:5052/eth/v1/node/health >/dev/null && \
  echo "   ✅ Lighthouse Beacon API accessible" || \
  echo "   ❌ Lighthouse Beacon API NOT accessible"
```

---

#### Task 4.2: Add Log Monitoring
**Priority:** ⚠️ LOW (Enhancement)
**Time Estimate:** 15 minutes

**Set up alerts for external RPC usage:**

```bash
# Add to monitoring system
journalctl -u mev-pipeline.service -f | \
  grep -E "connected via https://" | \
  grep -v "127.0.0.1" | \
  # Alert if external RPC used
```

---

## Part 3: Implementation Steps

### Step-by-Step Execution Plan

#### Day 1: Critical Fixes (Immediate)

**Morning Session (1-2 hours):**

1. **Task 1.1: Fix mev-execution.service** (15 min)
   - Backup service file
   - Add local endpoint configuration
   - Reload and restart service
   - Verify configuration

2. **Task 1.2: Analyze mev-pipeline.service** (30 min)
   - Check for .env loading in code
   - Verify systemd environment
   - Document findings

3. **Task 1.3: Update .env if needed** (10 min)
   - Only if code loads .env directly
   - Update to use local endpoints
   - Keep external as fallback

4. **Verification** (15 min)
   - Check service logs
   - Verify local endpoint usage
   - Test infrastructure connectivity

**Afternoon Session (2-3 hours):**

5. **Task 3.1: Fix service dependencies** (20 min)
   - Add health checks
   - Update After/Wants directives

6. **Task 3.2: Add MEV-Boost integration** (15 min)
   - Configure MEV-Boost endpoints
   - Verify accessibility

7. **Task 4.1: Create monitoring script** (30 min)
   - Write verification script
   - Test monitoring

8. **Full System Test** (30 min)
   - Restart all services
   - Monitor for 15 minutes
   - Verify all connections

---

#### Day 2: Code-Level Fixes (If Needed)

**If Phase 1 reveals code-level issues:**

9. **Task 2.1: Fix RPC pool priority** (30 min)
   - Review and fix priority logic
   - Ensure local-first configuration

10. **Task 2.2: Add health checks** (30 min)
    - Implement connection validation
    - Add startup checks

---

## Part 4: Verification Checklist

### Pre-Implementation Checklist
- [ ] Backup all service files
- [ ] Backup .env file
- [ ] Document current behavior
- [ ] Prepare rollback plan

### Post-Implementation Checklist
- [ ] Services start successfully
- [ ] Logs show local endpoint usage
- [ ] No external RPC connections (unless local fails)
- [ ] Infrastructure monitoring confirms local connections
- [ ] Service dependencies resolve correctly
- [ ] MEV-Boost integration working

### Success Criteria
- ✅ `journalctl -u mev-pipeline.service` shows: "erigon_local" or "127.0.0.1:8545"
- ✅ `journalctl -u mev-execution.service` shows: "erigon_local" or "127.0.0.1:8545"
- ✅ Services NOT showing: "https://ethereum-rpc.publicnode.com" or Infura URLs
- ✅ Systemd environment variables verified correct
- ✅ All services operational and using local infrastructure

---

## Part 5: Rollback Plan

### If Issues Occur:

1. **Immediate Rollback:**
   ```bash
   # Restore service files
   sudo cp /etc/systemd/system/mev-execution.service.backup.* \
          /etc/systemd/system/mev-execution.service
   
   # Restore .env if modified
   cp /opt/mev-lab/.env.backup.* /opt/mev-lab/.env
   
   # Reload and restart
   sudo systemctl daemon-reload
   sudo systemctl restart mev-pipeline.service
   sudo systemctl restart mev-execution.service
   ```

2. **Verify Rollback:**
   - Check service status
   - Verify functionality restored

---

## Part 6: Long-Term Best Practices

### Configuration Management
1. **Centralized Configuration:**
   - Use systemd environment for production
   - Keep .env for development only
   - Document all endpoint configurations

2. **Version Control:**
   - Track service file changes
   - Maintain change log
   - Document rationale for changes

3. **Testing:**
   - Test changes in staging first
   - Verify local endpoint connectivity
   - Monitor for 24 hours post-change

### Monitoring
1. **Alerting:**
   - Alert on external RPC usage (unless local down)
   - Monitor local endpoint health
   - Track service startup times

2. **Dashboards:**
   - Show local vs external RPC usage
   - Monitor endpoint response times
   - Track fallback events

---

## Conclusion

This remediation plan provides a comprehensive approach to ensuring MEV services properly use local infrastructure. The phased approach allows for incremental implementation with verification at each step.

**Estimated Total Time:** 4-6 hours (including testing)
**Risk Level:** Low (with proper backups and rollback plan)
**Expected Outcome:** 100% local infrastructure usage for MEV operations
