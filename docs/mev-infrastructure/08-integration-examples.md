# Integration Examples - MEV Infrastructure Platform

## Overview

This document provides comprehensive code samples and integration patterns for connecting with the MEV Infrastructure Platform. These examples demonstrate best practices for institutional-grade integrations, covering common use cases from basic monitoring to advanced trading automation.

## Getting Started

### Authentication Setup

#### API Key Configuration

```python
# config/api_config.py
import os
from typing import Optional

class MEVPlatformConfig:
    """Configuration class for MEV Platform API integration"""
    
    def __init__(self):
        self.base_url = os.getenv('MEV_API_URL', 'https://api.mev-platform.com/v1')
        self.api_key = os.getenv('MEV_API_KEY')
        self.api_secret = os.getenv('MEV_API_SECRET')
        self.timeout = int(os.getenv('MEV_API_TIMEOUT', '30'))
        self.rate_limit = int(os.getenv('MEV_RATE_LIMIT', '1000'))
        
        if not self.api_key or not self.api_secret:
            raise ValueError("MEV_API_KEY and MEV_API_SECRET must be set")
    
    @property
    def auth_headers(self) -> dict:
        """Generate authentication headers for API requests"""
        import hmac
        import hashlib
        import time
        import base64
        
        timestamp = str(int(time.time()))
        message = f"{timestamp}{self.api_key}"
        signature = hmac.new(
            self.api_secret.encode(),
            message.encode(),
            hashlib.sha256
        ).hexdigest()
        
        return {
            'X-API-Key': self.api_key,
            'X-Timestamp': timestamp,
            'X-Signature': signature,
            'Content-Type': 'application/json'
        }
```

#### JWT Token Management

```python
# auth/jwt_manager.py
import jwt
import time
import requests
from typing import Optional, Dict, Any

class JWTManager:
    """Manages JWT token authentication and refresh"""
    
    def __init__(self, config: MEVPlatformConfig):
        self.config = config
        self.access_token: Optional[str] = None
        self.refresh_token: Optional[str] = None
        self.token_expires_at: Optional[float] = None
    
    def authenticate(self) -> str:
        """Authenticate and obtain JWT token"""
        auth_data = {
            'api_key': self.config.api_key,
            'api_secret': self.config.api_secret
        }
        
        response = requests.post(
            f"{self.config.base_url}/auth/token",
            json=auth_data,
            timeout=self.config.timeout
        )
        response.raise_for_status()
        
        token_data = response.json()
        self.access_token = token_data['access_token']
        self.refresh_token = token_data['refresh_token']
        self.token_expires_at = time.time() + token_data['expires_in'] - 60  # 60s buffer
        
        return self.access_token
    
    def get_valid_token(self) -> str:
        """Get a valid access token, refreshing if necessary"""
        if not self.access_token or time.time() >= self.token_expires_at:
            if self.refresh_token:
                self._refresh_token()
            else:
                self.authenticate()
        
        return self.access_token
    
    def _refresh_token(self):
        """Refresh the access token using refresh token"""
        response = requests.post(
            f"{self.config.base_url}/auth/refresh",
            json={'refresh_token': self.refresh_token},
            timeout=self.config.timeout
        )
        response.raise_for_status()
        
        token_data = response.json()
        self.access_token = token_data['access_token']
        self.token_expires_at = time.time() + token_data['expires_in'] - 60
    
    @property
    def auth_headers(self) -> Dict[str, str]:
        """Get authorization headers with valid token"""
        return {
            'Authorization': f'Bearer {self.get_valid_token()}',
            'Content-Type': 'application/json'
        }
```

## Basic Integration Examples

### 1. System Status Monitoring

#### Simple Health Check

```python
# monitoring/health_check.py
import requests
import logging
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

class HealthMonitor:
    """Monitor MEV Platform system health"""
    
    def __init__(self, config: MEVPlatformConfig):
        self.config = config
        self.jwt_manager = JWTManager(config)
    
    def check_system_health(self) -> Dict[str, Any]:
        """Get comprehensive system health status"""
        try:
            response = requests.get(
                f"{self.config.base_url}/status",
                headers=self.jwt_manager.auth_headers,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            return response.json()
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Health check failed: {e}")
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': time.time()
            }
    
    def check_trading_status(self) -> Dict[str, Any]:
        """Check trading engine status specifically"""
        try:
            response = requests.get(
                f"{self.config.base_url}/trading/status",
                headers=self.jwt_manager.auth_headers,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            return response.json()
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Trading status check failed: {e}")
            return {'is_trading': False, 'error': str(e)}
    
    def monitor_continuously(self, interval: int = 30):
        """Continuously monitor system health"""
        import time
        
        while True:
            health = self.check_system_health()
            trading = self.check_trading_status()
            
            logger.info(f"System Health: {health.get('status')}")
            logger.info(f"Trading Active: {trading.get('is_trading')}")
            
            # Alert on critical issues
            if health.get('status') != 'healthy':
                self._send_alert('System health degraded', health)
            
            if not trading.get('is_trading') and trading.get('error'):
                self._send_alert('Trading engine error', trading)
            
            time.sleep(interval)
    
    def _send_alert(self, message: str, data: Dict[str, Any]):
        """Send alert notification (implement based on your needs)"""
        logger.critical(f"ALERT: {message} - {data}")
        # Add webhook, email, or Slack integration here

# Usage example
if __name__ == "__main__":
    config = MEVPlatformConfig()
    monitor = HealthMonitor(config)
    
    # One-time health check
    health = monitor.check_system_health()
    print(f"System Status: {health}")
    
    # Continuous monitoring
    # monitor.monitor_continuously(interval=60)
```

#### Advanced Metrics Collection

```python
# monitoring/metrics_collector.py
import requests
import time
import json
from typing import Dict, List, Any
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta

@dataclass
class PerformanceMetrics:
    timestamp: float
    latency_ms: float
    throughput_tps: float
    active_opportunities: int
    session_pnl: float
    success_rate: float
    cpu_usage: float
    memory_usage: float

class MetricsCollector:
    """Collect and analyze performance metrics"""
    
    def __init__(self, config: MEVPlatformConfig):
        self.config = config
        self.jwt_manager = JWTManager(config)
        self.metrics_history: List[PerformanceMetrics] = []
    
    def collect_current_metrics(self) -> PerformanceMetrics:
        """Collect current performance metrics"""
        response = requests.get(
            f"{self.config.base_url}/metrics",
            headers=self.jwt_manager.auth_headers,
            params={'timeframe': '5m', 'granularity': '1m'},
            timeout=self.config.timeout
        )
        response.raise_for_status()
        
        data = response.json()['data']
        
        return PerformanceMetrics(
            timestamp=time.time(),
            latency_ms=data['performance']['avg_latency_ms'],
            throughput_tps=data['performance']['throughput_tps'],
            active_opportunities=data['trading']['opportunities_detected'],
            session_pnl=data['trading']['total_profit_usd'],
            success_rate=data['performance']['success_rate'],
            cpu_usage=data['resources']['cpu_usage'],
            memory_usage=data['resources']['memory_usage']
        )
    
    def analyze_performance_trends(self, hours: int = 24) -> Dict[str, Any]:
        """Analyze performance trends over specified period"""
        cutoff_time = time.time() - (hours * 3600)
        recent_metrics = [m for m in self.metrics_history if m.timestamp > cutoff_time]
        
        if not recent_metrics:
            return {'error': 'Insufficient data for analysis'}
        
        # Calculate trends
        latencies = [m.latency_ms for m in recent_metrics]
        throughputs = [m.throughput_tps for m in recent_metrics]
        success_rates = [m.success_rate for m in recent_metrics]
        
        return {
            'period_hours': hours,
            'sample_count': len(recent_metrics),
            'latency': {
                'avg': sum(latencies) / len(latencies),
                'min': min(latencies),
                'max': max(latencies),
                'trend': self._calculate_trend(latencies)
            },
            'throughput': {
                'avg': sum(throughputs) / len(throughputs),
                'min': min(throughputs),
                'max': max(throughputs),
                'trend': self._calculate_trend(throughputs)
            },
            'success_rate': {
                'avg': sum(success_rates) / len(success_rates),
                'min': min(success_rates),
                'max': max(success_rates),
                'trend': self._calculate_trend(success_rates)
            }
        }
    
    def _calculate_trend(self, values: List[float]) -> str:
        """Calculate trend direction for a series of values"""
        if len(values) < 2:
            return 'insufficient_data'
        
        first_half = values[:len(values)//2]
        second_half = values[len(values)//2:]
        
        first_avg = sum(first_half) / len(first_half)
        second_avg = sum(second_half) / len(second_half)
        
        change_pct = ((second_avg - first_avg) / first_avg) * 100
        
        if abs(change_pct) < 5:
            return 'stable'
        elif change_pct > 0:
            return 'improving'
        else:
            return 'declining'
    
    def export_metrics(self, filepath: str, format: str = 'json'):
        """Export collected metrics to file"""
        if format == 'json':
            with open(filepath, 'w') as f:
                json.dump([asdict(m) for m in self.metrics_history], f, indent=2)
        elif format == 'csv':
            import csv
            with open(filepath, 'w', newline='') as f:
                if self.metrics_history:
                    writer = csv.DictWriter(f, fieldnames=asdict(self.metrics_history[0]).keys())
                    writer.writeheader()
                    for metric in self.metrics_history:
                        writer.writerow(asdict(metric))
```

### 2. Trading Integration

#### Basic Trading Operations

```python
# trading/trading_client.py
import requests
import logging
from typing import Dict, List, Any, Optional
from enum import Enum
from dataclasses import dataclass

logger = logging.getLogger(__name__)

class TradingMode(Enum):
    CONSERVATIVE = "conservative"
    BALANCED = "balanced"
    AGGRESSIVE = "aggressive"

class Strategy(Enum):
    ARBITRAGE = "arbitrage"
    SANDWICH = "sandwich"
    LIQUIDATION = "liquidation"
    FLASH_LOAN = "flash_loan"

@dataclass
class TradingConfig:
    mode: TradingMode
    position_size_eth: float
    strategies: List[Strategy]
    chains: List[int]
    max_drawdown: float = 0.05
    max_position_size: float = 10.0
    stop_loss: float = 0.02

class TradingClient:
    """Client for MEV trading operations"""
    
    def __init__(self, config: MEVPlatformConfig):
        self.config = config
        self.jwt_manager = JWTManager(config)
        self.session_id: Optional[str] = None
    
    def start_trading(self, trading_config: TradingConfig) -> Dict[str, Any]:
        """Start trading with specified configuration"""
        request_data = {
            'mode': trading_config.mode.value,
            'position_size_eth': trading_config.position_size_eth,
            'strategies': [s.value for s in trading_config.strategies],
            'chains': trading_config.chains,
            'risk_limits': {
                'max_drawdown': trading_config.max_drawdown,
                'max_position_size': trading_config.max_position_size,
                'stop_loss': trading_config.stop_loss
            }
        }
        
        response = requests.post(
            f"{self.config.base_url}/trading/start",
            headers=self.jwt_manager.auth_headers,
            json=request_data,
            timeout=self.config.timeout
        )
        response.raise_for_status()
        
        result = response.json()
        self.session_id = result.get('session_id')
        
        logger.info(f"Trading started: {self.session_id}")
        return result
    
    def stop_trading(self, close_positions: bool = True) -> Dict[str, Any]:
        """Stop trading operations"""
        request_data = {
            'close_positions': close_positions,
            'force_stop': False
        }
        
        response = requests.post(
            f"{self.config.base_url}/trading/stop",
            headers=self.jwt_manager.auth_headers,
            json=request_data,
            timeout=self.config.timeout
        )
        response.raise_for_status()
        
        result = response.json()
        logger.info(f"Trading stopped. Final PnL: {result.get('final_pnl')}")
        return result
    
    def get_trading_status(self) -> Dict[str, Any]:
        """Get current trading status"""
        response = requests.get(
            f"{self.config.base_url}/trading/status",
            headers=self.jwt_manager.auth_headers,
            timeout=self.config.timeout
        )
        response.raise_for_status()
        return response.json()
    
    def get_current_positions(self) -> List[Dict[str, Any]]:
        """Get current trading positions"""
        response = requests.get(
            f"{self.config.base_url}/positions",
            headers=self.jwt_manager.auth_headers,
            timeout=self.config.timeout
        )
        response.raise_for_status()
        return response.json()['positions']
    
    def get_trade_history(self, 
                         start_date: Optional[str] = None,
                         end_date: Optional[str] = None,
                         strategy: Optional[Strategy] = None,
                         limit: int = 100) -> List[Dict[str, Any]]:
        """Get trade history with optional filters"""
        params = {'limit': limit}
        if start_date:
            params['start_date'] = start_date
        if end_date:
            params['end_date'] = end_date
        if strategy:
            params['strategy'] = strategy.value
        
        response = requests.get(
            f"{self.config.base_url}/trades",
            headers=self.jwt_manager.auth_headers,
            params=params,
            timeout=self.config.timeout
        )
        response.raise_for_status()
        return response.json()['trades']

# Usage example
if __name__ == "__main__":
    config = MEVPlatformConfig()
    client = TradingClient(config)
    
    # Configure trading parameters
    trading_config = TradingConfig(
        mode=TradingMode.CONSERVATIVE,
        position_size_eth=1.0,
        strategies=[Strategy.ARBITRAGE, Strategy.LIQUIDATION],
        chains=[1, 42161, 10],  # Ethereum, Arbitrum, Optimism
        max_drawdown=0.03,
        max_position_size=5.0
    )
    
    try:
        # Start trading
        start_result = client.start_trading(trading_config)
        print(f"Trading started: {start_result['session_id']}")
        
        # Monitor for a while
        import time
        time.sleep(60)  # Trade for 1 minute
        
        # Check status
        status = client.get_trading_status()
        print(f"Session PnL: {status['session_pnl']}")
        
        # Stop trading
        stop_result = client.stop_trading()
        print(f"Final PnL: {stop_result['final_pnl']}")
        
    except Exception as e:
        logger.error(f"Trading error: {e}")
        # Ensure trading is stopped on error
        try:
            client.stop_trading()
        except:
            pass
```

#### Advanced Trading Strategy

```python
# trading/advanced_strategy.py
import asyncio
import websockets
import json
import logging
from typing import Dict, Any, Callable, Optional
from dataclasses import dataclass
from decimal import Decimal

logger = logging.getLogger(__name__)

@dataclass
class TradingSignal:
    signal_type: str
    confidence: float
    expected_profit: float
    risk_score: float
    metadata: Dict[str, Any]

class AdvancedTradingStrategy:
    """Advanced trading strategy with real-time decision making"""
    
    def __init__(self, config: MEVPlatformConfig, trading_client: TradingClient):
        self.config = config
        self.trading_client = trading_client
        self.jwt_manager = JWTManager(config)
        self.is_running = False
        self.signal_handlers: Dict[str, Callable] = {}
        
        # Strategy parameters
        self.min_profit_threshold = 100.0  # USD
        self.max_risk_score = 0.7
        self.position_size_multiplier = 1.0
        
    def register_signal_handler(self, signal_type: str, handler: Callable):
        """Register handler for specific signal types"""
        self.signal_handlers[signal_type] = handler
    
    async def start_strategy(self):
        """Start the advanced trading strategy"""
        self.is_running = True
        
        # Connect to WebSocket for real-time data
        ws_url = f"wss://api.mev-platform.com/v1/ws"
        headers = self.jwt_manager.auth_headers
        
        try:
            async with websockets.connect(
                ws_url,
                extra_headers=headers,
                ping_interval=30,
                ping_timeout=10
            ) as websocket:
                
                # Subscribe to opportunity feed
                await self._subscribe_to_opportunities(websocket)
                
                # Subscribe to trade executions
                await self._subscribe_to_trades(websocket)
                
                # Subscribe to metrics for risk management
                await self._subscribe_to_metrics(websocket)
                
                # Process messages
                async for message in websocket:
                    if not self.is_running:
                        break
                    
                    await self._process_message(json.loads(message))
                    
        except Exception as e:
            logger.error(f"Strategy error: {e}")
        finally:
            self.is_running = False
    
    async def _subscribe_to_opportunities(self, websocket):
        """Subscribe to MEV opportunity feed"""
        subscribe_msg = {
            "type": "subscribe",
            "channel": "opportunities",
            "params": {
                "strategy": "arbitrage",
                "min_profit": self.min_profit_threshold
            }
        }
        await websocket.send(json.dumps(subscribe_msg))
        logger.info("Subscribed to opportunities feed")
    
    async def _subscribe_to_trades(self, websocket):
        """Subscribe to trade execution feed"""
        subscribe_msg = {
            "type": "subscribe",
            "channel": "trades"
        }
        await websocket.send(json.dumps(subscribe_msg))
        logger.info("Subscribed to trades feed")
    
    async def _subscribe_to_metrics(self, websocket):
        """Subscribe to real-time metrics"""
        subscribe_msg = {
            "type": "subscribe",
            "channel": "metrics",
            "params": {
                "interval": "5s"
            }
        }
        await websocket.send(json.dumps(subscribe_msg))
        logger.info("Subscribed to metrics feed")
    
    async def _process_message(self, message: Dict[str, Any]):
        """Process incoming WebSocket messages"""
        msg_type = message.get('type')
        channel = message.get('channel')
        data = message.get('data', {})
        
        if msg_type == 'opportunity' and channel == 'opportunities':
            await self._handle_opportunity(data)
        elif msg_type == 'trade_execution' and channel == 'trades':
            await self._handle_trade_execution(data)
        elif msg_type == 'metrics' and channel == 'metrics':
            await self._handle_metrics_update(data)
    
    async def _handle_opportunity(self, opportunity: Dict[str, Any]):
        """Handle new MEV opportunity"""
        # Analyze opportunity
        signal = self._analyze_opportunity(opportunity)
        
        if not signal:
            return
        
        # Check if we should execute
        if self._should_execute_trade(signal):
            await self._execute_opportunity(opportunity, signal)
    
    def _analyze_opportunity(self, opportunity: Dict[str, Any]) -> Optional[TradingSignal]:
        """Analyze MEV opportunity and generate trading signal"""
        expected_profit = opportunity.get('expected_profit_usd', 0)
        gas_cost = opportunity.get('gas_cost_usd', 0)
        net_profit = expected_profit - gas_cost
        
        # Skip if below profit threshold
        if net_profit < self.min_profit_threshold:
            return None
        
        # Calculate confidence based on multiple factors
        confidence = self._calculate_confidence(opportunity)
        
        # Calculate risk score
        risk_score = self._calculate_risk_score(opportunity)
        
        return TradingSignal(
            signal_type='opportunity',
            confidence=confidence,
            expected_profit=net_profit,
            risk_score=risk_score,
            metadata=opportunity
        )
    
    def _calculate_confidence(self, opportunity: Dict[str, Any]) -> float:
        """Calculate confidence score for opportunity"""
        base_confidence = 0.5
        
        # Adjust based on profit margin
        profit_margin = opportunity.get('expected_profit_usd', 0) / max(opportunity.get('size_usd', 1), 1)
        if profit_margin > 0.02:  # 2% profit margin
            base_confidence += 0.2
        
        # Adjust based on opportunity type
        strategy_type = opportunity.get('strategy_type')
        if strategy_type == 'arbitrage':
            base_confidence += 0.1  # Arbitrage is generally safer
        elif strategy_type == 'liquidation':
            base_confidence += 0.15  # Liquidations can be very profitable
        
        # Adjust based on confidence from the system
        system_confidence = opportunity.get('confidence', 0.5)
        base_confidence = (base_confidence + system_confidence) / 2
        
        return min(base_confidence, 1.0)
    
    def _calculate_risk_score(self, opportunity: Dict[str, Any]) -> float:
        """Calculate risk score for opportunity"""
        base_risk = 0.3
        
        # Adjust based on gas cost ratio
        gas_cost = opportunity.get('gas_cost_usd', 0)
        expected_profit = opportunity.get('expected_profit_usd', 0)
        if gas_cost > expected_profit * 0.5:  # High gas cost relative to profit
            base_risk += 0.2
        
        # Adjust based on opportunity size
        size_usd = opportunity.get('size_usd', 0)
        if size_usd > 100000:  # Large position
            base_risk += 0.1
        
        # Adjust based on chain
        chain_id = opportunity.get('chain_id', 1)
        if chain_id != 1:  # Non-Ethereum chains might have different risks
            base_risk += 0.05
        
        return min(base_risk, 1.0)
    
    def _should_execute_trade(self, signal: TradingSignal) -> bool:
        """Determine if trade should be executed based on signal"""
        # Check confidence threshold
        if signal.confidence < 0.7:
            return False
        
        # Check risk threshold
        if signal.risk_score > self.max_risk_score:
            return False
        
        # Check current positions and exposure
        positions = self.trading_client.get_current_positions()
        total_exposure = sum(p.get('size', 0) * p.get('current_price', 0) for p in positions)
        
        if total_exposure > 50000:  # Max total exposure
            return False
        
        return True
    
    async def _execute_opportunity(self, opportunity: Dict[str, Any], signal: TradingSignal):
        """Execute the MEV opportunity"""
        opportunity_id = opportunity.get('id')
        
        # Calculate position size based on signal confidence and risk
        base_size = 1.0 * self.position_size_multiplier
        adjusted_size = base_size * signal.confidence * (1 - signal.risk_score)
        
        execution_params = {
            'position_size': adjusted_size,
            'slippage_tolerance': 0.005,
            'gas_price_gwei': 25,
            'private_mempool': True
        }
        
        try:
            response = requests.post(
                f"{self.config.base_url}/opportunities/{opportunity_id}/execute",
                headers=self.jwt_manager.auth_headers,
                json=execution_params,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            
            result = response.json()
            logger.info(f"Executed opportunity {opportunity_id}: {result}")
            
        except Exception as e:
            logger.error(f"Failed to execute opportunity {opportunity_id}: {e}")
    
    async def _handle_trade_execution(self, trade_data: Dict[str, Any]):
        """Handle trade execution updates"""
        trade_id = trade_data.get('trade_id')
        status = trade_data.get('status')
        pnl = trade_data.get('pnl', 0)
        
        logger.info(f"Trade {trade_id} status: {status}, PnL: {pnl}")
        
        # Call registered handlers
        if 'trade_execution' in self.signal_handlers:
            self.signal_handlers['trade_execution'](trade_data)
    
    async def _handle_metrics_update(self, metrics_data: Dict[str, Any]):
        """Handle real-time metrics updates"""
        # Monitor for risk management
        session_pnl = metrics_data.get('session_pnl', 0)
        
        # Emergency stop if large losses
        if session_pnl < -5000:  # $5000 loss threshold
            logger.warning("Emergency stop triggered due to large losses")
            self.trading_client.stop_trading()
            self.is_running = False
    
    def stop_strategy(self):
        """Stop the trading strategy"""
        self.is_running = False
        logger.info("Strategy stopped")

# Usage example
async def main():
    config = MEVPlatformConfig()
    trading_client = TradingClient(config)
    strategy = AdvancedTradingStrategy(config, trading_client)
    
    # Register custom handlers
    def on_trade_execution(trade_data):
        print(f"Trade executed: {trade_data}")
    
    strategy.register_signal_handler('trade_execution', on_trade_execution)
    
    # Start trading with basic configuration
    trading_config = TradingConfig(
        mode=TradingMode.BALANCED,
        position_size_eth=2.0,
        strategies=[Strategy.ARBITRAGE],
        chains=[1, 42161]
    )
    
    trading_client.start_trading(trading_config)
    
    # Run advanced strategy
    await strategy.start_strategy()

if __name__ == "__main__":
    asyncio.run(main())
```

## Real-Time Data Integration

### WebSocket Client

```python
# realtime/websocket_client.py
import asyncio
import websockets
import json
import logging
from typing import Dict, Any, Callable, Optional, List
from dataclasses import dataclass, field
import time

logger = logging.getLogger(__name__)

@dataclass
class Subscription:
    channel: str
    params: Dict[str, Any] = field(default_factory=dict)
    handler: Optional[Callable] = None

class MEVWebSocketClient:
    """WebSocket client for real-time MEV data"""
    
    def __init__(self, config: MEVPlatformConfig):
        self.config = config
        self.jwt_manager = JWTManager(config)
        self.websocket: Optional[websockets.WebSocketServerProtocol] = None
        self.subscriptions: List[Subscription] = []
        self.is_connected = False
        self.reconnect_attempts = 0
        self.max_reconnect_attempts = 10
        self.heartbeat_interval = 30
        
    async def connect(self):
        """Connect to WebSocket server"""
        ws_url = f"wss://api.mev-platform.com/v1/ws"
        headers = self.jwt_manager.auth_headers
        
        try:
            self.websocket = await websockets.connect(
                ws_url,
                extra_headers=headers,
                ping_interval=self.heartbeat_interval,
                ping_timeout=10,
                close_timeout=10
            )
            
            self.is_connected = True
            self.reconnect_attempts = 0
            logger.info("Connected to MEV WebSocket")
            
            # Authenticate
            await self._authenticate()
            
            # Restore subscriptions
            await self._restore_subscriptions()
            
        except Exception as e:
            logger.error(f"WebSocket connection failed: {e}")
            raise
    
    async def disconnect(self):
        """Disconnect from WebSocket server"""
        if self.websocket:
            await self.websocket.close()
            self.is_connected = False
            logger.info("Disconnected from MEV WebSocket")
    
    async def _authenticate(self):
        """Authenticate WebSocket connection"""
        auth_msg = {
            "type": "auth",
            "token": self.jwt_manager.get_valid_token()
        }
        await self.websocket.send(json.dumps(auth_msg))
        
        # Wait for auth confirmation
        response = await asyncio.wait_for(self.websocket.recv(), timeout=10)
        auth_response = json.loads(response)
        
        if auth_response.get('type') != 'auth_success':
            raise Exception(f"Authentication failed: {auth_response}")
        
        logger.info("WebSocket authenticated successfully")
    
    async def subscribe(self, channel: str, params: Dict[str, Any] = None, handler: Callable = None):
        """Subscribe to a WebSocket channel"""
        subscription = Subscription(
            channel=channel,
            params=params or {},
            handler=handler
        )
        
        self.subscriptions.append(subscription)
        
        if self.is_connected:
            await self._send_subscription(subscription)
    
    async def _send_subscription(self, subscription: Subscription):
        """Send subscription message"""
        subscribe_msg = {
            "type": "subscribe",
            "channel": subscription.channel,
            "params": subscription.params
        }
        
        await self.websocket.send(json.dumps(subscribe_msg))
        logger.info(f"Subscribed to {subscription.channel}")
    
    async def _restore_subscriptions(self):
        """Restore all subscriptions after reconnection"""
        for subscription in self.subscriptions:
            await self._send_subscription(subscription)
    
    async def listen(self):
        """Listen for WebSocket messages"""
        try:
            async for message in self.websocket:
                await self._process_message(json.loads(message))
                
        except websockets.exceptions.ConnectionClosed:
            logger.warning("WebSocket connection closed")
            self.is_connected = False
            await self._handle_reconnection()
            
        except Exception as e:
            logger.error(f"WebSocket error: {e}")
            self.is_connected = False
    
    async def _process_message(self, message: Dict[str, Any]):
        """Process incoming WebSocket message"""
        msg_type = message.get('type')
        channel = message.get('channel')
        data = message.get('data', {})
        
        # Find matching subscription and call handler
        for subscription in self.subscriptions:
            if subscription.channel == channel and subscription.handler:
                try:
                    if asyncio.iscoroutinefunction(subscription.handler):
                        await subscription.handler(data)
                    else:
                        subscription.handler(data)
                except Exception as e:
                    logger.error(f"Handler error for {channel}: {e}")
    
    async def _handle_reconnection(self):
        """Handle WebSocket reconnection"""
        if self.reconnect_attempts >= self.max_reconnect_attempts:
            logger.error("Max reconnection attempts reached")
            return
        
        self.reconnect_attempts += 1
        wait_time = min(2 ** self.reconnect_attempts, 60)  # Exponential backoff
        
        logger.info(f"Reconnecting in {wait_time} seconds (attempt {self.reconnect_attempts})")
        await asyncio.sleep(wait_time)
        
        try:
            await self.connect()
            await self.listen()
        except Exception as e:
            logger.error(f"Reconnection failed: {e}")
            await self._handle_reconnection()
    
    async def run(self):
        """Run WebSocket client with automatic reconnection"""
        await self.connect()
        await self.listen()

# Usage example
async def opportunity_handler(data):
    """Handle new MEV opportunities"""
    profit = data.get('expected_profit_usd', 0)
    strategy = data.get('strategy_type', 'unknown')
    print(f"New {strategy} opportunity: ${profit:.2f} profit")

async def trade_handler(data):
    """Handle trade executions"""
    trade_id = data.get('trade_id')
    pnl = data.get('pnl', 0)
    print(f"Trade {trade_id} executed: ${pnl:.2f} PnL")

async def metrics_handler(data):
    """Handle real-time metrics"""
    latency = data.get('latency_ms', 0)
    throughput = data.get('throughput_tps', 0)
    print(f"System: {latency}ms latency, {throughput} TPS")

async def main():
    config = MEVPlatformConfig()
    client = MEVWebSocketClient(config)
    
    # Subscribe to channels with handlers
    await client.subscribe('opportunities', 
                          {'strategy': 'arbitrage', 'min_profit': 100}, 
                          opportunity_handler)
    
    await client.subscribe('trades', handler=trade_handler)
    
    await client.subscribe('metrics', 
                          {'interval': '5s'}, 
                          metrics_handler)
    
    # Run client
    await client.run()

if __name__ == "__main__":
    asyncio.run(main())
```

## Enterprise Integration Patterns

### Configuration Management

```python
# enterprise/config_manager.py
import json
import yaml
import os
from typing import Dict, Any, Optional
from dataclasses import dataclass, asdict
from pathlib import Path

@dataclass
class ChainConfig:
    enabled: bool
    priority: int
    gas_multiplier: float
    max_gas_price: float

@dataclass
class StrategyConfig:
    enabled: bool
    min_profit_usd: float
    max_position_size: float
    risk_multiplier: float = 1.0

@dataclass
class RiskConfig:
    max_total_exposure: float
    max_drawdown: float
    stop_loss: float
    position_timeout: int

@dataclass
class MEVConfig:
    chains: Dict[str, ChainConfig]
    strategies: Dict[str, StrategyConfig]
    risk_management: RiskConfig
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'MEVConfig':
        """Create config from dictionary"""
        chains = {
            name: ChainConfig(**chain_data) 
            for name, chain_data in data.get('chains', {}).items()
        }
        
        strategies = {
            name: StrategyConfig(**strategy_data)
            for name, strategy_data in data.get('strategies', {}).items()
        }
        
        risk_management = RiskConfig(**data.get('risk_management', {}))
        
        return cls(
            chains=chains,
            strategies=strategies,
            risk_management=risk_management
        )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert config to dictionary"""
        return {
            'chains': {name: asdict(config) for name, config in self.chains.items()},
            'strategies': {name: asdict(config) for name, config in self.strategies.items()},
            'risk_management': asdict(self.risk_management)
        }

class ConfigManager:
    """Manage MEV platform configuration"""
    
    def __init__(self, config_path: str = "config/mev_config.yaml"):
        self.config_path = Path(config_path)
        self.config: Optional[MEVConfig] = None
        self.load_config()
    
    def load_config(self) -> MEVConfig:
        """Load configuration from file"""
        if not self.config_path.exists():
            self.config = self._create_default_config()
            self.save_config()
        else:
            with open(self.config_path, 'r') as f:
                if self.config_path.suffix == '.yaml':
                    data = yaml.safe_load(f)
                else:
                    data = json.load(f)
            
            self.config = MEVConfig.from_dict(data)
        
        return self.config
    
    def save_config(self):
        """Save configuration to file"""
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(self.config_path, 'w') as f:
            if self.config_path.suffix == '.yaml':
                yaml.dump(self.config.to_dict(), f, default_flow_style=False)
            else:
                json.dump(self.config.to_dict(), f, indent=2)
    
    def _create_default_config(self) -> MEVConfig:
        """Create default configuration"""
        return MEVConfig(
            chains={
                'ethereum': ChainConfig(
                    enabled=True,
                    priority=1,
                    gas_multiplier=1.1,
                    max_gas_price=100
                ),
                'arbitrum': ChainConfig(
                    enabled=True,
                    priority=2,
                    gas_multiplier=1.05,
                    max_gas_price=5
                ),
                'optimism': ChainConfig(
                    enabled=True,
                    priority=3,
                    gas_multiplier=1.05,
                    max_gas_price=10
                )
            },
            strategies={
                'arbitrage': StrategyConfig(
                    enabled=True,
                    min_profit_usd=50,
                    max_position_size=10,
                    risk_multiplier=1.0
                ),
                'liquidation': StrategyConfig(
                    enabled=True,
                    min_profit_usd=100,
                    max_position_size=5,
                    risk_multiplier=1.2
                )
            },
            risk_management=RiskConfig(
                max_total_exposure=100000,
                max_drawdown=0.05,
                stop_loss=0.02,
                position_timeout=3600
            )
        )
    
    def update_strategy(self, strategy_name: str, **kwargs):
        """Update strategy configuration"""
        if strategy_name in self.config.strategies:
            strategy_config = self.config.strategies[strategy_name]
            for key, value in kwargs.items():
                if hasattr(strategy_config, key):
                    setattr(strategy_config, key, value)
            self.save_config()
    
    def update_risk_limits(self, **kwargs):
        """Update risk management configuration"""
        for key, value in kwargs.items():
            if hasattr(self.config.risk_management, key):
                setattr(self.config.risk_management, key, value)
        self.save_config()
    
    def get_active_strategies(self) -> List[str]:
        """Get list of enabled strategies"""
        return [
            name for name, config in self.config.strategies.items()
            if config.enabled
        ]
    
    def get_active_chains(self) -> List[str]:
        """Get list of enabled chains"""
        return [
            name for name, config in self.config.chains.items()
            if config.enabled
        ]

# Usage example
if __name__ == "__main__":
    config_manager = ConfigManager("config/production.yaml")
    
    # Update strategy parameters
    config_manager.update_strategy('arbitrage', min_profit_usd=75)
    
    # Update risk limits
    config_manager.update_risk_limits(max_drawdown=0.03)
    
    # Get active configurations
    active_strategies = config_manager.get_active_strategies()
    active_chains = config_manager.get_active_chains()
    
    print(f"Active strategies: {active_strategies}")
    print(f"Active chains: {active_chains}")
```

### Monitoring Integration

```python
# enterprise/monitoring_integration.py
import time
import requests
import logging
from typing import Dict, Any, List
from prometheus_client import start_http_server, Gauge, Counter, Histogram
import asyncio

logger = logging.getLogger(__name__)

class PrometheusExporter:
    """Export MEV metrics to Prometheus"""
    
    def __init__(self, config: MEVPlatformConfig, port: int = 8000):
        self.config = config
        self.jwt_manager = JWTManager(config)
        self.port = port
        
        # Define Prometheus metrics
        self.system_health = Gauge('mev_system_health_score', 'System health score (0-1)')
        self.api_latency = Histogram('mev_api_latency_seconds', 'API response latency')
        self.trading_pnl = Gauge('mev_trading_pnl_usd', 'Current trading PnL in USD')
        self.active_opportunities = Gauge('mev_active_opportunities', 'Number of active opportunities')
        self.trades_executed = Counter('mev_trades_executed_total', 'Total trades executed')
        self.error_count = Counter('mev_errors_total', 'Total error count', ['error_type'])
        
        # Chain-specific metrics
        self.chain_health = Gauge('mev_chain_health', 'Chain health status', ['chain'])
        self.chain_block_height = Gauge('mev_chain_block_height', 'Current block height', ['chain'])
        
        # Strategy metrics
        self.strategy_profit = Gauge('mev_strategy_profit_usd', 'Strategy profit', ['strategy'])
        self.strategy_success_rate = Gauge('mev_strategy_success_rate', 'Strategy success rate', ['strategy'])
    
    def start_exporter(self):
        """Start Prometheus HTTP server"""
        start_http_server(self.port)
        logger.info(f"Prometheus exporter started on port {self.port}")
    
    async def collect_metrics(self):
        """Continuously collect metrics from MEV platform"""
        while True:
            try:
                await self._update_system_metrics()
                await self._update_trading_metrics()
                await self._update_chain_metrics()
                await self._update_strategy_metrics()
                
                await asyncio.sleep(30)  # Update every 30 seconds
                
            except Exception as e:
                logger.error(f"Metrics collection error: {e}")
                self.error_count.labels(error_type='metrics_collection').inc()
                await asyncio.sleep(60)  # Wait longer on error
    
    async def _update_system_metrics(self):
        """Update system-level metrics"""
        try:
            response = requests.get(
                f"{self.config.base_url}/status",
                headers=self.jwt_manager.auth_headers,
                timeout=10
            )
            response.raise_for_status()
            
            data = response.json()
            
            # Extract health score
            health_score = 0.0
            if data.get('status') == 'healthy':
                health_score = 1.0
            elif data.get('status') == 'degraded':
                health_score = 0.5
            
            self.system_health.set(health_score)
            
        except Exception as e:
            logger.error(f"Failed to update system metrics: {e}")
            self.error_count.labels(error_type='system_metrics').inc()
    
    async def _update_trading_metrics(self):
        """Update trading-related metrics"""
        try:
            # Get trading status
            response = requests.get(
                f"{self.config.base_url}/trading/status",
                headers=self.jwt_manager.auth_headers,
                timeout=10
            )
            response.raise_for_status()
            
            data = response.json()
            
            self.trading_pnl.set(data.get('session_pnl', 0))
            
            # Get opportunities
            response = requests.get(
                f"{self.config.base_url}/opportunities",
                headers=self.jwt_manager.auth_headers,
                timeout=10
            )
            response.raise_for_status()
            
            opp_data = response.json()
            self.active_opportunities.set(opp_data.get('total_count', 0))
            
        except Exception as e:
            logger.error(f"Failed to update trading metrics: {e}")
            self.error_count.labels(error_type='trading_metrics').inc()
    
    async def _update_chain_metrics(self):
        """Update blockchain-specific metrics"""
        try:
            response = requests.get(
                f"{self.config.base_url}/status",
                headers=self.jwt_manager.auth_headers,
                timeout=10
            )
            response.raise_for_status()
            
            data = response.json()
            blockchain_nodes = data.get('components', {}).get('blockchain_nodes', {})
            
            for chain_name, chain_data in blockchain_nodes.items():
                # Set health status (1 for synced, 0.5 for syncing, 0 for error)
                health_value = 1.0 if chain_data.get('status') == 'synced' else 0.0
                self.chain_health.labels(chain=chain_name).set(health_value)
                
                # Set block height
                block_height = chain_data.get('block_height', 0)
                self.chain_block_height.labels(chain=chain_name).set(block_height)
                
        except Exception as e:
            logger.error(f"Failed to update chain metrics: {e}")
            self.error_count.labels(error_type='chain_metrics').inc()
    
    async def _update_strategy_metrics(self):
        """Update strategy-specific metrics"""
        try:
            # Get trade history for recent performance
            response = requests.get(
                f"{self.config.base_url}/trades",
                headers=self.jwt_manager.auth_headers,
                params={'limit': 100},
                timeout=10
            )
            response.raise_for_status()
            
            data = response.json()
            trades = data.get('trades', [])
            
            # Calculate metrics by strategy
            strategy_stats = {}
            for trade in trades:
                strategy = trade.get('strategy', 'unknown')
                if strategy not in strategy_stats:
                    strategy_stats[strategy] = {'profit': 0, 'count': 0, 'successful': 0}
                
                strategy_stats[strategy]['profit'] += trade.get('realized_pnl', 0)
                strategy_stats[strategy]['count'] += 1
                if trade.get('realized_pnl', 0) > 0:
                    strategy_stats[strategy]['successful'] += 1
            
            # Update Prometheus metrics
            for strategy, stats in strategy_stats.items():
                self.strategy_profit.labels(strategy=strategy).set(stats['profit'])
                
                success_rate = stats['successful'] / max(stats['count'], 1)
                self.strategy_success_rate.labels(strategy=strategy).set(success_rate)
                
        except Exception as e:
            logger.error(f"Failed to update strategy metrics: {e}")
            self.error_count.labels(error_type='strategy_metrics').inc()

# Usage example
async def main():
    config = MEVPlatformConfig()
    exporter = PrometheusExporter(config, port=8000)
    
    # Start Prometheus HTTP server
    exporter.start_exporter()
    
    # Start collecting metrics
    await exporter.collect_metrics()

if __name__ == "__main__":
    asyncio.run(main())
```

---

*These integration examples provide a comprehensive foundation for connecting with the MEV Infrastructure Platform. For additional examples and advanced use cases, consult the API Reference documentation or contact technical support.*