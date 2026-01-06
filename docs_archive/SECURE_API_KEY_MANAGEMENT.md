# Secure API Key Management for MEV Services
**Best Practices: Loading API Keys from .env Files**
**Date:** $(date +"%Y-%m-%d %H:%M:%S")

---

## ⚠️ Security Best Practices

**NEVER:**
- ❌ Hardcode API keys in systemd service files
- ❌ Commit API keys to version control
- ❌ Store API keys in plain text in service files
- ❌ Log API keys or expose them

**ALWAYS:**
- ✅ Load API keys from secure .env files
- ✅ Use EnvironmentFile in systemd (loads securely)
- ✅ Restrict .env file permissions (600)
- ✅ Keep .env in .gitignore

---

## Secure Configuration Approach

### Option 1: Use .env File with EnvironmentFile (Recommended)

**How it works:**
- Systemd loads `.env` file via `EnvironmentFile=`
- Variables are injected into service environment
- API keys never appear in service files
- File permissions protect the keys

### Option 2: Use Separate Secrets File

- Keep API keys in `/etc/mev-lab/secrets.env` (600 permissions)
- Load only secrets file in systemd
- Never commit to git

---

## Implementation: Secure API Key Loading

### Step 1: Create Secure .env File Structure

**File:** `/opt/mev-lab/.env`

```bash
# ============================================
# SECURE API KEYS (DO NOT COMMIT)
# ============================================
# This file contains private API keys
# Permissions: 600 (read/write owner only)

# Infura API Key
INFURA_API_KEY=your_actual_infura_key_here

# Alchemy API Key
ALCHEMY_API_KEY=your_actual_alchemy_key_here

# QuickNode Endpoint (optional)
QUICKNODE_HTTP=https://your-endpoint.quicknode.com

# ============================================
# LOCAL NODE ENDPOINTS (Public - OK to commit)
# ============================================
ERIGON_HTTP=http://127.0.0.1:8545
ERIGON_WS=ws://127.0.0.1:8546
GETH_HTTP=http://127.0.0.1:8549
GETH_WS=ws://127.0.0.1:8550

# ============================================
# DERIVED ENDPOINTS (Built from API keys)
# ============================================
INFURA_HTTP=https://mainnet.infura.io/v3/${INFURA_API_KEY}
INFURA_WS=wss://mainnet.infura.io/ws/v3/${INFURA_API_KEY}
ALCHEMY_HTTP=https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}
ALCHEMY_WS=wss://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}
```

**Note:** Systemd doesn't expand `${VAR}` syntax, so we need a different approach.

---

## Correct Implementation: Secure API Key Loading

### Step 1: Secure .env File

```bash
# Create or update .env file
nano /opt/mev-lab/.env

# Add API keys (DO NOT include in service files)
INFURA_API_KEY=your_actual_key
ALCHEMY_API_KEY=your_actual_key
```

### Step 2: Secure File Permissions

```bash
# Restrict .env file permissions
chmod 600 /opt/mev-lab/.env
chown lyftium:lyftium /opt/mev-lab/.env

# Verify permissions
ls -la /opt/mev-lab/.env
# Should show: -rw------- (600)
```

### Step 3: Update Service Files (NO API Keys!)

**File:** `/etc/systemd/system/mev-pipeline.service.d/rpc-endpoints.conf`

```ini
[Service]
# ============================================
# TIER 1: LOCAL NODES (No secrets - safe to expose)
# ============================================
Environment="ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_WS=ws://127.0.0.1:8546"
Environment="LOCAL_ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_RPC_URL=http://127.0.0.1:8545"

Environment="GETH_HTTP=http://127.0.0.1:8549"
Environment="GETH_WS=ws://127.0.0.1:8550"
Environment="LOCAL_GETH_HTTP=http://127.0.0.1:8549"

# ============================================
# TIER 2: CLOUD ENDPOINTS
# API keys loaded from .env file via EnvironmentFile
# NEVER hardcode here!
# ============================================
# The .env file will be loaded and INFURA_API_KEY, etc. will be available
# We construct URLs using those variables in the application code OR
# create a script that expands them

# ============================================
# LOAD BALANCING (No secrets)
# ============================================
Environment="PREFER_LOCAL_NODES=true"
Environment="LOCAL_NODE_PRIORITY=true"
Environment="HEALTH_CHECK_INTERVAL=30"
Environment="RATE_LIMIT_DETECTION=true"
```

### Step 4: Load .env File Securely

**Update main service file or override:**

The service already has:
```ini
EnvironmentFile=-/opt/mev-lab/.env
```

This securely loads the .env file, making API keys available as environment variables.

### Step 5: Build Cloud Endpoints from API Keys

Since systemd doesn't expand `${VAR}`, we have two options:

#### Option A: Application Code Builds URLs

The application reads API keys and constructs URLs:
```python
# In rpc_pool.py
infura_key = os.getenv("INFURA_API_KEY")
if infura_key:
    infura_url = f"https://mainnet.infura.io/v3/{infura_key}"
```

#### Option B: Use Startup Script to Expand Variables

Create a startup script that expands variables:

```bash
#!/bin/bash
# /opt/mev-lab/scripts/expand-rpc-urls.sh

# Load .env
source /opt/mev-lab/.env

# Export expanded URLs
export INFURA_HTTP="https://mainnet.infura.io/v3/${INFURA_API_KEY}"
export INFURA_WS="wss://mainnet.infura.io/ws/v3/${INFURA_API_KEY}"
export ALCHEMY_HTTP="https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
export ALCHEMY_WS="wss://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}"

# Execute the actual service
exec "$@"
```

---

## Recommended: Application-Level URL Construction

**Best Practice:** Let the application build URLs from API keys.

### Update rpc_pool.py

```python
def _collect_cloud_ethereum_providers() -> list:
    """Collect cloud Ethereum RPC endpoints (Tier 2)."""
    cloud_providers = []
    
    # Infura - build URL from API key
    infura_key = os.getenv("INFURA_API_KEY")
    if infura_key:
        cloud_providers.append({
            "url": f"https://mainnet.infura.io/v3/{infura_key}",
            "name": "infura_primary",
            "priority": 2,
            "weight": 60,
        })
    
    # Alchemy - build URL from API key
    alchemy_key = os.getenv("ALCHEMY_API_KEY")
    if alchemy_key:
        cloud_providers.append({
            "url": f"https://eth-mainnet.g.alchemy.com/v2/{alchemy_key}",
            "name": "alchemy_primary",
            "priority": 2,
            "weight": 60,
        })
    
    # QuickNode - can use direct endpoint or API key
    quicknode_url = os.getenv("QUICKNODE_HTTP")
    if quicknode_url:
        cloud_providers.append({
            "url": quicknode_url,
            "name": "quicknode_primary",
            "priority": 2,
            "weight": 50,
        })
    
    return cloud_providers
```

**This way:**
- ✅ API keys only in .env file
- ✅ Service files contain no secrets
- ✅ Application constructs URLs securely
- ✅ No variable expansion needed in systemd

---

## Secure Implementation Steps

### Step 1: Update .env File

```bash
# Edit .env file
nano /opt/mev-lab/.env

# Add (or update existing):
INFURA_API_KEY=your_actual_infura_key_here
ALCHEMY_API_KEY=your_actual_alchemy_key_here
QUICKNODE_HTTP=https://your-endpoint.quicknode.com  # If you have it
```

### Step 2: Secure Permissions

```bash
# Make .env file private
chmod 600 /opt/mev-lab/.env
chown lyftium:lyftium /opt/mev-lab/.env

# Verify
ls -la /opt/mev-lab/.env
# Should show: -rw------- 1 lyftium lyftium ...
```

### Step 3: Update Service Files (No API Keys!)

```bash
# Create override file WITHOUT API keys
sudo tee /etc/systemd/system/mev-pipeline.service.d/rpc-endpoints.conf > /dev/null << 'EOF'
[Service]
# TIER 1: LOCAL (Public endpoints - safe)
Environment="ERIGON_HTTP=http://127.0.0.1:8545"
Environment="ERIGON_WS=ws://127.0.0.1:8546"
Environment="LOCAL_ERIGON_HTTP=http://127.0.0.1:8545"
Environment="GETH_HTTP=http://127.0.0.1:8549"
Environment="GETH_WS=ws://127.0.0.1:8550"

# API keys loaded from .env file via EnvironmentFile in main service
# Application code constructs cloud endpoint URLs from API keys

# LOAD BALANCING
Environment="PREFER_LOCAL_NODES=true"
Environment="LOCAL_NODE_PRIORITY=true"
EOF
```

### Step 4: Verify .env is Loaded

```bash
# Check that .env is being loaded
grep "EnvironmentFile" /etc/systemd/system/mev-pipeline.service
# Should show: EnvironmentFile=-/opt/mev-lab/.env
```

### Step 5: Enhance Application Code

Update `/opt/mev-lab/src/core/config/rpc_pool.py` to build URLs from API keys (code shown above).

---

## Security Checklist

- [ ] ✅ API keys only in .env file (not in service files)
- [ ] ✅ .env file has 600 permissions (owner read/write only)
- [ ] ✅ .env file owned by service user (lyftium)
- [ ] ✅ Service files contain no API keys
- [ ] ✅ Application code constructs URLs from keys
- [ ] ✅ .env file in .gitignore (not committed)
- [ ] ✅ No API keys in logs
- [ ] ✅ EnvironmentFile loads .env securely

---

## Verification

### Check API Keys Are NOT in Service Files

```bash
# Should return nothing (no API keys found)
grep -r "INFURA_API_KEY\|ALCHEMY_API_KEY" \
  /etc/systemd/system/mev-*.service \
  /etc/systemd/system/mev-*.service.d/ 2>/dev/null

# If output found, API keys are exposed - REMOVE THEM!
```

### Check .env File Permissions

```bash
ls -la /opt/mev-lab/.env
# Should show: -rw------- (600 permissions)
```

### Verify API Keys Loaded (Without Exposing)

```bash
# Check that variables are available (without showing values)
systemctl show mev-pipeline.service --property=Environment | \
  grep -q "INFURA_API_KEY\|ALCHEMY_API_KEY" && \
  echo "✅ API keys loaded from .env" || \
  echo "⚠️  API keys not found - check EnvironmentFile"
```

---

## Best Practice Summary

1. **Store API keys in .env file only**
2. **Set .env file permissions to 600**
3. **Load .env via EnvironmentFile in systemd**
4. **Let application code build URLs from API keys**
5. **Never hardcode API keys in service files**
6. **Never log API keys**
7. **Keep .env in .gitignore**

---

## Quick Secure Setup

```bash
# 1. Add API keys to .env (if not already there)
echo "INFURA_API_KEY=your_key_here" >> /opt/mev-lab/.env
echo "ALCHEMY_API_KEY=your_key_here" >> /opt/mev-lab/.env

# 2. Secure permissions
chmod 600 /opt/mev-lab/.env
chown lyftium:lyftium /opt/mev-lab/.env

# 3. Verify service loads .env
grep "EnvironmentFile.*\.env" /etc/systemd/system/mev-pipeline.service

# 4. Reload services
sudo systemctl daemon-reload
sudo systemctl restart mev-pipeline.service
```

---

**Security: API keys are now properly secured in .env file with restricted permissions!**
