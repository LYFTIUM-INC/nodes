# API Documentation - Complete RPC Endpoints & MEV Engine APIs
**Version 3.6.5 | July 2025**

## Table of Contents
1. [API Overview](#api-overview)
2. [Authentication & Security](#authentication--security)
3. [RPC Endpoints](#rpc-endpoints)
4. [MEV Engine APIs](#mev-engine-apis)
5. [WebSocket Streaming APIs](#websocket-streaming-apis)
6. [Rate Limiting Guidelines](#rate-limiting-guidelines)
7. [Integration Examples](#integration-examples)
8. [Error Handling](#error-handling)

---

## API Overview

### Base URLs

| Service | Environment | Base URL | Port |
|---------|------------|----------|------|
| Ethereum RPC | Production | http://localhost | 8545 |
| Arbitrum RPC | Production | http://localhost | 8590 |
| Optimism RPC | Production | http://localhost | 8591 |
| Base RPC | Production | http://localhost | 8592 |
| Polygon RPC | Production | http://localhost | 8593 |
| MEV Engine API | Production | http://localhost | 8082 |
| MEV WebSocket | Production | ws://localhost | 8083 |
| Monitoring API | Production | http://localhost | 8081 |

### API Standards

- **Protocol**: JSON-RPC 2.0 for blockchain RPCs, REST for MEV APIs
- **Content-Type**: application/json
- **Authentication**: API key required for MEV operations
- **Rate Limiting**: See [Rate Limiting Guidelines](#rate-limiting-guidelines)
- **Versioning**: API version in URL path (e.g., /api/v1/)

---

## Authentication & Security

### API Key Authentication

```bash
# Request header format
Authorization: Bearer YOUR_API_KEY

# Example request
curl -H "Authorization: Bearer mev-prod-key-2025" \
     -H "Content-Type: application/json" \
     http://localhost:8082/api/v1/opportunities
```

### API Key Management

```python
# Generate API key
POST /api/v1/auth/generate-key
{
  "name": "production-key",
  "permissions": ["read", "execute", "admin"],
  "rate_limit": 1000,
  "expires_at": "2026-01-01T00:00:00Z"
}

# Response
{
  "api_key": "mev-prod-key-2025-xxxxx",
  "key_id": "key_123456",
  "created_at": "2025-07-17T00:00:00Z",
  "permissions": ["read", "execute", "admin"]
}
```

### Security Headers

```http
X-Request-ID: unique-request-id
X-Timestamp: 1626345600
X-Signature: HMAC-SHA256(payload + timestamp)
```

---

## RPC Endpoints

### Standard Ethereum RPC Methods

#### eth_blockNumber
Get the latest block number.

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_blockNumber",
    "params": [],
    "id": 1
  }'

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0x1234567"
}
```

#### eth_getBalance
Get balance of an address.

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_getBalance",
    "params": ["0x742d35Cc6634C0532925a3b844Bc9e7595f7BBa", "latest"],
    "id": 1
  }'
```

#### eth_sendRawTransaction
Submit a signed transaction.

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_sendRawTransaction",
    "params": ["0xf869..."],
    "id": 1
  }'
```

### MEV-Specific RPC Extensions

#### eth_sendBundle
Submit a bundle of transactions to MEV-Boost.

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_sendBundle",
    "params": [{
      "txs": ["0xraw_tx_1", "0xraw_tx_2"],
      "blockNumber": "0x1234567",
      "minTimestamp": 1626345600,
      "maxTimestamp": 1626345700,
      "revertingTxHashes": []
    }],
    "id": 1
  }'
```

#### eth_callBundle
Simulate bundle execution.

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_callBundle",
    "params": [{
      "txs": ["0xraw_tx_1", "0xraw_tx_2"],
      "blockNumber": "0x1234567",
      "stateBlockNumber": "latest",
      "timestamp": 1626345600
    }],
    "id": 1
  }'
```

### Multi-Chain RPC Endpoints

Each chain follows the same RPC standard with chain-specific extensions:

```python
# Chain-specific endpoints
chains = {
    "ethereum": "http://localhost:8545",
    "arbitrum": "http://localhost:8590",
    "optimism": "http://localhost:8591",
    "base": "http://localhost:8592",
    "polygon": "http://localhost:8593"
}

# Example: Get block on Arbitrum
response = requests.post(chains["arbitrum"], json={
    "jsonrpc": "2.0",
    "method": "eth_getBlockByNumber",
    "params": ["latest", True],
    "id": 1
})
```

---

## MEV Engine APIs

### Opportunity Detection API

#### GET /api/v1/opportunities
List current MEV opportunities.

```bash
curl -X GET "http://localhost:8082/api/v1/opportunities?limit=10&min_profit=0.01" \
  -H "Authorization: Bearer YOUR_API_KEY"

# Response
{
  "opportunities": [
    {
      "id": "opp_123456",
      "type": "arbitrage",
      "chain_id": 1,
      "estimated_profit_eth": 0.05,
      "gas_estimate": 250000,
      "deadline": 1626345700,
      "confidence": 0.85,
      "details": {
        "token_in": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        "token_out": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        "amount_in": "10000000000",
        "dex_path": ["uniswap_v3", "sushiswap"]
      }
    }
  ],
  "total": 42,
  "timestamp": 1626345600
}
```

#### GET /api/v1/opportunities/{id}
Get specific opportunity details.

```bash
curl -X GET "http://localhost:8082/api/v1/opportunities/opp_123456" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

#### POST /api/v1/opportunities/analyze
Analyze a potential opportunity.

```bash
curl -X POST "http://localhost:8082/api/v1/opportunities/analyze" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "arbitrage",
    "token_a": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "token_b": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    "amount": "1000000000000",
    "dexes": ["uniswap_v3", "sushiswap", "curve"]
  }'
```

### Strategy Execution API

#### POST /api/v1/execute
Execute MEV strategy.

```bash
curl -X POST "http://localhost:8082/api/v1/execute" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "opportunity_id": "opp_123456",
    "strategy": "arbitrage",
    "params": {
      "max_gas_price_gwei": 100,
      "slippage_tolerance": 0.01,
      "use_flashloan": false,
      "dry_run": false
    }
  }'

# Response
{
  "execution_id": "exec_789012",
  "status": "pending",
  "transactions": [
    {
      "hash": "0x123...",
      "type": "swap",
      "status": "submitted"
    }
  ],
  "estimated_profit": 0.048,
  "gas_used": 245000
}
```

#### GET /api/v1/executions/{id}
Get execution status.

```bash
curl -X GET "http://localhost:8082/api/v1/executions/exec_789012" \
  -H "Authorization: Bearer YOUR_API_KEY"

# Response
{
  "execution_id": "exec_789012",
  "status": "completed",
  "result": "success",
  "actual_profit_eth": 0.045,
  "gas_cost_eth": 0.012,
  "net_profit_eth": 0.033,
  "block_number": 18234567,
  "transactions": [
    {
      "hash": "0x123...",
      "status": "confirmed",
      "gas_used": 245000
    }
  ]
}
```

### Bundle Management API

#### POST /api/v1/bundles
Create and submit bundle.

```bash
curl -X POST "http://localhost:8082/api/v1/bundles" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "transactions": [
      {
        "raw": "0xf869...",
        "can_revert": false
      },
      {
        "raw": "0xf870...",
        "can_revert": true
      }
    ],
    "target_block": "latest+1",
    "min_profit_eth": 0.02,
    "max_retries": 3
  }'
```

#### GET /api/v1/bundles/{id}/status
Check bundle inclusion status.

```bash
curl -X GET "http://localhost:8082/api/v1/bundles/bundle_345678/status" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### Performance & Analytics API

#### GET /api/v1/stats
Get MEV performance statistics.

```bash
curl -X GET "http://localhost:8082/api/v1/stats?period=24h" \
  -H "Authorization: Bearer YOUR_API_KEY"

# Response
{
  "period": "24h",
  "metrics": {
    "total_opportunities": 1523,
    "executed_opportunities": 245,
    "success_rate": 0.82,
    "total_profit_eth": 12.45,
    "total_gas_cost_eth": 3.21,
    "net_profit_eth": 9.24,
    "average_profit_per_opportunity": 0.0377,
    "best_strategy": "arbitrage",
    "most_profitable_chain": "ethereum"
  },
  "hourly_breakdown": [
    {
      "hour": "2025-07-17T00:00:00Z",
      "opportunities": 63,
      "profit_eth": 0.52
    }
  ]
}
```

#### GET /api/v1/performance/strategies
Get strategy performance breakdown.

```bash
curl -X GET "http://localhost:8082/api/v1/performance/strategies" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

---

## WebSocket Streaming APIs

### Connection

```javascript
// JavaScript WebSocket connection
const ws = new WebSocket('ws://localhost:8083');

ws.on('open', () => {
  // Authenticate
  ws.send(JSON.stringify({
    type: 'auth',
    api_key: 'YOUR_API_KEY'
  }));
  
  // Subscribe to opportunities
  ws.send(JSON.stringify({
    type: 'subscribe',
    channels: ['opportunities', 'executions', 'blocks']
  }));
});

ws.on('message', (data) => {
  const message = JSON.parse(data);
  console.log('Received:', message);
});
```

### Subscription Channels

#### opportunities
Real-time MEV opportunities.

```json
{
  "channel": "opportunities",
  "data": {
    "id": "opp_123456",
    "type": "arbitrage",
    "chain_id": 1,
    "estimated_profit_eth": 0.05,
    "timestamp": 1626345600
  }
}
```

#### executions
Execution status updates.

```json
{
  "channel": "executions",
  "data": {
    "execution_id": "exec_789012",
    "status": "completed",
    "profit_eth": 0.045,
    "timestamp": 1626345700
  }
}
```

#### blocks
New block notifications.

```json
{
  "channel": "blocks",
  "data": {
    "chain_id": 1,
    "block_number": 18234567,
    "block_hash": "0xabc...",
    "base_fee_gwei": 25,
    "timestamp": 1626345600
  }
}
```

#### mempool
Mempool transaction stream.

```json
{
  "channel": "mempool",
  "data": {
    "chain_id": 1,
    "tx_hash": "0xdef...",
    "from": "0x...",
    "to": "0x...",
    "value": "1000000000000000000",
    "gas_price": "30000000000",
    "input": "0x..."
  }
}
```

### WebSocket Commands

```javascript
// Unsubscribe from channel
ws.send(JSON.stringify({
  type: 'unsubscribe',
  channels: ['mempool']
}));

// Request snapshot
ws.send(JSON.stringify({
  type: 'snapshot',
  channel: 'opportunities'
}));

// Ping/Pong for keepalive
ws.send(JSON.stringify({
  type: 'ping'
}));
```

---

## Rate Limiting Guidelines

### Rate Limit Tiers

| Tier | Requests/Minute | Requests/Day | WebSocket Connections |
|------|-----------------|--------------|----------------------|
| Basic | 60 | 10,000 | 1 |
| Professional | 300 | 100,000 | 5 |
| Enterprise | 1000 | 1,000,000 | 20 |
| Custom | Negotiated | Negotiated | Negotiated |

### Rate Limit Headers

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1626345700
X-RateLimit-Reset-After: 60
```

### Handling Rate Limits

```python
import time
import requests

def make_request_with_retry(url, headers, data=None):
    while True:
        response = requests.post(url, headers=headers, json=data)
        
        if response.status_code == 429:  # Rate limited
            retry_after = int(response.headers.get('X-RateLimit-Reset-After', 60))
            print(f"Rate limited. Waiting {retry_after} seconds...")
            time.sleep(retry_after)
            continue
            
        return response
```

---

## Integration Examples

### Python Integration

```python
import requests
import json
from typing import Dict, List

class MEVClient:
    def __init__(self, base_url: str, api_key: str):
        self.base_url = base_url
        self.headers = {
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        }
    
    def get_opportunities(self, min_profit: float = 0.01) -> List[Dict]:
        """Fetch current MEV opportunities"""
        response = requests.get(
            f"{self.base_url}/api/v1/opportunities",
            headers=self.headers,
            params={'min_profit': min_profit}
        )
        response.raise_for_status()
        return response.json()['opportunities']
    
    def execute_opportunity(self, opportunity_id: str, **params) -> Dict:
        """Execute an MEV opportunity"""
        response = requests.post(
            f"{self.base_url}/api/v1/execute",
            headers=self.headers,
            json={
                'opportunity_id': opportunity_id,
                'params': params
            }
        )
        response.raise_for_status()
        return response.json()
    
    def get_execution_status(self, execution_id: str) -> Dict:
        """Check execution status"""
        response = requests.get(
            f"{self.base_url}/api/v1/executions/{execution_id}",
            headers=self.headers
        )
        response.raise_for_status()
        return response.json()

# Example usage
client = MEVClient('http://localhost:8082', 'YOUR_API_KEY')

# Get opportunities
opportunities = client.get_opportunities(min_profit=0.02)
for opp in opportunities:
    print(f"Opportunity {opp['id']}: {opp['estimated_profit_eth']} ETH")

# Execute best opportunity
if opportunities:
    best_opp = max(opportunities, key=lambda x: x['estimated_profit_eth'])
    execution = client.execute_opportunity(
        best_opp['id'],
        max_gas_price_gwei=100,
        slippage_tolerance=0.01
    )
    print(f"Execution {execution['execution_id']} started")
```

### Node.js Integration

```javascript
const axios = require('axios');

class MEVClient {
  constructor(baseUrl, apiKey) {
    this.baseUrl = baseUrl;
    this.headers = {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    };
  }
  
  async getOpportunities(minProfit = 0.01) {
    const response = await axios.get(
      `${this.baseUrl}/api/v1/opportunities`,
      {
        headers: this.headers,
        params: { min_profit: minProfit }
      }
    );
    return response.data.opportunities;
  }
  
  async executeOpportunity(opportunityId, params = {}) {
    const response = await axios.post(
      `${this.baseUrl}/api/v1/execute`,
      {
        opportunity_id: opportunityId,
        params: params
      },
      { headers: this.headers }
    );
    return response.data;
  }
}

// Example usage
const client = new MEVClient('http://localhost:8082', 'YOUR_API_KEY');

(async () => {
  try {
    // Get opportunities
    const opportunities = await client.getOpportunities(0.02);
    console.log(`Found ${opportunities.length} opportunities`);
    
    // Execute best opportunity
    if (opportunities.length > 0) {
      const bestOpp = opportunities.reduce((a, b) => 
        a.estimated_profit_eth > b.estimated_profit_eth ? a : b
      );
      
      const execution = await client.executeOpportunity(bestOpp.id, {
        max_gas_price_gwei: 100,
        slippage_tolerance: 0.01
      });
      
      console.log(`Execution ${execution.execution_id} started`);
    }
  } catch (error) {
    console.error('Error:', error.response?.data || error.message);
  }
})();
```

### Rust Integration

```rust
use reqwest::{Client, header};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Deserialize)]
struct Opportunity {
    id: String,
    #[serde(rename = "type")]
    opp_type: String,
    estimated_profit_eth: f64,
    gas_estimate: u64,
}

#[derive(Debug, Deserialize)]
struct OpportunitiesResponse {
    opportunities: Vec<Opportunity>,
    total: u32,
}

struct MEVClient {
    client: Client,
    base_url: String,
    api_key: String,
}

impl MEVClient {
    fn new(base_url: &str, api_key: &str) -> Self {
        MEVClient {
            client: Client::new(),
            base_url: base_url.to_string(),
            api_key: api_key.to_string(),
        }
    }
    
    async fn get_opportunities(&self, min_profit: f64) -> Result<Vec<Opportunity>, Box<dyn std::error::Error>> {
        let mut headers = header::HeaderMap::new();
        headers.insert(
            header::AUTHORIZATION,
            header::HeaderValue::from_str(&format!("Bearer {}", self.api_key))?
        );
        
        let params = [("min_profit", min_profit.to_string())];
        
        let response = self.client
            .get(&format!("{}/api/v1/opportunities", self.base_url))
            .headers(headers)
            .query(&params)
            .send()
            .await?;
        
        let data: OpportunitiesResponse = response.json().await?;
        Ok(data.opportunities)
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = MEVClient::new("http://localhost:8082", "YOUR_API_KEY");
    
    let opportunities = client.get_opportunities(0.02).await?;
    
    for opp in opportunities {
        println!("Opportunity {}: {} ETH", opp.id, opp.estimated_profit_eth);
    }
    
    Ok(())
}
```

---

## Error Handling

### Error Response Format

```json
{
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "Insufficient balance for transaction",
    "details": {
      "required": "1.5",
      "available": "1.2",
      "unit": "ETH"
    },
    "request_id": "req_123456",
    "timestamp": 1626345600
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| UNAUTHORIZED | 401 | Invalid or missing API key |
| FORBIDDEN | 403 | Insufficient permissions |
| NOT_FOUND | 404 | Resource not found |
| RATE_LIMITED | 429 | Rate limit exceeded |
| INVALID_PARAMS | 400 | Invalid request parameters |
| INSUFFICIENT_BALANCE | 400 | Insufficient balance for operation |
| GAS_TOO_HIGH | 400 | Gas price exceeds limits |
| OPPORTUNITY_EXPIRED | 410 | Opportunity no longer available |
| EXECUTION_FAILED | 500 | Strategy execution failed |
| INTERNAL_ERROR | 500 | Internal server error |

### Error Handling Best Practices

```python
def handle_api_response(response):
    """Handle API response with proper error checking"""
    if response.status_code == 200:
        return response.json()
    
    error_data = response.json().get('error', {})
    error_code = error_data.get('code', 'UNKNOWN')
    error_message = error_data.get('message', 'Unknown error')
    
    if response.status_code == 429:
        # Handle rate limiting
        retry_after = response.headers.get('X-RateLimit-Reset-After', 60)
        raise RateLimitError(f"Rate limited. Retry after {retry_after} seconds")
    
    elif response.status_code == 401:
        # Handle authentication errors
        raise AuthenticationError("Invalid API key")
    
    elif response.status_code == 400:
        # Handle client errors
        if error_code == 'INSUFFICIENT_BALANCE':
            raise InsufficientBalanceError(error_message, error_data.get('details'))
        elif error_code == 'GAS_TOO_HIGH':
            raise GasTooHighError(error_message, error_data.get('details'))
        else:
            raise ClientError(error_message)
    
    elif response.status_code >= 500:
        # Handle server errors
        raise ServerError(f"Server error: {error_message}")
    
    else:
        raise APIError(f"Unexpected error: {error_code} - {error_message}")
```

---

## Appendix: API Quick Reference

### Common Endpoints

```bash
# Health check
GET /health

# API status
GET /api/v1/status

# Get opportunities
GET /api/v1/opportunities

# Execute strategy
POST /api/v1/execute

# Get execution status
GET /api/v1/executions/{id}

# Performance stats
GET /api/v1/stats

# Submit bundle
POST /api/v1/bundles

# WebSocket connection
WS ws://localhost:8083
```

### Required Headers

```http
Authorization: Bearer YOUR_API_KEY
Content-Type: application/json
X-Request-ID: unique-request-id
```

### Response Headers

```http
X-Request-ID: unique-request-id
X-Response-Time: 125ms
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
```

---

**Document Classification**: CONFIDENTIAL - INTERNAL USE ONLY  
**API Version**: 1.0  
**Last Updated**: July 17, 2025  
**Next Review**: August 17, 2025