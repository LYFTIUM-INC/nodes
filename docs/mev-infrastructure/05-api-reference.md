# API Reference - MEV Infrastructure Platform

## Overview

The MEV Infrastructure Platform provides comprehensive REST and WebSocket APIs for integration with external systems, monitoring, and control. All APIs follow OpenAPI 3.0 specifications and support both JSON and MessagePack serialization formats for optimal performance.

### Base URL
```
Production: https://api.mev-platform.com/v1
Staging:    https://staging-api.mev-platform.com/v1
Local:      http://localhost:8080/v1
```

### Authentication

All API endpoints require authentication using JWT tokens:

```bash
# Obtain JWT token
curl -X POST https://api.mev-platform.com/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "your_username", "password": "your_password"}'

# Response
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...",
  "refresh_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...",
  "expires_in": 900
}

# Use token in requests
curl -H "Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..." \
  https://api.mev-platform.com/v1/status
```

## REST API Endpoints

### System Status & Health

#### Get System Status
```http
GET /api/v1/status
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-07-15T10:30:00Z",
  "uptime": 2592000,
  "version": "2.1.4",
  "components": {
    "mev_engine": {
      "status": "running",
      "health_score": 0.98,
      "last_heartbeat": "2025-07-15T10:29:58Z"
    },
    "blockchain_nodes": {
      "ethereum": {"status": "synced", "block_height": 18567234},
      "arbitrum": {"status": "synced", "block_height": 145623789},
      "optimism": {"status": "synced", "block_height": 89456123}
    },
    "database": {"status": "healthy", "connections": 23},
    "redis": {"status": "healthy", "memory_usage": "45%"}
  }
}
```

#### Get System Metrics
```http
GET /api/v1/metrics
```

**Query Parameters:**
- `timeframe`: `1h`, `24h`, `7d`, `30d` (default: `1h`)
- `granularity`: `1m`, `5m`, `1h`, `1d` (default: `5m`)

**Response:**
```json
{
  "timeframe": "1h",
  "granularity": "5m",
  "data": {
    "performance": {
      "avg_latency_ms": 198,
      "p95_latency_ms": 587,
      "p99_latency_ms": 1247,
      "throughput_tps": 11867,
      "success_rate": 0.87
    },
    "trading": {
      "opportunities_detected": 14523,
      "trades_executed": 234,
      "total_profit_usd": 45234.56,
      "active_positions": 12
    },
    "resources": {
      "cpu_usage": 0.68,
      "memory_usage": 0.45,
      "disk_usage": 0.23,
      "network_io_mbps": 125.4
    }
  }
}
```

### Trading Operations

#### Start Trading
```http
POST /api/v1/trading/start
```

**Request Body:**
```json
{
  "mode": "conservative",
  "position_size_eth": 1.0,
  "strategies": ["arbitrage", "liquidation"],
  "chains": [1, 42161, 10],
  "risk_limits": {
    "max_drawdown": 0.05,
    "max_position_size": 10.0,
    "stop_loss": 0.02
  }
}
```

**Response:**
```json
{
  "status": "started",
  "session_id": "trading_session_20250715_103045",
  "timestamp": "2025-07-15T10:30:45Z",
  "configuration": {
    "mode": "conservative",
    "active_strategies": ["arbitrage", "liquidation"],
    "enabled_chains": [1, 42161, 10],
    "risk_parameters": {
      "max_drawdown": 0.05,
      "max_position_size": 10.0,
      "stop_loss": 0.02
    }
  }
}
```

#### Stop Trading
```http
POST /api/v1/trading/stop
```

**Request Body:**
```json
{
  "close_positions": true,
  "force_stop": false
}
```

**Response:**
```json
{
  "status": "stopped",
  "timestamp": "2025-07-15T10:35:22Z",
  "positions_closed": 8,
  "final_pnl": 1234.56,
  "session_duration": 298
}
```

#### Get Trading Status
```http
GET /api/v1/trading/status
```

**Response:**
```json
{
  "is_trading": true,
  "session_id": "trading_session_20250715_103045",
  "mode": "conservative",
  "uptime": 1477,
  "active_strategies": ["arbitrage", "liquidation"],
  "current_positions": 12,
  "session_pnl": 2345.67,
  "today_pnl": 4567.89,
  "risk_metrics": {
    "current_drawdown": 0.012,
    "max_drawdown": 0.05,
    "position_utilization": 0.67,
    "var_95": 245.67
  }
}
```

### MEV Opportunities

#### Get Active Opportunities
```http
GET /api/v1/opportunities
```

**Query Parameters:**
- `strategy`: Filter by strategy type
- `chain_id`: Filter by blockchain
- `min_profit`: Minimum profit threshold (USD)
- `limit`: Number of results (default: 50, max: 500)

**Response:**
```json
{
  "opportunities": [
    {
      "id": "opp_arbitrage_20250715_103045_001",
      "strategy_type": "arbitrage",
      "chain_id": 1,
      "token_pair": "WETH/USDC",
      "expected_profit_usd": 245.67,
      "gas_cost_usd": 23.45,
      "net_profit_usd": 222.22,
      "confidence": 0.89,
      "size_usd": 50000,
      "detected_at": "2025-07-15T10:30:45.123Z",
      "expires_at": "2025-07-15T10:31:15.123Z",
      "dexes": ["uniswap_v3", "sushiswap"],
      "details": {
        "token_0": "0xA0b86a33E6441d0b1E8a31b3d0D3e9f1b6e4a2c3",
        "token_1": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        "price_difference": 0.0023,
        "liquidity_available": 250000
      }
    }
  ],
  "total_count": 1,
  "active_scanners": 8,
  "opportunities_per_second": 23.4
}
```

#### Execute Opportunity
```http
POST /api/v1/opportunities/{opportunity_id}/execute
```

**Request Body:**
```json
{
  "position_size": 1.0,
  "slippage_tolerance": 0.005,
  "gas_price_gwei": 25,
  "private_mempool": true
}
```

**Response:**
```json
{
  "execution_id": "exec_20250715_103045_001",
  "status": "submitted",
  "transaction_hash": "0x1234567890abcdef...",
  "bundle_hash": "0xabcdef1234567890...",
  "estimated_profit": 222.22,
  "gas_used": 245000,
  "submission_time": "2025-07-15T10:30:45.456Z"
}
```

### Positions & Portfolio

#### Get Current Positions
```http
GET /api/v1/positions
```

**Response:**
```json
{
  "positions": [
    {
      "position_id": "pos_20250715_001",
      "strategy": "arbitrage",
      "chain_id": 1,
      "token": "WETH",
      "size": 2.5,
      "entry_price": 2456.78,
      "current_price": 2467.89,
      "unrealized_pnl": 27.75,
      "opened_at": "2025-07-15T10:25:30Z",
      "duration": 305,
      "status": "open"
    }
  ],
  "summary": {
    "total_positions": 12,
    "total_exposure_usd": 125000,
    "unrealized_pnl": 567.89,
    "margin_utilization": 0.67
  }
}
```

#### Get Trade History
```http
GET /api/v1/trades
```

**Query Parameters:**
- `start_date`: ISO 8601 date
- `end_date`: ISO 8601 date
- `strategy`: Filter by strategy
- `chain_id`: Filter by chain
- `limit`: Number of results

**Response:**
```json
{
  "trades": [
    {
      "trade_id": "trade_20250715_001",
      "opportunity_id": "opp_arbitrage_20250715_103045_001",
      "strategy": "arbitrage",
      "chain_id": 1,
      "token_pair": "WETH/USDC",
      "size": 1.0,
      "entry_price": 2456.78,
      "exit_price": 2467.89,
      "realized_pnl": 11.11,
      "gas_cost": 23.45,
      "net_profit": -12.34,
      "executed_at": "2025-07-15T10:30:45Z",
      "duration": 15,
      "status": "completed",
      "transaction_hashes": [
        "0x1234567890abcdef...",
        "0xabcdef1234567890..."
      ]
    }
  ],
  "summary": {
    "total_trades": 1,
    "total_pnl": -12.34,
    "win_rate": 0.87,
    "avg_profit": 245.67
  }
}
```

### Configuration Management

#### Get Configuration
```http
GET /api/v1/config
```

**Response:**
```json
{
  "chains": {
    "ethereum": {
      "enabled": true,
      "priority": 1,
      "gas_multiplier": 1.1,
      "max_gas_price": 100
    },
    "arbitrum": {
      "enabled": true,
      "priority": 2,
      "gas_multiplier": 1.05,
      "max_gas_price": 5
    }
  },
  "strategies": {
    "arbitrage": {
      "enabled": true,
      "min_profit_usd": 50,
      "max_position_size": 10
    },
    "liquidation": {
      "enabled": true,
      "min_profit_usd": 100,
      "max_position_size": 5
    }
  },
  "risk_management": {
    "max_total_exposure": 100000,
    "max_drawdown": 0.05,
    "stop_loss": 0.02,
    "position_timeout": 3600
  }
}
```

#### Update Configuration
```http
PUT /api/v1/config
```

**Request Body:**
```json
{
  "strategies": {
    "arbitrage": {
      "min_profit_usd": 75
    }
  },
  "risk_management": {
    "max_drawdown": 0.03
  }
}
```

## WebSocket API

### Connection

Connect to WebSocket endpoint:
```
wss://api.mev-platform.com/v1/ws
```

**Authentication:**
```json
{
  "type": "auth",
  "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
}
```

### Subscriptions

#### Subscribe to Opportunities
```json
{
  "type": "subscribe",
  "channel": "opportunities",
  "params": {
    "strategy": "arbitrage",
    "min_profit": 100
  }
}
```

**Message Format:**
```json
{
  "type": "opportunity",
  "channel": "opportunities",
  "data": {
    "id": "opp_arbitrage_20250715_103045_001",
    "strategy_type": "arbitrage",
    "expected_profit_usd": 245.67,
    "timestamp": "2025-07-15T10:30:45.123Z"
  }
}
```

#### Subscribe to Trade Executions
```json
{
  "type": "subscribe",
  "channel": "trades"
}
```

**Message Format:**
```json
{
  "type": "trade_execution",
  "channel": "trades",
  "data": {
    "trade_id": "trade_20250715_001",
    "status": "executed",
    "pnl": 245.67,
    "timestamp": "2025-07-15T10:30:45Z"
  }
}
```

#### Subscribe to System Metrics
```json
{
  "type": "subscribe",
  "channel": "metrics",
  "params": {
    "interval": "5s"
  }
}
```

**Message Format:**
```json
{
  "type": "metrics",
  "channel": "metrics",
  "data": {
    "timestamp": "2025-07-15T10:30:45Z",
    "latency_ms": 198,
    "throughput_tps": 11867,
    "active_opportunities": 23,
    "session_pnl": 1234.56
  }
}
```

### Real-Time Commands

#### Emergency Stop
```json
{
  "type": "command",
  "action": "emergency_stop",
  "params": {
    "reason": "Market volatility detected"
  }
}
```

#### Pause Strategy
```json
{
  "type": "command",
  "action": "pause_strategy",
  "params": {
    "strategy": "arbitrage",
    "duration": 300
  }
}
```

## Error Handling

### HTTP Status Codes

- `200 OK`: Request successful
- `201 Created`: Resource created
- `400 Bad Request`: Invalid request parameters
- `401 Unauthorized`: Invalid or missing authentication
- `403 Forbidden`: Insufficient permissions
- `404 Not Found`: Resource not found
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error
- `503 Service Unavailable`: System maintenance

### Error Response Format

```json
{
  "error": {
    "code": "INVALID_PARAMETER",
    "message": "Invalid strategy type specified",
    "details": {
      "parameter": "strategy",
      "value": "invalid_strategy",
      "valid_values": ["arbitrage", "sandwich", "liquidation", "flash_loan"]
    },
    "request_id": "req_20250715_103045_001"
  }
}
```

### Common Error Codes

- `AUTHENTICATION_FAILED`: Invalid credentials
- `INSUFFICIENT_PERMISSIONS`: Access denied
- `INVALID_PARAMETER`: Request validation failed
- `RESOURCE_NOT_FOUND`: Requested resource doesn't exist
- `RATE_LIMIT_EXCEEDED`: Too many requests
- `SYSTEM_MAINTENANCE`: System temporarily unavailable
- `TRADING_DISABLED`: Trading operations paused
- `INSUFFICIENT_BALANCE`: Insufficient funds for operation

## Rate Limiting

### Limits by Endpoint Type

```
Rate Limits (per minute):
┌─────────────────────┬─────────────┬──────────────┬─────────────────┐
│ Endpoint Type       │ Free Tier   │ Professional │ Enterprise      │
├─────────────────────┼─────────────┼──────────────┼─────────────────┤
│ System Status       │ 60          │ 300          │ Unlimited       │
│ Trading Operations  │ 10          │ 100          │ 1000            │
│ Opportunity Queries │ 30          │ 300          │ 3000            │
│ Configuration       │ 5           │ 50           │ 500             │
│ Historical Data     │ 20          │ 200          │ 2000            │
└─────────────────────┴─────────────┴──────────────┴─────────────────┘
```

### Rate Limit Headers

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1642089600
X-RateLimit-Window: 60
```

## SDK & Libraries

### Official SDKs

**Python SDK**
```bash
pip install mev-platform-sdk
```

```python
from mev_platform import MEVClient

client = MEVClient(
    api_key="your_api_key",
    base_url="https://api.mev-platform.com/v1"
)

# Get system status
status = client.get_status()

# Start trading
session = client.start_trading(
    mode="conservative",
    strategies=["arbitrage"],
    position_size=1.0
)
```

**JavaScript SDK**
```bash
npm install @mev-platform/sdk
```

```javascript
import { MEVClient } from '@mev-platform/sdk';

const client = new MEVClient({
  apiKey: 'your_api_key',
  baseUrl: 'https://api.mev-platform.com/v1'
});

// WebSocket connection
const ws = client.connect();
ws.subscribe('opportunities', { strategy: 'arbitrage' });
```

### Community Libraries

- **Go**: `github.com/mev-platform/go-sdk`
- **Rust**: `mev-platform-rs` crate
- **Java**: `com.mevplatform:sdk`

---

*For additional API documentation and interactive testing, visit our [API Explorer](https://docs.mev-platform.com/api-explorer).*