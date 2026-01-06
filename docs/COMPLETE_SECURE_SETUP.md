# Complete Secure Setup - API Keys from .env
**Final Implementation: Secure Multi-Tier Infrastructure**
**Date:** $(date +"%Y-%m-%d %H:%M:%S")

---

## ✅ Secure Configuration Status

### Security Verification:
- ✅ .env file: 600 permissions (secure)
- ✅ API keys: Present in .env file
- ⚠️ Need to verify: Service files don't expose keys
- ⚠️ Need to ensure: .env is loaded by services

---

## Complete Secure Implementation

### Architecture: Secure 3-Tier with API Key Protection

```
┌─────────────────────────────────────────────┐
│  API Keys (PRIVATE)                          │
│  /opt/mev-lab/.env (600 permissions)        │
└───────────────┬───────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────┐
│  Systemd EnvironmentFile                     │
│  Loads .env securely                        │
└───────────────┬───────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────┐
│  Service Environment                         │
│  INFURA_API_KEY, ALCHEMY_API_KEY available │
└───────────────┬───────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────┐
│  Application Code                            │
│  Reads keys → Builds URLs → RPC Pool         │
└───────────────┬───────────────────────────────┘
                │
    ┌───────────┴───────────┐
    │   3-Tier RPC Pool    │
    │   (Smart Balancing) │
    └───────────┬───────────┘
                │
    ┌───────────┼───────────┐
    │           │           │
┌───▼───┐  ┌───▼───┐  ┌───▼───┐
│TIER 1 │  │TIER 2 │  │TIER 3 │
│LOCAL  │  │CLOUD  │  │PUBLIC │
└───────┘  └───────┘  └───────┘
```

---

## Step-by-Step Secure Implementation

### Step 1: Verify .env File Security ✅

```bash
# Already done:
# - Permissions: 600 ✅
# - Owner: lyftium:lyftium ✅
# - API keys present ✅
```

### Step 2: Ensure .env is Loaded by Services

**Current Status:**
- mev-pipeline.service: Has `EnvironmentFile=-/etc/mev-lab/env` (line 14)
- mev-execution.service: Has `EnvironmentFile=-/opt/mev-lab/.env` (line 34)

**Action:** Verify /etc/mev-lab/env also loads, or ensure services load /opt/mev-lab/.env

**Check what /etc/mev-lab/env contains:**
```bash
sudo cat /etc/mev-lab/env 2>/dev/null | head -10
```

**If it doesn't have API keys, ensure .env is loaded:**

Update mev-pipeline.service to explicitly load .env:
```bash
# The service already has EnvironmentFile=-/etc/mev-lab/env
# Add .env loading if not present:
sudo nano /etc/systemd/system/mev-pipeline.service
# Ensure line has: EnvironmentFile=-/opt/mev-lab/.env
```

### Step 3: Create Service Override (NO API Keys!)

**File:** `/etc/systemd/system/mev-pipeline.service.d/rpc-endpoints.conf`

```ini
[Service]
# ============================================
# TIER 1: LOCAL NODES (Public endpoints)
# ============================================
Environment="ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_WS=ws://127.0.0.1:8546"
Environment="LOCAL_ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_RPC_URL=http://127.0.0.1:8545"

Environment="GETH_HTTP=http://127.0.0.1:8549"
Environment="GETH_WS=ws://127.0.0.1:8550"
Environment="LOCAL_GETH_HTTP=http://127.0.0.1:8549"
Environment="GETH_RPC_URL=http://127.0.0.1:8549"

# ============================================
# TIER 2: CLOUD ENDPOINTS
# API keys loaded from .env file via EnvironmentFile
# Application code will read INFURA_API_KEY, ALCHEMY_API_KEY
# and build URLs: https://...v3/{INFURA_API_KEY}
# DO NOT put API keys or full URLs here!
# ============================================

# ============================================
# LOAD BALANCING
# ============================================
Environment="PREFER_LOCAL_NODES=true"
Environment="LOCAL_NODE_PRIORITY=true"
Environment="HEALTH_CHECK_INTERVAL=30"
Environment="RATE_LIMIT_DETECTION=true"
Environment="CIRCUIT_BREAKER_ENABLED=true"
```

**Same for mev-execution.service.d/rpc-endpoints.conf**

### Step 4: Update Application Code

**File:** `/opt/mev-lab/src/core/config/rpc_pool.py`

Add secure cloud provider collection:

```python
def _collect_cloud_ethereum_providers() -> list:
    """Collect cloud endpoints - securely build URLs from API keys."""
    providers = []
    
    # Infura - build URL from API key (secure)
    infura_key = os.getenv("INFURA_API_KEY")
    if infura_key:
        providers.append({
            "url": f"https://mainnet.infura.io/v3/{infura_key}",
            "name": "infura_primary",
            "priority": 2,  # Tier 2
            "weight": 60,
        })
        # WebSocket endpoint
        providers.append({
            "url": f"wss://mainnet.infura.io/ws/v3/{infura_key}",
            "name": "infura_ws",
            "priority": 2,
            "weight": 60,
        })
    
    # Alchemy - build URL from API key (secure)
    alchemy_key = os.getenv("ALCHEMY_API_KEY")
    if alchemy_key:
        providers.append({
            "url": f"https://eth-mainnet.g.alchemy.com/v2/{alchemy_key}",
            "name": "alchemy_primary",
            "priority": 2,
            "weight": 60,
        })
        # WebSocket endpoint
        providers.append({
            "url": f"wss://eth-mainnet.g.alchemy.com/v2/{alchemy_key}",
            "name": "alchemy_ws",
            "priority": 2,
            "weight": 60,
        })
    
    # QuickNode - use endpoint directly
    quicknode = os.getenv("QUICKNODE_ENDPOINT") or os.getenv("QUICKNODE_HTTP")
    if quicknode:
        providers.append({
            "url": quicknode,
            "name": "quicknode_primary",
            "priority": 2,
            "weight": 50,
        })
    
    return _unique_providers(providers)
```

Update `build_production_rpc_config()`:

```python
def build_production_rpc_config() -> dict[str, list[dict[str, str]]]:
    """Build production RPC config with secure tiered priority."""
    config: dict[str, list[dict[str, str]]] = {}
    
    for network, base_providers in BASE_PRODUCTION_RPC_CONFIG.items():
        if network == "ethereum":
            # Collect by tier (secure - builds URLs from keys)
            tier_1_local = _collect_local_ethereum_providers()
            tier_2_cloud = _collect_cloud_ethereum_providers()  # NEW - secure
            
            # Set priorities and weights for local
            for provider in tier_1_local:
                provider["priority"] = 1
                if "erigon" in provider.get("name", ""):
                    provider["weight"] = 100
                elif "geth" in provider.get("name", ""):
                    provider["weight"] = 80
            
            # Combine: Local (Priority 1) -> Cloud (Priority 2) -> Public (Priority 3+)
            config[network] = _unique_providers(
                tier_1_local + tier_2_cloud + base_providers
            )
        else:
            config[network] = list(base_providers)
    
    return config
```

---

## Complete Implementation Script

```bash
#!/bin/bash
# Complete Secure Setup Script

echo "=== Secure Multi-Tier Infrastructure Setup ==="
echo ""

# 1. Secure .env file
echo "1. Securing .env file..."
chmod 600 /opt/mev-lab/.env
chown lyftium:lyftium /opt/mev-lab/.env
echo "✅ .env file secured (600 permissions)"

# 2. Create service overrides (NO API keys)
echo ""
echo "2. Creating service override files..."

# mev-pipeline
sudo tee /etc/systemd/system/mev-pipeline.service.d/rpc-endpoints.conf > /dev/null << 'EOF'
[Service]
# TIER 1: LOCAL NODES
Environment="ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_WS=ws://127.0.0.1:8546"
Environment="GETH_HTTP=http://127.0.0.1:8549"
Environment="GETH_WS=ws://127.0.0.1:8550"

# API keys loaded from .env via EnvironmentFile
# Application builds cloud URLs from INFURA_API_KEY, ALCHEMY_API_KEY

# LOAD BALANCING
Environment="PREFER_LOCAL_NODES=true"
Environment="LOCAL_NODE_PRIORITY=true"
EOF

# mev-execution
sudo cp /etc/systemd/system/mev-pipeline.service.d/rpc-endpoints.conf \
       /etc/systemd/system/mev-execution.service.d/rpc-endpoints.conf

echo "✅ Service override files created (no API keys)"

# 3. Verify no API keys exposed
echo ""
echo "3. Verifying security..."
EXPOSED=$(grep -rE "INFURA_API_KEY|ALCHEMY_API_KEY" \
  /etc/systemd/system/mev-*.service* 2>/dev/null | \
  grep -v "^#" | grep -v "YOUR_KEY\|YOUR_INFURA\|YOUR_ALCHEMY" | wc -l)

if [ "$EXPOSED" -eq 0 ]; then
    echo "✅ No API keys exposed in service files"
else
    echo "⚠️  Found $EXPOSED API key references - review manually"
fi

# 4. Ensure .env is loaded
echo ""
echo "4. Verifying .env loading..."
if systemctl show mev-pipeline.service 2>/dev/null | grep -q "EnvironmentFile.*\.env"; then
    echo "✅ mev-pipeline.service loads .env"
else
    echo "⚠️  mev-pipeline.service may not load .env - check manually"
fi

if systemctl show mev-execution.service 2>/dev/null | grep -q "EnvironmentFile.*\.env"; then
    echo "✅ mev-execution.service loads .env"
else
    echo "⚠️  mev-execution.service may not load .env - check manually"
fi

# 5. Reload systemd
echo ""
echo "5. Reloading systemd..."
sudo systemctl daemon-reload
echo "✅ Systemd reloaded"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Verify API keys are in /opt/mev-lab/.env"
echo "2. Update application code to build URLs from keys (rpc_pool.py)"
echo "3. Restart services:"
echo "   sudo systemctl restart mev-pipeline.service"
echo "   sudo systemctl restart mev-execution.service"
echo "4. Monitor logs to verify tier usage"
```

---

## Security Checklist

- [x] .env file permissions: 600
- [x] .env file owner: lyftium:lyftium
- [x] API keys present in .env
- [ ] Service files: NO API keys
- [ ] Services load .env via EnvironmentFile
- [ ] Application code builds URLs from keys
- [ ] .env in .gitignore

---

## Expected Result

After implementation:
- ✅ API keys stored securely in .env (600 permissions)
- ✅ Service files contain NO secrets
- ✅ Application builds cloud URLs from API keys
- ✅ 3-tier infrastructure with smart balancing
- ✅ Automatic failover between tiers
- ✅ Maximum resilience with secure key management

---

**Status: Ready for secure implementation!**
