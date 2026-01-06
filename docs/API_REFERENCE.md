# MEV Infrastructure API Reference

## 🚀 API Overview

Our MEV infrastructure provides comprehensive APIs for monitoring, analytics, and system management. All APIs are designed for high-performance real-time access with sub-100ms response times.

**Base URLs:**
- Master Orchestrator: `http://localhost:8091`
- Performance Dashboard: `http://localhost:8090`
- MEV Backend: `http://localhost:5000`

## 🔐 Authentication

### API Key Authentication
```http
Authorization: Bearer <API_KEY>
```

### JWT Token Authentication
```http
Authorization: JWT <JWT_TOKEN>
```

## 📊 Master Orchestrator API

### System Status
Get overall system health and status.

**Endpoint:** `GET /api/status`

**Response:**
```json
{
  "timestamp": 1719511200.0,
  "systems": {
    "total": 6,
    "running": 6,
    "healthy": 6,
    "error": 0
  },
  "overall_health_score": 95.2,
  "uptime": 510430,
  "status": "operational"
}
```

### Health Summary
Get detailed health metrics for all systems.

**Endpoint:** `GET /api/health`

**Response:**
```json
{
  "overall_health": 95.2,
  "system_health": {
    "master_orchestrator": {
      "status": "running",
      "health_score": 98.5,
      "cpu_usage": 12.3,
      "memory_usage": 245.6,
      "uptime": 510430
    },
    "performance_dashboard": {
      "status": "running", 
      "health_score": 94.1,
      "cpu_usage": 8.7,
      "memory_usage": 189.2,
      "uptime": 510420
    }
  },
  "alerts": {
    "total": 0,
    "critical": 0,
    "warning": 0
  }
}
```

### Emergency Controls
Activate or deactivate emergency mode.

**Endpoint:** `POST /api/emergency/activate`
**Endpoint:** `POST /api/emergency/deactivate`

**Request:**
```json
{
  "reason": "High memory usage detected",
  "severity": "critical"
}
```

**Response:**
```json
{
  "status": "emergency_activated",
  "timestamp": 1719511200.0,
  "actions_taken": [
    "Reduced position sizes",
    "Activated conservative strategies",
    "Increased monitoring frequency"
  ]
}
```

## 💹 Performance Dashboard API

### Current Metrics
Get real-time performance metrics.

**Endpoint:** `GET /api/metrics`

**Response:**
```json
{
  "timestamp": 1719511200.0,
  "performance": {
    "total_profit_24h": 1410036.35,
    "total_opportunities": 2726,
    "success_rate": 100.0,
    "sharpe_ratio": 2.45,
    "max_drawdown": 0.08,
    "var_95": 15420.50
  },
  "system": {
    "uptime": 510430,
    "active_components": 4,
    "total_components": 4,
    "health_score": 95.2
  }
}
```

### Strategy Performance
Get performance metrics by strategy.

**Endpoint:** `GET /api/strategies`

**Response:**
```json
{
  "strategies": [
    {
      "name": "Cross-Chain MEV",
      "executions": 0,
      "profit": 0.00,
      "success_rate": 0.0,
      "status": "active"
    },
    {
      "name": "Bridge Monitor", 
      "executions": 0,
      "profit": 0.00,
      "success_rate": 0.0,
      "status": "active"
    },
    {
      "name": "Strategy Engine",
      "executions": 2,
      "profit": 824.94,
      "success_rate": 100.0,
      "status": "active"
    }
  ]
}
```

### Executive Summary
Get executive-level performance summary.

**Endpoint:** `GET /api/summary/{period}`

**Parameters:**
- `period`: `daily`, `weekly`, `monthly`

**Response:**
```json
{
  "period": "daily",
  "summary": {
    "total_profit": 1410036.35,
    "profit_change": "+15.2%",
    "opportunities": 2726,
    "success_rate": 100.0,
    "best_strategy": "Strategy Engine",
    "risk_metrics": {
      "var_95": 15420.50,
      "max_drawdown": 0.08,
      "volatility": 0.12
    }
  },
  "recommendations": [
    "Continue current strategy allocation",
    "Monitor gas price trends for optimization",
    "Consider expanding cross-chain operations"
  ]
}
```

### Active Alerts
Get current system alerts.

**Endpoint:** `GET /api/alerts`

**Response:**
```json
{
  "alerts": [
    {
      "id": "alert_001",
      "severity": "warning",
      "system": "memory_monitor",
      "message": "Memory usage approaching 80%",
      "timestamp": 1719511200.0,
      "acknowledged": false
    }
  ],
  "summary": {
    "total": 1,
    "critical": 0,
    "warning": 1,
    "info": 0
  }
}
```

## 🤖 Predictive Analytics API

### Latest Predictions
Get most recent ML predictions.

**Endpoint:** `GET /api/predictions`

**Parameters:**
- `limit`: Number of predictions to return (default: 10)
- `strategy`: Filter by strategy type

**Response:**
```json
{
  "predictions": [
    {
      "id": "pred_001",
      "timestamp": 1719511200.0,
      "strategy": "arbitrage",
      "predicted_profit": 1250.75,
      "confidence": 0.87,
      "gas_estimate": 150000,
      "execution_window": 30
    }
  ],
  "model_performance": {
    "accuracy": 87.3,
    "precision": 89.1,
    "recall": 85.6,
    "last_updated": 1719510000.0
  }
}
```

### Market Forecasts
Get market trend forecasts.

**Endpoint:** `GET /api/forecasts`

**Parameters:**
- `chain_id`: Blockchain network ID
- `timeframe`: `1h`, `4h`, `1d`, `1w`

**Response:**
```json
{
  "forecasts": [
    {
      "chain_id": 1,
      "asset": "ETH",
      "current_price": 3456.78,
      "predicted_price": 3489.12,
      "price_change": "+0.94%",
      "confidence": 0.82,
      "timeframe": "1h"
    }
  ],
  "market_conditions": {
    "volatility": "moderate",
    "trend": "bullish",
    "volume": "high"
  }
}
```

### MEV Opportunities
Get predicted MEV opportunities.

**Endpoint:** `GET /api/opportunities`

**Parameters:**
- `min_profit`: Minimum profit threshold
- `max_risk`: Maximum risk level

**Response:**
```json
{
  "opportunities": [
    {
      "id": "opp_001", 
      "type": "sandwich",
      "chain_id": 1,
      "predicted_profit": 2340.50,
      "risk_score": 0.15,
      "gas_cost": 0.08,
      "execution_time": 12,
      "confidence": 0.91
    }
  ],
  "summary": {
    "total_opportunities": 45,
    "average_profit": 1456.78,
    "average_confidence": 0.84
  }
}
```

## 🔔 Alerting System API

### Active Alerts
Get current active alerts.

**Endpoint:** `GET /api/alerts/active`

**Response:**
```json
{
  "alerts": [
    {
      "id": "alert_001",
      "rule_id": "high_memory",
      "severity": "warning",
      "status": "active",
      "created_at": 1719511200.0,
      "message": "Memory usage above threshold",
      "current_value": 82.5,
      "threshold": 80.0,
      "auto_remediation": true
    }
  ]
}
```

### Acknowledge Alert
Mark an alert as acknowledged.

**Endpoint:** `POST /api/alerts/{alert_id}/acknowledge`

**Request:**
```json
{
  "acknowledged_by": "admin",
  "notes": "Investigating memory usage spike"
}
```

### Alert Configuration
Get or update alert rules.

**Endpoint:** `GET /api/alerts/rules`
**Endpoint:** `PUT /api/alerts/rules/{rule_id}`

**Response:**
```json
{
  "rules": [
    {
      "rule_id": "high_memory",
      "name": "High Memory Usage",
      "metric": "memory_usage_percent",
      "condition": "greater_than",
      "threshold": 80.0,
      "severity": "warning",
      "adaptive": true
    }
  ]
}
```

## 💰 Revenue Optimization API

### Portfolio Metrics
Get current portfolio performance.

**Endpoint:** `GET /api/portfolio/metrics`

**Response:**
```json
{
  "portfolio": {
    "total_value": 1000000.0,
    "allocated_capital": 850000.0,
    "available_capital": 150000.0,
    "total_return": 15.2,
    "sharpe_ratio": 2.45,
    "sortino_ratio": 3.12,
    "max_drawdown": 0.08
  },
  "allocations": [
    {
      "strategy": "arbitrage",
      "allocation": 0.35,
      "value": 350000.0,
      "return": 18.7
    },
    {
      "strategy": "sandwich",
      "allocation": 0.25,
      "value": 250000.0,
      "return": 12.3
    }
  ]
}
```

### Optimization Recommendations
Get portfolio optimization suggestions.

**Endpoint:** `GET /api/portfolio/optimize`

**Response:**
```json
{
  "recommendations": [
    {
      "action": "rebalance",
      "strategy": "arbitrage",
      "current_allocation": 0.35,
      "recommended_allocation": 0.40,
      "expected_improvement": "+2.1% annual return"
    }
  ],
  "optimization_score": 8.7,
  "risk_budget": {
    "total_risk": 0.15,
    "allocated_risk": 0.12,
    "available_risk": 0.03
  }
}
```

## 🕵️ Competitive Intelligence API

### Competitor Analysis
Get competitor performance data.

**Endpoint:** `GET /api/competitors`

**Response:**
```json
{
  "competitors": [
    {
      "id": "comp_001",
      "name": "Competitor A",
      "market_share": 15.3,
      "estimated_volume": 25000000,
      "strategies": ["arbitrage", "liquidation"],
      "performance_trend": "stable"
    }
  ],
  "market_overview": {
    "total_mev_volume": 150000000,
    "our_market_share": 8.7,
    "growth_rate": "+12.5%"
  }
}
```

### Market Share Analysis
Get detailed market share breakdown.

**Endpoint:** `GET /api/market-share`

**Parameters:**
- `timeframe`: `24h`, `7d`, `30d`

**Response:**
```json
{
  "timeframe": "24h",
  "market_share": {
    "our_share": 8.7,
    "rank": 3,
    "volume": 13050000,
    "transactions": 1250
  },
  "competitors": [
    {
      "rank": 1,
      "market_share": 22.1,
      "volume": 33150000
    },
    {
      "rank": 2, 
      "market_share": 18.5,
      "volume": 27750000
    }
  ]
}
```

## 🔗 MEV Backend API

### System Status
Get MEV system operational status.

**Endpoint:** `GET /api/status`

**Response:**
```json
{
  "status": "operational",
  "components": {
    "cross_chain_mev": "active",
    "bridge_monitor": "active", 
    "strategy_engine": "active",
    "analytics_engine": "active"
  },
  "performance": {
    "profit_24h": 1410036.35,
    "opportunities": 2726,
    "success_rate": 100.0
  }
}
```

### Recent Opportunities
Get recently detected opportunities.

**Endpoint:** `GET /api/opportunities/recent`

**Parameters:**
- `limit`: Number of opportunities (default: 50)
- `status`: `detected`, `executed`, `missed`

**Response:**
```json
{
  "opportunities": [
    {
      "id": "opp_001",
      "type": "arbitrage",
      "chain_id": 1,
      "detected_at": 1719511200.0,
      "profit": 1234.56,
      "gas_cost": 0.05,
      "status": "executed",
      "execution_time": 850
    }
  ],
  "summary": {
    "total": 2726,
    "executed": 2,
    "missed": 0,
    "success_rate": 100.0
  }
}
```

### Execute Strategy
Manually trigger strategy execution.

**Endpoint:** `POST /api/strategies/execute`

**Request:**
```json
{
  "strategy": "arbitrage",
  "chain_id": 1,
  "target_profit": 1000.0,
  "max_gas": 0.1,
  "timeout": 30
}
```

**Response:**
```json
{
  "execution_id": "exec_001",
  "status": "submitted",
  "estimated_profit": 1250.75,
  "gas_estimate": 0.08,
  "submission_time": 1719511200.0
}
```

## 🚨 Error Handling

### Standard Error Response
```json
{
  "error": {
    "code": "INSUFFICIENT_CAPITAL",
    "message": "Insufficient capital for strategy execution",
    "details": {
      "required": 10000.0,
      "available": 8500.0
    },
    "timestamp": 1719511200.0
  }
}
```

### HTTP Status Codes
- `200`: Success
- `400`: Bad Request
- `401`: Unauthorized  
- `403`: Forbidden
- `404`: Not Found
- `429`: Rate Limited
- `500`: Internal Server Error
- `503`: Service Unavailable

## 📝 Rate Limiting

### Default Limits
- **General API**: 100 requests/minute
- **Real-time Data**: 1000 requests/minute
- **Strategy Execution**: 10 requests/minute

### Rate Limit Headers
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1719511260
```

## 🔧 WebSocket APIs

### Real-time Performance Data
**Endpoint:** `ws://localhost:8090/ws/performance`

**Message Format:**
```json
{
  "type": "performance_update",
  "data": {
    "profit": 1410036.35,
    "opportunities": 2726,
    "timestamp": 1719511200.0
  }
}
```

### Live Alerts
**Endpoint:** `ws://localhost:8091/ws/alerts`

**Message Format:**
```json
{
  "type": "alert",
  "data": {
    "id": "alert_001",
    "severity": "warning",
    "message": "Memory usage above threshold",
    "timestamp": 1719511200.0
  }
}
```

## 📊 Data Models

### Opportunity Model
```json
{
  "id": "string",
  "type": "arbitrage|sandwich|liquidation|flashloan",
  "chain_id": "number",
  "detected_at": "timestamp",
  "executed_at": "timestamp|null",
  "profit": "number",
  "gas_cost": "number", 
  "risk_score": "number",
  "confidence": "number",
  "status": "detected|executed|missed|failed"
}
```

### Strategy Model
```json
{
  "name": "string",
  "type": "arbitrage|sandwich|liquidation",
  "status": "active|paused|stopped",
  "allocation": "number",
  "executions": "number",
  "total_profit": "number",
  "success_rate": "number",
  "average_profit": "number",
  "risk_level": "low|medium|high"
}
```

### Alert Model
```json
{
  "id": "string",
  "rule_id": "string", 
  "severity": "info|warning|critical",
  "status": "active|acknowledged|resolved",
  "message": "string",
  "created_at": "timestamp",
  "acknowledged_at": "timestamp|null",
  "resolved_at": "timestamp|null",
  "auto_remediation": "boolean"
}
```

---

**API Version**: 2.0.0
**Last Updated**: 2025-06-27
**Rate Limits**: Standard enterprise limits apply
**Authentication**: Bearer token required for all endpoints