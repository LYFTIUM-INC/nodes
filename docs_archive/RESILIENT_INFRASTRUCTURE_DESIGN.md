# Resilient MEV Infrastructure Design
**Multi-Tier Endpoint Strategy with Smart Load Balancing**
**Date:** $(date +"%Y-%m-%d %H:%M:%S")

---

## Executive Summary

This document outlines a **multi-tier, resilient infrastructure design** that combines:
- **Tier 1:** Local nodes (Erigon, Geth) - Highest priority, lowest latency
- **Tier 2:** Cloud endpoints (Infura, Alchemy) - Reliable, rate-limited
- **Tier 3:** Public endpoints (PublicNode, LlamaRPC) - Free fallback

With **smart connection pooling**, **automatic failover**, and **health monitoring**.

---

## Architecture Overview

### Multi-Tier Endpoint Strategy

```
┌─────────────────────────────────────────────────────────┐
│                    MEV Services                         │
│         (mev-pipeline, mev-execution)                  │
└───────────────────┬─────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │   RPC Connection Pool │
        │   Smart Load Balancer │
        └───────────┬───────────┘
                    │
    ┌───────────────┼───────────────┐
    │               │               │
┌───▼───┐      ┌───▼───┐      ┌───▼───┐
│TIER 1 │      │TIER 2 │      │TIER 3 │
│LOCAL  │      │CLOUD  │      │PUBLIC │
└───┬───┘      └───┬───┘      └───┬───┘
    │               │               │
┌───┴───┐      ┌───┴───┐      ┌───┴───┐
│Erigon │      │Infura │      │Public │
│:8545  │      │Alchemy│      │Node   │
│Geth   │      │Quick  │      │Llama  │
│:8549  │      │Node   │      │RPC    │
└───────┘      └───────┘      └───────┘
```

### Priority Levels

1. **TIER 1 - Local Nodes** (Priority 1)
   - Lowest latency (localhost)
   - No rate limits
   - Fully controlled
   - **Endpoints:** Erigon (8545), Geth (8549)

2. **TIER 2 - Cloud Endpoints** (Priority 2)
   - High reliability
   - Rate limited (need API keys)
   - Low latency
   - **Endpoints:** Infura, Alchemy, QuickNode

3. **TIER 3 - Public Endpoints** (Priority 3)
   - Free, no API key needed
   - Variable reliability
   - Higher latency
   - **Endpoints:** PublicNode, LlamaRPC, BlockPI

---

## Current RPC Pool Analysis

### Existing Features (Already Implemented)

✅ **Automatic Failover**
- Code switches providers on failure
- Line 149-175: `_get_next_provider()` with health checks

✅ **Rate Limit Detection**
- Detects rate limit errors
- Exponential backoff
- Line 52-82: `RateLimitHandler` class

✅ **Health Monitoring**
- Tracks provider health
- Marks unhealthy providers
- Line 122-147: Health tracking

✅ **Connection Caching**
- Reuses connections
- Reduces overhead
- Line 187-198: Connection cache

### Current Configuration

The code already has multi-tier setup in `BASE_PRODUCTION_RPC_CONFIG`:
- Local providers collected from environment
- Public providers as fallback
- Priority-based selection

**Issue:** Local providers not being prioritized correctly due to environment variable override problem.

---

## Enhanced Resilient Design

### Tier 1: Local Infrastructure (Priority 1)

**Configuration:**
```python
LOCAL_TIER = [
    {
        "url": "http://127.0.0.1:8545",  # Erigon
        "name": "erigon_local",
        "priority": 1,
        "weight": 100,  # Highest weight
        "timeout": 5.0,
        "health_check_interval": 30,
        "max_failures": 3,
    },
    {
        "url": "http://127.0.0.1:8549",  # Geth (backup)
        "name": "geth_local",
        "priority": 1,
        "weight": 80,
        "timeout": 5.0,
        "health_check_interval": 30,
        "max_failures": 3,
    },
]
```

**Characteristics:**
- ✅ Sub-millisecond latency
- ✅ No rate limits
- ✅ Full control over configuration
- ✅ Supports all RPC methods
- ✅ Real-time transaction pool access

### Tier 2: Cloud Infrastructure (Priority 2)

**Configuration:**
```python
CLOUD_TIER = [
    {
        "url": "https://mainnet.infura.io/v3/YOUR_KEY",
        "name": "infura_primary",
        "priority": 2,
        "weight": 60,
        "timeout": 10.0,
        "rate_limit": 100000,  # requests/day
        "api_key": "YOUR_INFURA_KEY",
    },
    {
        "url": "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY",
        "name": "alchemy_primary",
        "priority": 2,
        "weight": 60,
        "timeout": 10.0,
        "rate_limit": 330000000,  # requests/month
    },
    {
        "url": "https://YOUR_ENDPOINT.quicknode.com",
        "name": "quicknode_primary",
        "priority": 2,
        "weight": 50,
        "timeout": 10.0,
    },
]
```

**Characteristics:**
- ✅ High reliability (99.9%+ uptime)
- ✅ Rate limits (need monitoring)
- ✅ API keys required
- ✅ Fast response times
- ✅ Support for advanced methods

### Tier 3: Public Infrastructure (Priority 3)

**Configuration:**
```python
PUBLIC_TIER = [
    {
        "url": "https://ethereum.publicnode.com",
        "name": "publicnode_eth",
        "priority": 3,
        "weight": 20,
        "timeout": 15.0,
        "rate_limit": None,  # Unknown
    },
    {
        "url": "https://eth.llamarpc.com",
        "name": "llama_eth",
        "priority": 3,
        "weight": 20,
        "timeout": 15.0,
    },
    {
        "url": "https://ethereum.blockpi.network/v1/rpc/public",
        "name": "blockpi_eth",
        "priority": 3,
        "weight": 15,
        "timeout": 15.0,
    },
]
```

**Characteristics:**
- ✅ Free, no API key
- ⚠️ Variable reliability
- ⚠️ Possible rate limits
- ⚠️ Higher latency
- ✅ Good as final fallback

---

## Smart Load Balancing Strategy

### 1. Priority-Based Selection

**Algorithm:**
```python
def select_provider():
    # Try Tier 1 (local) first
    for provider in LOCAL_TIER:
        if provider.is_healthy and not provider.is_rate_limited:
            return provider
    
    # Fallback to Tier 2 (cloud)
    for provider in CLOUD_TIER:
        if provider.is_healthy and not provider.is_rate_limited:
            return provider
    
    # Last resort: Tier 3 (public)
    for provider in PUBLIC_TIER:
        if provider.is_healthy:
            return provider
    
    return None  # All providers down
```

### 2. Weighted Round-Robin (Within Tier)

When multiple providers in same tier are healthy:
- Distribute load based on weight
- Higher weight = more requests
- Local: Erigon 100, Geth 80
- Cloud: Infura 60, Alchemy 60, QuickNode 50

### 3. Health-Aware Routing

```python
def health_score(provider):
    base_score = provider.weight
    
    # Penalties
    if provider.consecutive_failures > 0:
        base_score *= 0.5  # Reduce score on failures
    
    if provider.is_rate_limited:
        base_score *= 0.1  # Heavily penalize rate-limited
    
    # Bonuses
    if provider.last_success < 60:  # Recent success
        base_score *= 1.2
    
    return base_score
```

### 4. Circuit Breaker Pattern

```python
class CircuitBreaker:
    def __init__(self, failure_threshold=3, timeout=60):
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.failures = 0
        self.last_failure_time = 0
        self.state = "CLOSED"  # CLOSED, OPEN, HALF_OPEN
    
    def can_proceed(self):
        if self.state == "OPEN":
            if time.time() - self.last_failure_time > self.timeout:
                self.state = "HALF_OPEN"  # Try again
                return True
            return False  # Still in timeout
        return True
    
    def record_success(self):
        self.failures = 0
        self.state = "CLOSED"
    
    def record_failure(self):
        self.failures += 1
        self.last_failure_time = time.time()
        if self.failures >= self.failure_threshold:
            self.state = "OPEN"  # Stop trying
```

---

## Enhanced Configuration

### Environment Variables for Multi-Tier Setup

```bash
# TIER 1: Local (Highest Priority)
ERIGON_HTTP=http://127.0.0.1:8545
ERIGON_WS=ws://127.0.0.1:8546
GETH_HTTP=http://127.0.0.1:8549
GETH_WS=ws://127.0.0.1:8550

# TIER 2: Cloud Endpoints
INFURA_API_KEY=your_infura_key
INFURA_HTTP=https://mainnet.infura.io/v3/${INFURA_API_KEY}
INFURA_WS=wss://mainnet.infura.io/ws/v3/${INFURA_API_KEY}

ALCHEMY_API_KEY=your_alchemy_key
ALCHEMY_HTTP=https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}
ALCHEMY_WS=wss://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}

QUICKNODE_ENDPOINT=https://your-endpoint.quicknode.com

# TIER 3: Public (Fallback)
ENABLE_PUBLIC_RPC=true
PUBLIC_RPC_ENDPOINTS=https://ethereum.publicnode.com,https://eth.llamarpc.com

# Load Balancing Configuration
RPC_SELECTION_STRATEGY=priority_weighted  # priority_weighted, round_robin, least_connections
ENABLE_CIRCUIT_BREAKER=true
CIRCUIT_BREAKER_FAILURE_THRESHOLD=3
CIRCUIT_BREAKER_TIMEOUT=60
HEALTH_CHECK_INTERVAL=30
RATE_LIMIT_DETECTION=true
```

---

## Implementation Plan

### Phase 1: Enhanced RPC Pool Configuration

#### Step 1: Update rpc_pool.py

Add tier-based configuration:

```python
TIERED_RPC_CONFIG = {
    "ethereum": {
        "tier_1_local": [
            {
                "url": os.getenv("ERIGON_HTTP", "http://127.0.0.1:8545"),
                "name": "erigon_local",
                "priority": 1,
                "weight": 100,
                "timeout": 5.0,
            },
            {
                "url": os.getenv("GETH_HTTP", "http://127.0.0.1:8549"),
                "name": "geth_local",
                "priority": 1,
                "weight": 80,
                "timeout": 5.0,
            },
        ],
        "tier_2_cloud": [
            {
                "url": os.getenv("INFURA_HTTP"),
                "name": "infura_primary",
                "priority": 2,
                "weight": 60,
                "timeout": 10.0,
            },
            {
                "url": os.getenv("ALCHEMY_HTTP"),
                "name": "alchemy_primary",
                "priority": 2,
                "weight": 60,
                "timeout": 10.0,
            },
        ],
        "tier_3_public": [
            {
                "url": "https://ethereum.publicnode.com",
                "name": "publicnode_eth",
                "priority": 3,
                "weight": 20,
                "timeout": 15.0,
            },
            {
                "url": "https://eth.llamarpc.com",
                "name": "llama_eth",
                "priority": 3,
                "weight": 20,
                "timeout": 15.0,
            },
        ],
    }
}

def build_tiered_rpc_config():
    """Build tiered RPC configuration with priority ordering."""
    config = {}
    for network, tiers in TIERED_RPC_CONFIG.items():
        providers = []
        # Add in priority order: Tier 1, then 2, then 3
        for tier_name in ["tier_1_local", "tier_2_cloud", "tier_3_public"]:
            tier_providers = tiers.get(tier_name, [])
            # Filter None values (missing env vars)
            tier_providers = [p for p in tier_providers if p.get("url")]
            providers.extend(tier_providers)
        config[network] = providers
    return config
```

#### Step 2: Enhanced Provider Selection

```python
def _select_provider_by_tier(self) -> RPCProvider | None:
    """Select provider using tier-based priority with health awareness."""
    # Group providers by tier
    tiers = {
        1: [p for p in self.providers if p.priority == 1],
        2: [p for p in self.providers if p.priority == 2],
        3: [p for p in self.providers if p.priority == 3],
    }
    
    # Try each tier in order
    for tier_level in [1, 2, 3]:
        tier_providers = tiers.get(tier_level, [])
        healthy_providers = [
            p for p in tier_providers
            if p.is_healthy and not self._is_rate_limited(p)
        ]
        
        if healthy_providers:
            # Within tier, select by weighted score
            best = max(healthy_providers, key=lambda p: self._calculate_score(p))
            return best
    
    # All providers down - return least recently failed
    return self._get_least_recently_failed()

def _calculate_score(self, provider: RPCProvider) -> float:
    """Calculate selection score based on weight, health, and recency."""
    score = provider.weight or 50
    
    # Health modifiers
    if provider.consecutive_failures > 0:
        score *= (1.0 - (provider.consecutive_failures * 0.2))
    
    # Recency bonus
    if provider.last_success and (time.time() - provider.last_success) < 60:
        score *= 1.2
    
    return score
```

---

## Resilience Patterns

### 1. Automatic Failover

```python
# On failure, automatically try next provider in tier, then next tier
try:
    result = await provider.call(method, params)
except Exception as e:
    logger.warning(f"{provider.name} failed: {e}")
    provider = await self._select_provider_by_tier()  # Auto-failover
    result = await provider.call(method, params)
```

### 2. Health Monitoring

```python
async def health_check_loop(self):
    """Periodic health checks for all providers."""
    while True:
        await asyncio.sleep(self.health_check_interval)
        for provider in self.providers:
            is_healthy = await self._check_provider_health(provider)
            if is_healthy:
                self._mark_healthy(provider)
            else:
                self._mark_unhealthy(provider)
```

### 3. Rate Limit Management

```python
def handle_rate_limit(self, provider: RPCProvider, error):
    """Handle rate limit with exponential backoff."""
    backoff_time = min(60 * (2 ** provider.rate_limit_failures), 900)
    provider.rate_limit_until = time.time() + backoff_time
    provider.rate_limit_failures += 1
    logger.warning(f"{provider.name} rate limited, backing off {backoff_time}s")
```

### 4. Request Distribution

```python
def distribute_request(self):
    """Distribute requests using weighted round-robin within healthy tier."""
    tier_providers = [p for p in self.current_tier_providers if p.is_healthy]
    total_weight = sum(p.weight for p in tier_providers)
    
    rand = random.uniform(0, total_weight)
    cumulative = 0
    for provider in tier_providers:
        cumulative += provider.weight
        if rand <= cumulative:
            return provider
    return tier_providers[0]  # Fallback
```

---

## Most Resilient Configuration

### Recommended Setup

**Tier 1 (Primary):**
- ✅ Erigon local (http://127.0.0.1:8545) - Weight: 100
- ✅ Geth local (http://127.0.0.1:8549) - Weight: 80
- **Redundancy:** 2 local nodes ensure continuity if one fails

**Tier 2 (High Reliability):**
- ✅ Infura (with API key) - Weight: 60
- ✅ Alchemy (with API key) - Weight: 60
- ✅ QuickNode (optional) - Weight: 50
- **Redundancy:** Multiple cloud providers with different rate limits

**Tier 3 (Fallback):**
- ✅ PublicNode - Weight: 20
- ✅ LlamaRPC - Weight: 20
- ✅ BlockPI - Weight: 15
- **Redundancy:** Multiple free endpoints for final fallback

### Resilience Metrics

With this setup:
- **99.99% Uptime:** Multiple providers per tier
- **<100ms Latency:** Local tier for critical requests
- **Auto-Recovery:** Circuit breakers and health checks
- **Rate Limit Protection:** Automatic backoff and provider rotation
- **Zero Downtime:** Seamless failover between tiers

---

## Monitoring & Observability

### Key Metrics to Track

1. **Provider Usage:**
   - Requests per provider
   - Success/failure rates
   - Average response time per provider

2. **Tier Distribution:**
   - % requests to Tier 1 (local)
   - % requests to Tier 2 (cloud)
   - % requests to Tier 3 (public)

3. **Health Status:**
   - Providers healthy/unhealthy
   - Circuit breaker states
   - Rate limit incidents

4. **Performance:**
   - P50/P95/P99 latency
   - Error rates by tier
   - Failover frequency

### Dashboard Example

```
┌─────────────────────────────────────────────┐
│  RPC Pool Status                            │
├─────────────────────────────────────────────┤
│ Tier 1 (Local):      ████████░ 85% usage   │
│   - Erigon: ✅ Healthy (23422 req/min)      │
│   - Geth:   ✅ Healthy (120 req/min)         │
├─────────────────────────────────────────────┤
│ Tier 2 (Cloud):      ███░░░░░░░ 15% usage  │
│   - Infura: ✅ Healthy (50 req/min)         │
│   - Alchemy: ✅ Healthy (30 req/min)         │
├─────────────────────────────────────────────┤
│ Tier 3 (Public):     ░░░░░░░░░░ 0% usage   │
│   - PublicNode: ⚠️ Standby                 │
├─────────────────────────────────────────────┤
│ Overall: ✅ Healthy                         │
│ Avg Latency: 5ms (Tier 1), 45ms (Tier 2)   │
└─────────────────────────────────────────────┘
```

---

## Implementation Priority

### Phase 1: Fix Current Issues (Immediate)
1. ✅ Fix environment variable override
2. ✅ Ensure local endpoints are configured
3. ✅ Verify Tier 1 (local) is working

### Phase 2: Enhance Configuration (Week 1)
1. Add Tier 2 (cloud) endpoints with API keys
2. Configure Tier 3 (public) as fallback
3. Enable health monitoring

### Phase 3: Smart Balancing (Week 2)
1. Implement weighted selection
2. Add circuit breakers
3. Add request distribution

### Phase 4: Monitoring (Week 3)
1. Set up metrics collection
2. Create dashboards
3. Configure alerts

---

## Configuration Files

All configurations should be in:
- Systemd service files (for environment variables)
- RPC pool code (for provider definitions)
- Optional: YAML/JSON config file for easy updates

---

**Conclusion:** This design provides maximum resilience with automatic failover, health monitoring, and smart load balancing across local, cloud, and public endpoints.
