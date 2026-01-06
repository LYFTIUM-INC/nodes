# MEV Infrastructure API Integration Guide

## Overview

The MEV Infrastructure API provides comprehensive access to advanced Maximum Extractable Value opportunities across multiple blockchain networks. This guide covers authentication, endpoints, WebSocket integration, and best practices for building applications on top of our infrastructure.

## Quick Start

### 1. Authentication

All API requests require authentication using Bearer tokens. Obtain your API credentials from the dashboard.

```bash
# Example authentication
curl -X POST https://api.mev-infrastructure.com/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "your_username",
    "password": "your_password"
  }'

# Response
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...",
  "refresh_token": "def50200...",
  "token_type": "bearer",
  "expires_in": 3600
}
```

### 2. Making Your First Request

```bash
# Get MEV opportunities
curl -X GET https://api.mev-infrastructure.com/v1/mev/opportunities \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json"
```

## API Reference

### Base URL
- **Production**: `https://api.mev-infrastructure.com`
- **Staging**: `https://staging-api.mev-infrastructure.com`

### Rate Limits
- **Free Tier**: 100 requests/minute
- **Professional**: 1,000 requests/minute  
- **Enterprise**: 10,000 requests/minute

### Response Format
All responses follow a consistent JSON structure:

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "timestamp": "2024-01-20T15:30:00Z",
    "request_id": "req_123456789",
    "rate_limit": {
      "remaining": 995,
      "reset_time": "2024-01-20T15:31:00Z"
    }
  }
}
```

## Authentication Endpoints

### POST /v1/auth/login
Authenticate user and obtain access tokens.

**Request Body:**
```json
{
  "username": "string",
  "password": "string",
  "remember_me": false
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "access_token": "string",
    "refresh_token": "string",
    "token_type": "bearer",
    "expires_in": 3600,
    "user": {
      "id": "uuid",
      "username": "string",
      "tier": "professional",
      "permissions": ["read:opportunities", "execute:trades"]
    }
  }
}
```

### POST /v1/auth/refresh
Refresh access token using refresh token.

**Request Body:**
```json
{
  "refresh_token": "string"
}
```

### POST /v1/auth/logout
Invalidate current session.

**Headers:**
```
Authorization: Bearer {access_token}
```

## MEV Opportunities

### GET /v1/mev/opportunities
Retrieve available MEV opportunities with filtering and pagination.

**Query Parameters:**
- `chain` (string, optional): Filter by blockchain (ethereum, polygon, bsc, arbitrum)
- `strategy` (string, optional): Filter by strategy type (arbitrage, sandwich, liquidation)
- `min_profit` (number, optional): Minimum profit in USD
- `max_gas` (number, optional): Maximum gas cost in gwei
- `confidence` (number, optional): Minimum confidence score (0-1)
- `limit` (number, optional): Number of results (default: 50, max: 100)
- `offset` (number, optional): Pagination offset

**Example Request:**
```bash
curl -X GET "https://api.mev-infrastructure.com/v1/mev/opportunities?chain=ethereum&strategy=arbitrage&min_profit=100&limit=10" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response:**
```json
{
  "success": true,
  "data": {
    "opportunities": [
      {
        "id": "opp_123456",
        "chain": "ethereum",
        "strategy": "arbitrage",
        "tokens": ["WETH", "USDC", "DAI"],
        "dexes": ["uniswap_v3", "sushiswap", "curve"],
        "profit_estimate": 1250.75,
        "gas_estimate": 285000,
        "gas_price_gwei": 45,
        "confidence_score": 0.94,
        "risk_level": "medium",
        "time_sensitive": true,
        "expires_at": "2024-01-20T15:35:00Z",
        "created_at": "2024-01-20T15:30:00Z",
        "route": {
          "steps": [
            {
              "dex": "uniswap_v3",
              "token_in": "WETH",
              "token_out": "USDC",
              "amount_in": "10.5",
              "expected_out": "24250.30"
            },
            {
              "dex": "curve",
              "token_in": "USDC", 
              "token_out": "DAI",
              "amount_in": "24250.30",
              "expected_out": "24275.80"
            }
          ]
        },
        "simulation": {
          "success_probability": 0.94,
          "slippage_tolerance": 0.01,
          "mev_share": 0.15,
          "flashloan_required": true
        }
      }
    ],
    "pagination": {
      "total": 156,
      "limit": 10,
      "offset": 0,
      "has_next": true
    }
  }
}
```

### GET /v1/mev/opportunities/{id}
Get detailed information about a specific opportunity.

**Response:**
```json
{
  "success": true,
  "data": {
    "opportunity": {
      "id": "opp_123456",
      "detailed_analysis": {
        "liquidity_analysis": {
          "total_liquidity": "15000000",
          "price_impact": 0.003,
          "slippage_risk": "low"
        },
        "market_conditions": {
          "volatility": 0.25,
          "volume_24h": "125000000",
          "trend": "bullish"
        },
        "execution_plan": {
          "recommended_gas_price": 45,
          "optimal_block_target": "next",
          "fallback_strategies": ["reduce_amount", "alternative_route"]
        }
      }
    }
  }
}
```

### POST /v1/mev/opportunities/{id}/execute
Execute a MEV opportunity.

**Request Body:**
```json
{
  "slippage_tolerance": 0.01,
  "gas_price_strategy": "aggressive",
  "use_flashloan": true,
  "max_gas_price": 100,
  "deadline": 300,
  "partial_fill": false
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "execution": {
      "id": "exec_789012",
      "opportunity_id": "opp_123456",
      "transaction_hash": "0x742d35cc6436d6e9ec3b47e99f0bca2c5c4b37b45a2e9c9d0e5f8a1b2c3d4e5f",
      "status": "pending",
      "estimated_profit": 1250.75,
      "gas_limit": 285000,
      "gas_price": 45,
      "created_at": "2024-01-20T15:32:00Z"
    }
  }
}
```

### GET /v1/mev/executions/{id}
Get execution status and results.

**Response:**
```json
{
  "success": true,
  "data": {
    "execution": {
      "id": "exec_789012",
      "opportunity_id": "opp_123456",
      "transaction_hash": "0x742d35cc6436d6e9ec3b47e99f0bca2c5c4b37b45a2e9c9d0e5f8a1b2c3d4e5f",
      "status": "confirmed",
      "block_number": 18925476,
      "actual_profit": 1245.30,
      "gas_used": 276543,
      "gas_price": 45,
      "execution_time_ms": 125,
      "slippage": 0.004,
      "mev_share": 187.80,
      "confirmed_at": "2024-01-20T15:32:15Z"
    }
  }
}
```

## Market Data

### GET /v1/market/prices
Get real-time token prices across multiple DEXes.

**Query Parameters:**
- `tokens` (string, required): Comma-separated token addresses
- `chains` (string, optional): Comma-separated chain IDs
- `dexes` (string, optional): Comma-separated DEX names

**Response:**
```json
{
  "success": true,
  "data": {
    "prices": [
      {
        "token_address": "0xA0b86a33E6441B0D1c5D2F1E3C1E0C9C6D7A8B9C0E",
        "symbol": "WETH",
        "chain": "ethereum",
        "dex": "uniswap_v3",
        "price_usd": 2450.75,
        "liquidity_usd": "125000000",
        "volume_24h": "45000000",
        "price_change_24h": 0.025,
        "last_update": "2024-01-20T15:30:00Z"
      }
    ]
  }
}
```

### GET /v1/market/liquidity
Get liquidity information for token pairs.

### GET /v1/market/volume
Get trading volume across different venues.

## Analytics

### GET /v1/analytics/performance
Get performance analytics for your MEV operations.

**Query Parameters:**
- `period` (string): Time period (1h, 24h, 7d, 30d)
- `strategy` (string, optional): Filter by strategy
- `chain` (string, optional): Filter by chain

**Response:**
```json
{
  "success": true,
  "data": {
    "analytics": {
      "period": "24h",
      "total_opportunities": 1247,
      "executed_opportunities": 1174,
      "success_rate": 0.941,
      "total_profit": 125750.30,
      "total_gas_cost": 8420.15,
      "net_profit": 117330.15,
      "average_profit_per_trade": 99.94,
      "roi": 0.125,
      "strategy_breakdown": [
        {
          "strategy": "arbitrage",
          "count": 856,
          "profit": 89250.20,
          "success_rate": 0.952
        },
        {
          "strategy": "liquidation", 
          "count": 318,
          "profit": 28080.10,
          "success_rate": 0.921
        }
      ]
    }
  }
}
```

## WebSocket API

### Connection
Connect to real-time data streams for live MEV opportunities and market updates.

**Endpoint:** `wss://api.mev-infrastructure.com/v1/ws`

```javascript
const ws = new WebSocket('wss://api.mev-infrastructure.com/v1/ws');

ws.onopen = function() {
  // Authenticate
  ws.send(JSON.stringify({
    type: 'auth',
    data: {
      token: 'YOUR_ACCESS_TOKEN'
    }
  }));
};

ws.onmessage = function(event) {
  const message = JSON.parse(event.data);
  console.log('Received:', message);
};
```

### Subscription Management

```javascript
// Subscribe to opportunities
ws.send(JSON.stringify({
  type: 'subscribe',
  data: {
    channels: ['opportunities'],
    filters: {
      chains: ['ethereum', 'polygon'],
      strategies: ['arbitrage', 'liquidation'],
      min_profit: 100
    }
  }
}));

// Subscribe to executions
ws.send(JSON.stringify({
  type: 'subscribe', 
  data: {
    channels: ['executions'],
    filters: {
      user_only: true
    }
  }
}));

// Subscribe to market data
ws.send(JSON.stringify({
  type: 'subscribe',
  data: {
    channels: ['market_data'],
    filters: {
      tokens: ['WETH', 'USDC', 'DAI'],
      update_frequency: 1000
    }
  }
}));
```

### Message Types

#### Opportunity Update
```json
{
  "type": "opportunity",
  "timestamp": "2024-01-20T15:30:00Z",
  "data": {
    "action": "created",
    "opportunity": {
      "id": "opp_123456",
      "chain": "ethereum",
      "strategy": "arbitrage",
      "profit_estimate": 1250.75,
      "expires_at": "2024-01-20T15:35:00Z"
    }
  }
}
```

#### Execution Update
```json
{
  "type": "execution",
  "timestamp": "2024-01-20T15:32:15Z", 
  "data": {
    "execution_id": "exec_789012",
    "opportunity_id": "opp_123456",
    "status": "confirmed",
    "actual_profit": 1245.30,
    "transaction_hash": "0x742d35cc..."
  }
}
```

#### Market Data Update
```json
{
  "type": "market_data",
  "timestamp": "2024-01-20T15:30:01Z",
  "data": {
    "token": "WETH",
    "chain": "ethereum",
    "dex": "uniswap_v3",
    "price": 2450.75,
    "volume_1m": 125000,
    "liquidity": 15000000
  }
}
```

## SDKs and Libraries

### JavaScript/TypeScript SDK

```bash
npm install @mev-infrastructure/sdk
```

```typescript
import { MEVClient } from '@mev-infrastructure/sdk';

const client = new MEVClient({
  apiKey: 'your_api_key',
  baseUrl: 'https://api.mev-infrastructure.com',
  websocket: true
});

// Get opportunities
const opportunities = await client.opportunities.list({
  chain: 'ethereum',
  strategy: 'arbitrage',
  minProfit: 100
});

// Execute opportunity
const execution = await client.opportunities.execute('opp_123456', {
  slippageTolerance: 0.01,
  gasPriceStrategy: 'aggressive'
});

// Real-time subscriptions
client.subscribe('opportunities', {
  chains: ['ethereum'],
  strategies: ['arbitrage']
}, (opportunity) => {
  console.log('New opportunity:', opportunity);
});
```

### Python SDK

```bash
pip install mev-infrastructure-sdk
```

```python
from mev_infrastructure import MEVClient

client = MEVClient(
    api_key='your_api_key',
    base_url='https://api.mev-infrastructure.com'
)

# Get opportunities
opportunities = client.opportunities.list(
    chain='ethereum',
    strategy='arbitrage',
    min_profit=100
)

# Execute opportunity
execution = client.opportunities.execute(
    'opp_123456',
    slippage_tolerance=0.01,
    gas_price_strategy='aggressive'
)

# WebSocket connection
def on_opportunity(opportunity):
    print(f"New opportunity: {opportunity}")

client.subscribe('opportunities', on_opportunity, filters={
    'chains': ['ethereum'],
    'strategies': ['arbitrage']
})
```

## Error Handling

### Error Response Format
```json
{
  "success": false,
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "Insufficient balance to execute this opportunity",
    "details": {
      "required_balance": "1000.00",
      "current_balance": "500.00",
      "currency": "USD"
    },
    "request_id": "req_123456789"
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `INVALID_TOKEN` | 401 | Authentication token is invalid or expired |
| `INSUFFICIENT_PERMISSIONS` | 403 | User lacks required permissions |
| `OPPORTUNITY_EXPIRED` | 410 | MEV opportunity has expired |
| `INSUFFICIENT_BALANCE` | 402 | Insufficient balance for execution |
| `RATE_LIMIT_EXCEEDED` | 429 | API rate limit exceeded |
| `SLIPPAGE_TOO_HIGH` | 422 | Slippage tolerance exceeded |
| `EXECUTION_FAILED` | 500 | Transaction execution failed |

### Retry Logic
```typescript
async function executeWithRetry(opportunityId: string, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await client.opportunities.execute(opportunityId);
    } catch (error) {
      if (error.code === 'RATE_LIMIT_EXCEEDED' && attempt < maxRetries) {
        const retryAfter = error.headers['retry-after'] || Math.pow(2, attempt);
        await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
        continue;
      }
      throw error;
    }
  }
}
```

## Best Practices

### 1. Efficient Polling
```typescript
// Use WebSockets instead of polling when possible
const ws = new MEVWebSocket('wss://api.mev-infrastructure.com/v1/ws');

// If polling is necessary, use appropriate intervals
const pollOpportunities = async () => {
  const opportunities = await client.opportunities.list();
  // Process opportunities
};

// Poll every 5 seconds (not faster unless necessary)
setInterval(pollOpportunities, 5000);
```

### 2. Opportunity Filtering
```typescript
// Filter opportunities client-side to reduce API calls
const filterOpportunities = (opportunities) => {
  return opportunities.filter(opp => 
    opp.profit_estimate > 100 &&
    opp.confidence_score > 0.9 &&
    opp.risk_level === 'low'
  );
};
```

### 3. Gas Price Optimization
```typescript
// Use dynamic gas pricing
const executeOpportunity = async (opportunityId) => {
  const gasPrice = await client.gas.getOptimalPrice('ethereum');
  
  return client.opportunities.execute(opportunityId, {
    gasPrice: gasPrice.fast,
    gasPriceStrategy: 'dynamic'
  });
};
```

### 4. Risk Management
```typescript
// Implement position sizing and risk limits
const RiskManager = {
  maxDailyLoss: 1000, // USD
  maxPositionSize: 10000, // USD
  dailyLoss: 0,
  
  canExecute(opportunity) {
    const potentialLoss = opportunity.gas_estimate * opportunity.gas_price_gwei;
    
    return (
      this.dailyLoss + potentialLoss < this.maxDailyLoss &&
      opportunity.profit_estimate < this.maxPositionSize
    );
  }
};
```

### 5. Performance Monitoring
```typescript
// Track execution performance
const performanceTracker = {
  executions: [],
  
  track(execution) {
    this.executions.push({
      ...execution,
      timestamp: Date.now()
    });
  },
  
  getStats(period = '24h') {
    const cutoff = Date.now() - this.parsePeriod(period);
    const recentExecutions = this.executions.filter(e => e.timestamp > cutoff);
    
    return {
      totalExecutions: recentExecutions.length,
      successRate: recentExecutions.filter(e => e.status === 'success').length / recentExecutions.length,
      totalProfit: recentExecutions.reduce((sum, e) => sum + e.actual_profit, 0),
      averageProfit: recentExecutions.reduce((sum, e) => sum + e.actual_profit, 0) / recentExecutions.length
    };
  }
};
```

## Integration Examples

### 1. Trading Bot
```typescript
class MEVTradingBot {
  constructor(apiKey: string) {
    this.client = new MEVClient({ apiKey });
    this.riskManager = new RiskManager();
  }

  async start() {
    // Subscribe to opportunities
    this.client.subscribe('opportunities', this.handleOpportunity.bind(this));
    
    // Monitor executions
    this.client.subscribe('executions', this.handleExecution.bind(this));
    
    console.log('Trading bot started');
  }

  async handleOpportunity(opportunity) {
    // Apply filters
    if (!this.shouldExecute(opportunity)) return;
    
    // Check risk limits
    if (!this.riskManager.canExecute(opportunity)) return;
    
    try {
      // Execute opportunity
      const execution = await this.client.opportunities.execute(opportunity.id, {
        slippageTolerance: 0.01,
        gasPriceStrategy: 'optimal'
      });
      
      console.log(`Executed opportunity ${opportunity.id}: ${execution.id}`);
    } catch (error) {
      console.error(`Failed to execute ${opportunity.id}:`, error);
    }
  }

  shouldExecute(opportunity) {
    return (
      opportunity.profit_estimate > 50 &&
      opportunity.confidence_score > 0.85 &&
      opportunity.risk_level !== 'high'
    );
  }
}
```

### 2. Portfolio Manager
```typescript
class MEVPortfolioManager {
  constructor(apiKey: string) {
    this.client = new MEVClient({ apiKey });
    this.positions = new Map();
  }

  async getPortfolioValue() {
    const analytics = await this.client.analytics.getPerformance('24h');
    const balances = await this.client.wallet.getBalances();
    
    return {
      totalValue: balances.total_usd,
      dailyPnL: analytics.net_profit,
      unrealizedPnL: this.calculateUnrealizedPnL(),
      positions: Array.from(this.positions.values())
    };
  }

  async rebalance() {
    const portfolio = await this.getPortfolioValue();
    
    // Implement rebalancing logic
    if (portfolio.dailyPnL < -1000) {
      // Reduce position sizes
      await this.reduceExposure();
    } else if (portfolio.dailyPnL > 5000) {
      // Take profits
      await this.takeProfits();
    }
  }
}
```

## Testing

### Unit Testing with Jest
```typescript
import { MEVClient } from '@mev-infrastructure/sdk';
import nock from 'nock';

describe('MEV Client', () => {
  let client: MEVClient;

  beforeEach(() => {
    client = new MEVClient({
      apiKey: 'test_key',
      baseUrl: 'https://api.test.com'
    });
  });

  test('should fetch opportunities', async () => {
    const mockResponse = {
      success: true,
      data: { opportunities: [] }
    };

    nock('https://api.test.com')
      .get('/v1/mev/opportunities')
      .reply(200, mockResponse);

    const result = await client.opportunities.list();
    expect(result.opportunities).toEqual([]);
  });
});
```

### Integration Testing
```typescript
describe('MEV Integration Tests', () => {
  test('should execute opportunity end-to-end', async () => {
    const client = new MEVClient({
      apiKey: process.env.TEST_API_KEY,
      baseUrl: process.env.TEST_BASE_URL
    });

    // Get opportunities
    const opportunities = await client.opportunities.list({
      chain: 'ethereum',
      strategy: 'arbitrage'
    });

    expect(opportunities.length).toBeGreaterThan(0);

    // Execute first opportunity (in test environment)
    const execution = await client.opportunities.execute(opportunities[0].id, {
      slippageTolerance: 0.05
    });

    expect(execution.status).toBe('pending');
  });
});
```

## Rate Limiting and Quotas

### Understanding Rate Limits
- Rate limits are enforced per API key
- Limits reset every minute
- Rate limit headers are included in all responses

### Rate Limit Headers
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 995  
X-RateLimit-Reset: 1642694400
```

### Handling Rate Limits
```typescript
class RateLimitHandler {
  constructor(client: MEVClient) {
    this.client = client;
    this.requestQueue = [];
    this.processing = false;
  }

  async makeRequest(requestFn: Function) {
    return new Promise((resolve, reject) => {
      this.requestQueue.push({ requestFn, resolve, reject });
      this.processQueue();
    });
  }

  async processQueue() {
    if (this.processing || this.requestQueue.length === 0) return;
    
    this.processing = true;
    
    while (this.requestQueue.length > 0) {
      const { requestFn, resolve, reject } = this.requestQueue.shift();
      
      try {
        const result = await requestFn();
        resolve(result);
      } catch (error) {
        if (error.status === 429) {
          // Rate limited - wait and retry
          const retryAfter = parseInt(error.headers['retry-after']) || 60;
          await this.sleep(retryAfter * 1000);
          this.requestQueue.unshift({ requestFn, resolve, reject });
          continue;
        }
        reject(error);
      }
      
      // Small delay between requests
      await this.sleep(100);
    }
    
    this.processing = false;
  }

  sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
```

This comprehensive API integration guide provides everything developers need to build sophisticated MEV applications on top of our infrastructure. The examples cover common use cases while demonstrating best practices for performance, security, and reliability.