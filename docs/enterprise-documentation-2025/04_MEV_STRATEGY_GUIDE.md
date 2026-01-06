# MEV Strategy Guide - Advanced Execution Strategies & Best Practices
**Version 3.6.5 | July 2025**

## Table of Contents
1. [MEV Strategy Framework](#mev-strategy-framework)
2. [Strategy Selection Matrix](#strategy-selection-matrix)
3. [Risk Management Protocols](#risk-management-protocols)
4. [Profit Optimization Techniques](#profit-optimization-techniques)
5. [Multi-Chain Coordination](#multi-chain-coordination)
6. [Flash Loan Integration](#flash-loan-integration)
7. [Bundle Optimization Strategies](#bundle-optimization-strategies)

---

## MEV Strategy Framework

### Core MEV Strategies Overview

| Strategy | Complexity | Risk Level | Profit Potential | Capital Required |
|----------|------------|------------|------------------|------------------|
| Arbitrage | Medium | Low | Medium | Low-Medium |
| Sandwich | High | Medium | High | Low |
| Liquidation | High | Medium | Very High | Medium-High |
| Flash Loan Arbitrage | Very High | High | Very High | None (borrowed) |
| Cross-Chain Arbitrage | Very High | High | High | Medium |
| JIT Liquidity | High | Medium | Medium | High |
| Block Space Auction | Low | Low | Low-Medium | Low |

### Strategy Implementation Architecture

```
┌─────────────────────────────────────────────────────┐
│                  MEV Strategy Engine                 │
├─────────────────────────────────────────────────────┤
│  Opportunity Detection │ Strategy Selection │ Risk   │
│  ├─ Mempool Monitor   │ ├─ Profit Calculator│ Mgmt  │
│  ├─ Block Monitor     │ ├─ Gas Optimizer    │       │
│  └─ Event Listener    │ └─ Route Finder     │       │
├─────────────────────────────────────────────────────┤
│           Execution Layer (OCaml + Rust)            │
│  ├─ Transaction Builder                             │
│  ├─ Bundle Constructor                              │
│  └─ Flashbots Integration                          │
└─────────────────────────────────────────────────────┘
```

---

## Strategy Selection Matrix

### Dynamic Strategy Selection Algorithm

```python
# Strategy selection framework
cat > /data/blockchain/nodes/mev/strategy_selector.py << 'EOF'
#!/usr/bin/env python3
from typing import Dict, List, Optional
from dataclasses import dataclass
from enum import Enum
import json

class StrategyType(Enum):
    ARBITRAGE = "arbitrage"
    SANDWICH = "sandwich"
    LIQUIDATION = "liquidation"
    FLASH_LOAN = "flash_loan"
    CROSS_CHAIN = "cross_chain"
    JIT_LIQUIDITY = "jit_liquidity"

@dataclass
class MarketCondition:
    gas_price_gwei: float
    block_base_fee: float
    mempool_congestion: float  # 0-1 scale
    volatility_index: float    # 0-100 scale
    available_capital_eth: float
    chain_id: int

@dataclass
class OpportunityParams:
    opportunity_type: str
    profit_estimate_eth: float
    gas_cost_estimate_eth: float
    execution_complexity: int  # 1-10 scale
    time_sensitivity: int      # seconds
    required_capital_eth: float
    success_probability: float # 0-1 scale

class StrategySelector:
    def __init__(self):
        self.strategy_configs = {
            StrategyType.ARBITRAGE: {
                "min_profit_eth": 0.01,
                "max_gas_multiplier": 1.5,
                "complexity_threshold": 5,
                "min_success_prob": 0.8
            },
            StrategyType.SANDWICH: {
                "min_profit_eth": 0.02,
                "max_gas_multiplier": 2.0,
                "complexity_threshold": 7,
                "min_success_prob": 0.7,
                "max_volatility": 60
            },
            StrategyType.LIQUIDATION: {
                "min_profit_eth": 0.05,
                "max_gas_multiplier": 3.0,
                "complexity_threshold": 8,
                "min_success_prob": 0.6,
                "min_capital_eth": 1.0
            },
            StrategyType.FLASH_LOAN: {
                "min_profit_eth": 0.1,
                "max_gas_multiplier": 2.5,
                "complexity_threshold": 9,
                "min_success_prob": 0.7,
                "flash_loan_fee": 0.0009  # 0.09%
            },
            StrategyType.CROSS_CHAIN: {
                "min_profit_eth": 0.15,
                "max_gas_multiplier": 2.0,
                "complexity_threshold": 10,
                "min_success_prob": 0.6,
                "bridge_time_seconds": 300
            }
        }
    
    def select_strategy(
        self, 
        opportunity: OpportunityParams, 
        market: MarketCondition
    ) -> Optional[StrategyType]:
        """Select optimal strategy based on opportunity and market conditions"""
        
        viable_strategies = []
        
        for strategy_type, config in self.strategy_configs.items():
            if self._is_strategy_viable(strategy_type, config, opportunity, market):
                score = self._calculate_strategy_score(
                    strategy_type, config, opportunity, market
                )
                viable_strategies.append((strategy_type, score))
        
        if not viable_strategies:
            return None
        
        # Sort by score and return best strategy
        viable_strategies.sort(key=lambda x: x[1], reverse=True)
        return viable_strategies[0][0]
    
    def _is_strategy_viable(
        self,
        strategy_type: StrategyType,
        config: Dict,
        opportunity: OpportunityParams,
        market: MarketCondition
    ) -> bool:
        """Check if strategy meets minimum viability criteria"""
        
        # Profit threshold
        if opportunity.profit_estimate_eth < config["min_profit_eth"]:
            return False
        
        # Gas cost check
        max_gas_cost = opportunity.profit_estimate_eth * 0.5  # Max 50% of profit for gas
        if opportunity.gas_cost_estimate_eth > max_gas_cost:
            return False
        
        # Complexity check
        if opportunity.execution_complexity > config["complexity_threshold"]:
            return False
        
        # Success probability
        if opportunity.success_probability < config["min_success_prob"]:
            return False
        
        # Strategy-specific checks
        if strategy_type == StrategyType.SANDWICH:
            if market.volatility_index > config.get("max_volatility", 100):
                return False
        
        elif strategy_type == StrategyType.LIQUIDATION:
            if market.available_capital_eth < config.get("min_capital_eth", 0):
                return False
        
        elif strategy_type == StrategyType.CROSS_CHAIN:
            if opportunity.time_sensitivity < config.get("bridge_time_seconds", 0):
                return False
        
        return True
    
    def _calculate_strategy_score(
        self,
        strategy_type: StrategyType,
        config: Dict,
        opportunity: OpportunityParams,
        market: MarketCondition
    ) -> float:
        """Calculate strategy score for ranking"""
        
        # Base score from profit
        score = opportunity.profit_estimate_eth * 100
        
        # Adjust for success probability
        score *= opportunity.success_probability
        
        # Penalize for gas costs
        gas_ratio = opportunity.gas_cost_estimate_eth / opportunity.profit_estimate_eth
        score *= (1 - gas_ratio)
        
        # Adjust for market conditions
        if market.mempool_congestion > 0.8:
            score *= 0.8  # Reduce score in congested conditions
        
        if market.volatility_index > 70:
            if strategy_type in [StrategyType.ARBITRAGE, StrategyType.LIQUIDATION]:
                score *= 1.2  # Boost for volatility-friendly strategies
            else:
                score *= 0.9
        
        # Strategy-specific adjustments
        if strategy_type == StrategyType.FLASH_LOAN:
            # Boost score as no capital required
            score *= 1.3
        
        elif strategy_type == StrategyType.CROSS_CHAIN:
            # Penalize for bridge risk
            score *= 0.85
        
        return score
    
    def get_execution_params(
        self, 
        strategy_type: StrategyType,
        opportunity: OpportunityParams,
        market: MarketCondition
    ) -> Dict:
        """Get execution parameters for selected strategy"""
        
        config = self.strategy_configs[strategy_type]
        
        # Calculate dynamic gas price
        base_gas = market.block_base_fee
        if opportunity.time_sensitivity < 15:  # Very time sensitive
            gas_multiplier = min(config["max_gas_multiplier"], 2.5)
        elif opportunity.time_sensitivity < 60:
            gas_multiplier = min(config["max_gas_multiplier"], 1.8)
        else:
            gas_multiplier = 1.2
        
        max_gas_price = base_gas * gas_multiplier
        
        # Calculate slippage tolerance
        if market.volatility_index > 50:
            slippage_tolerance = 0.02  # 2%
        else:
            slippage_tolerance = 0.01  # 1%
        
        return {
            "strategy_type": strategy_type.value,
            "max_gas_price_gwei": max_gas_price,
            "slippage_tolerance": slippage_tolerance,
            "execution_deadline": opportunity.time_sensitivity,
            "min_profit_threshold_eth": config["min_profit_eth"],
            "retry_attempts": 3 if opportunity.success_probability > 0.8 else 1,
            "use_flashbots": True if strategy_type == StrategyType.SANDWICH else False,
            "bundle_priority": self._calculate_bundle_priority(
                opportunity.profit_estimate_eth, 
                opportunity.time_sensitivity
            )
        }
    
    def _calculate_bundle_priority(self, profit_eth: float, time_sensitivity: int) -> int:
        """Calculate bundle priority (0-100)"""
        profit_score = min(profit_eth * 100, 50)  # Max 50 points from profit
        time_score = max(0, 50 - time_sensitivity)  # Max 50 points from urgency
        return int(profit_score + time_score)

# Example usage
def select_mev_strategy(opportunity_data: dict, market_data: dict) -> dict:
    selector = StrategySelector()
    
    opportunity = OpportunityParams(**opportunity_data)
    market = MarketCondition(**market_data)
    
    selected_strategy = selector.select_strategy(opportunity, market)
    
    if selected_strategy:
        execution_params = selector.get_execution_params(
            selected_strategy, opportunity, market
        )
        return {
            "strategy": selected_strategy.value,
            "execution_params": execution_params,
            "estimated_profit": opportunity.profit_estimate_eth,
            "success_probability": opportunity.success_probability
        }
    else:
        return {"strategy": None, "reason": "No viable strategy found"}
EOF
```

### Strategy Performance Tracking

```python
# Strategy performance tracker
cat > /data/blockchain/nodes/mev/strategy_performance_tracker.py << 'EOF'
#!/usr/bin/env python3
import sqlite3
from datetime import datetime, timedelta
import json
from typing import Dict, List

class StrategyPerformanceTracker:
    def __init__(self):
        self.db_path = "/data/blockchain/nodes/mev/strategy_performance.db"
        self.init_database()
    
    def init_database(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS strategy_executions (
                execution_id TEXT PRIMARY KEY,
                timestamp TIMESTAMP,
                strategy_type TEXT,
                chain_id INTEGER,
                estimated_profit_eth REAL,
                actual_profit_eth REAL,
                gas_cost_eth REAL,
                execution_time_ms INTEGER,
                success BOOLEAN,
                failure_reason TEXT,
                market_conditions TEXT,
                execution_params TEXT
            )
        ''')
        conn.execute('''
            CREATE TABLE IF NOT EXISTS strategy_metrics (
                strategy_type TEXT,
                period TEXT,
                timestamp TIMESTAMP,
                total_executions INTEGER,
                successful_executions INTEGER,
                total_profit_eth REAL,
                average_profit_eth REAL,
                success_rate REAL,
                average_execution_time_ms REAL,
                roi REAL,
                PRIMARY KEY (strategy_type, period, timestamp)
            )
        ''')
        conn.commit()
        conn.close()
    
    def record_execution(self, execution_data: Dict):
        """Record strategy execution result"""
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            INSERT INTO strategy_executions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            execution_data['execution_id'],
            datetime.now(),
            execution_data['strategy_type'],
            execution_data['chain_id'],
            execution_data['estimated_profit_eth'],
            execution_data['actual_profit_eth'],
            execution_data['gas_cost_eth'],
            execution_data['execution_time_ms'],
            execution_data['success'],
            execution_data.get('failure_reason'),
            json.dumps(execution_data.get('market_conditions', {})),
            json.dumps(execution_data.get('execution_params', {}))
        ))
        conn.commit()
        conn.close()
    
    def calculate_strategy_metrics(self, period: str = "1h"):
        """Calculate performance metrics for each strategy"""
        conn = sqlite3.connect(self.db_path)
        
        # Determine time window
        if period == "1h":
            window = datetime.now() - timedelta(hours=1)
        elif period == "24h":
            window = datetime.now() - timedelta(days=1)
        elif period == "7d":
            window = datetime.now() - timedelta(days=7)
        else:
            window = datetime.now() - timedelta(hours=1)
        
        # Get all strategy types
        cursor = conn.execute("SELECT DISTINCT strategy_type FROM strategy_executions")
        strategies = [row[0] for row in cursor.fetchall()]
        
        metrics = {}
        for strategy in strategies:
            cursor = conn.execute('''
                SELECT 
                    COUNT(*) as total_executions,
                    SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successful_executions,
                    SUM(CASE WHEN success = 1 THEN actual_profit_eth ELSE 0 END) as total_profit,
                    AVG(CASE WHEN success = 1 THEN actual_profit_eth ELSE NULL END) as avg_profit,
                    AVG(execution_time_ms) as avg_execution_time,
                    SUM(gas_cost_eth) as total_gas_cost
                FROM strategy_executions
                WHERE strategy_type = ? AND timestamp > ?
            ''', (strategy, window))
            
            row = cursor.fetchone()
            if row[0] > 0:  # Has executions
                success_rate = row[1] / row[0] if row[0] > 0 else 0
                roi = (row[2] / row[5]) if row[5] > 0 else 0
                
                metrics[strategy] = {
                    'total_executions': row[0],
                    'successful_executions': row[1],
                    'total_profit_eth': row[2] or 0,
                    'average_profit_eth': row[3] or 0,
                    'success_rate': success_rate,
                    'average_execution_time_ms': row[4] or 0,
                    'roi': roi
                }
                
                # Store metrics
                conn.execute('''
                    INSERT OR REPLACE INTO strategy_metrics VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    strategy, period, datetime.now(),
                    row[0], row[1], row[2] or 0, row[3] or 0,
                    success_rate, row[4] or 0, roi
                ))
        
        conn.commit()
        conn.close()
        return metrics
    
    def get_best_performing_strategies(self, period: str = "24h", top_n: int = 3) -> List[Dict]:
        """Get best performing strategies by profit"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.execute('''
            SELECT 
                strategy_type,
                total_profit_eth,
                success_rate,
                average_profit_eth,
                roi
            FROM strategy_metrics
            WHERE period = ? AND timestamp > datetime('now', '-1 hour')
            ORDER BY total_profit_eth DESC
            LIMIT ?
        ''', (period, top_n))
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'strategy': row[0],
                'total_profit_eth': row[1],
                'success_rate': row[2],
                'average_profit_eth': row[3],
                'roi': row[4]
            })
        
        conn.close()
        return results
EOF
```

---

## Risk Management Protocols

### Comprehensive Risk Framework

```yaml
# Risk management configuration
risk_management:
  position_limits:
    max_position_size_eth: 10.0
    max_positions_per_strategy: 5
    max_total_exposure_eth: 50.0
  
  loss_limits:
    max_loss_per_transaction_eth: 0.5
    max_daily_loss_eth: 2.0
    max_weekly_loss_eth: 5.0
    circuit_breaker_threshold_eth: 1.0
  
  gas_limits:
    max_gas_price_gwei: 500
    max_gas_per_transaction: 3000000
    gas_price_multiplier_cap: 3.0
  
  execution_limits:
    max_slippage_percent: 3.0
    max_execution_time_seconds: 30
    max_retry_attempts: 3
    cooldown_after_failure_seconds: 60
  
  strategy_specific:
    sandwich:
      max_victim_gas_price_gwei: 200
      min_profit_after_gas_eth: 0.02
      max_position_blocks: 2
    
    liquidation:
      min_collateral_ratio: 1.1
      max_liquidation_penalty: 0.15
      safety_buffer: 0.05
    
    flash_loan:
      approved_providers: ["aave", "dydx", "uniswap"]
      max_loan_amount_eth: 1000
      max_loan_fee_percent: 0.1
```

### Risk Monitoring System

```python
# Real-time risk monitor
cat > /data/blockchain/nodes/mev/risk_monitor.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import json
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import sqlite3

class RiskMonitor:
    def __init__(self, config_path: str):
        with open(config_path, 'r') as f:
            self.config = json.load(f)
        
        self.db_path = "/data/blockchain/nodes/mev/risk_events.db"
        self.init_database()
        self.active_positions = {}
        self.daily_losses = 0
        self.circuit_breaker_active = False
    
    def init_database(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS risk_events (
                timestamp TIMESTAMP,
                event_type TEXT,
                severity TEXT,
                strategy TEXT,
                details TEXT,
                action_taken TEXT
            )
        ''')
        conn.commit()
        conn.close()
    
    async def check_position_limits(self, strategy: str, position_size_eth: float) -> Dict:
        """Check if position size is within limits"""
        limits = self.config['position_limits']
        strategy_positions = sum(1 for s, _ in self.active_positions.values() if s == strategy)
        total_exposure = sum(size for _, size in self.active_positions.values())
        
        checks = {
            'position_size_ok': position_size_eth <= limits['max_position_size_eth'],
            'strategy_count_ok': strategy_positions < limits['max_positions_per_strategy'],
            'total_exposure_ok': total_exposure + position_size_eth <= limits['max_total_exposure_eth'],
            'circuit_breaker_ok': not self.circuit_breaker_active
        }
        
        all_ok = all(checks.values())
        
        if not all_ok:
            self.log_risk_event(
                event_type='position_limit_exceeded',
                severity='HIGH',
                strategy=strategy,
                details=json.dumps(checks)
            )
        
        return {
            'approved': all_ok,
            'checks': checks,
            'current_exposure': total_exposure,
            'strategy_positions': strategy_positions
        }
    
    async def check_gas_limits(self, gas_price_gwei: float, gas_estimate: int) -> Dict:
        """Check if gas parameters are within acceptable limits"""
        limits = self.config['gas_limits']
        
        checks = {
            'gas_price_ok': gas_price_gwei <= limits['max_gas_price_gwei'],
            'gas_amount_ok': gas_estimate <= limits['max_gas_per_transaction'],
            'total_cost_ok': (gas_price_gwei * gas_estimate / 1e9) < 0.1  # Max 0.1 ETH for gas
        }
        
        all_ok = all(checks.values())
        
        if not all_ok:
            self.log_risk_event(
                event_type='gas_limit_exceeded',
                severity='MEDIUM',
                strategy='N/A',
                details=json.dumps({
                    'gas_price_gwei': gas_price_gwei,
                    'gas_estimate': gas_estimate,
                    'checks': checks
                })
            )
        
        return {
            'approved': all_ok,
            'checks': checks,
            'estimated_gas_cost_eth': gas_price_gwei * gas_estimate / 1e9
        }
    
    async def record_execution_result(
        self, 
        execution_id: str,
        strategy: str,
        profit_eth: float,
        success: bool
    ):
        """Record execution result and update risk metrics"""
        if execution_id in self.active_positions:
            del self.active_positions[execution_id]
        
        if not success or profit_eth < 0:
            self.daily_losses += abs(profit_eth)
            
            # Check circuit breaker
            if self.daily_losses >= self.config['loss_limits']['circuit_breaker_threshold_eth']:
                self.circuit_breaker_active = True
                self.log_risk_event(
                    event_type='circuit_breaker_triggered',
                    severity='CRITICAL',
                    strategy=strategy,
                    details=json.dumps({
                        'daily_losses': self.daily_losses,
                        'threshold': self.config['loss_limits']['circuit_breaker_threshold_eth']
                    }),
                    action_taken='All trading halted'
                )
        
        # Check daily loss limit
        if self.daily_losses >= self.config['loss_limits']['max_daily_loss_eth']:
            self.log_risk_event(
                event_type='daily_loss_limit_exceeded',
                severity='CRITICAL',
                strategy=strategy,
                details=json.dumps({'daily_losses': self.daily_losses})
            )
    
    def log_risk_event(
        self, 
        event_type: str,
        severity: str,
        strategy: str,
        details: str,
        action_taken: str = None
    ):
        """Log risk event to database"""
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            INSERT INTO risk_events VALUES (?, ?, ?, ?, ?, ?)
        ''', (datetime.now(), event_type, severity, strategy, details, action_taken))
        conn.commit()
        conn.close()
    
    async def get_risk_status(self) -> Dict:
        """Get current risk status"""
        return {
            'circuit_breaker_active': self.circuit_breaker_active,
            'daily_losses_eth': self.daily_losses,
            'active_positions': len(self.active_positions),
            'total_exposure_eth': sum(size for _, size in self.active_positions.values()),
            'risk_score': self._calculate_risk_score()
        }
    
    def _calculate_risk_score(self) -> float:
        """Calculate overall risk score (0-100)"""
        score = 0
        
        # Loss ratio
        loss_ratio = self.daily_losses / self.config['loss_limits']['max_daily_loss_eth']
        score += loss_ratio * 40
        
        # Position concentration
        total_exposure = sum(size for _, size in self.active_positions.values())
        exposure_ratio = total_exposure / self.config['position_limits']['max_total_exposure_eth']
        score += exposure_ratio * 30
        
        # Active positions
        position_ratio = len(self.active_positions) / 10  # Assume 10 is high
        score += position_ratio * 30
        
        return min(100, score)
    
    async def reset_daily_counters(self):
        """Reset daily counters (run at UTC midnight)"""
        self.daily_losses = 0
        self.circuit_breaker_active = False
        self.log_risk_event(
            event_type='daily_reset',
            severity='INFO',
            strategy='system',
            details='Daily risk counters reset'
        )

# Risk validation middleware
async def validate_mev_execution(risk_monitor: RiskMonitor, execution_params: Dict) -> Dict:
    """Validate execution against risk limits"""
    # Check position limits
    position_check = await risk_monitor.check_position_limits(
        execution_params['strategy'],
        execution_params['position_size_eth']
    )
    
    if not position_check['approved']:
        return {
            'approved': False,
            'reason': 'Position limits exceeded',
            'details': position_check
        }
    
    # Check gas limits
    gas_check = await risk_monitor.check_gas_limits(
        execution_params['gas_price_gwei'],
        execution_params['gas_estimate']
    )
    
    if not gas_check['approved']:
        return {
            'approved': False,
            'reason': 'Gas limits exceeded',
            'details': gas_check
        }
    
    # Additional strategy-specific checks
    if execution_params['strategy'] == 'sandwich':
        if execution_params.get('victim_gas_price', 0) > 200:
            return {
                'approved': False,
                'reason': 'Victim gas price too high for sandwich'
            }
    
    return {
        'approved': True,
        'risk_checks': {
            'position': position_check,
            'gas': gas_check
        }
    }
EOF
```

---

## Profit Optimization Techniques

### Advanced Profit Optimization Engine

```python
# Profit optimizer
cat > /data/blockchain/nodes/mev/profit_optimizer.py << 'EOF'
#!/usr/bin/env python3
import numpy as np
from typing import Dict, List, Tuple, Optional
import json
from scipy.optimize import minimize

class ProfitOptimizer:
    def __init__(self):
        self.gas_price_history = []
        self.profit_history = []
        self.optimization_params = {
            'learning_rate': 0.1,
            'decay_factor': 0.95,
            'exploration_rate': 0.1
        }
    
    def optimize_gas_bidding(
        self, 
        base_fee: float,
        priority_fees: List[float],
        opportunity_value: float,
        time_sensitivity: float
    ) -> float:
        """Optimize gas bidding strategy using dynamic programming"""
        
        # Calculate optimal priority fee
        if len(priority_fees) < 10:
            # Not enough data, use simple heuristic
            return base_fee + (opportunity_value * 0.1)
        
        # Statistical analysis of recent priority fees
        p25 = np.percentile(priority_fees, 25)
        p50 = np.percentile(priority_fees, 50)
        p75 = np.percentile(priority_fees, 75)
        p90 = np.percentile(priority_fees, 90)
        
        # Time sensitivity factor
        if time_sensitivity < 5:  # Very urgent
            target_percentile = p90
        elif time_sensitivity < 15:  # Urgent
            target_percentile = p75
        elif time_sensitivity < 60:  # Normal
            target_percentile = p50
        else:  # Not urgent
            target_percentile = p25
        
        # Profit-adjusted bidding
        profit_ratio = min(opportunity_value / 0.1, 3.0)  # Cap at 3x
        optimal_priority = target_percentile * profit_ratio
        
        # Total gas price
        optimal_gas_price = base_fee + optimal_priority
        
        # Safety check: don't exceed 50% of opportunity value
        max_gas_wei = opportunity_value * 0.5 * 1e18
        max_gas_price = max_gas_wei / 300000  # Assume 300k gas
        
        return min(optimal_gas_price, max_gas_price)
    
    def optimize_route_path(
        self,
        token_in: str,
        token_out: str,
        amount_in: float,
        dex_liquidity: Dict[str, Dict]
    ) -> Tuple[List[str], float]:
        """Optimize trading route for maximum output"""
        
        # Build graph of possible paths
        paths = self._find_all_paths(token_in, token_out, dex_liquidity)
        
        best_path = None
        best_output = 0
        
        for path in paths:
            output = self._calculate_path_output(amount_in, path, dex_liquidity)
            if output > best_output:
                best_output = output
                best_path = path
        
        # Check for split routing opportunities
        if len(paths) > 1:
            split_output = self._optimize_split_routing(
                amount_in, paths[:3], dex_liquidity  # Top 3 paths
            )
            if split_output['total_output'] > best_output * 1.01:  # 1% improvement threshold
                return split_output['routes'], split_output['total_output']
        
        return best_path, best_output
    
    def _find_all_paths(
        self,
        start: str,
        end: str,
        liquidity: Dict,
        max_hops: int = 3
    ) -> List[List[str]]:
        """Find all possible trading paths"""
        paths = []
        
        def dfs(current: str, target: str, path: List[str], visited: set):
            if len(path) > max_hops:
                return
            
            if current == target:
                paths.append(path.copy())
                return
            
            for dex, pairs in liquidity.items():
                for pair in pairs:
                    if current in pair:
                        next_token = pair[0] if pair[1] == current else pair[1]
                        if next_token not in visited:
                            visited.add(next_token)
                            path.append(f"{dex}:{current}->{next_token}")
                            dfs(next_token, target, path, visited)
                            path.pop()
                            visited.remove(next_token)
        
        dfs(start, end, [], {start})
        return paths
    
    def _calculate_path_output(
        self,
        amount_in: float,
        path: List[str],
        liquidity: Dict
    ) -> float:
        """Calculate output for a specific path"""
        current_amount = amount_in
        
        for hop in path:
            dex, pair = hop.split(':')
            token_in, token_out = pair.split('->')
            
            # Get liquidity for this hop
            reserve_in = liquidity[dex][pair]['reserve_in']
            reserve_out = liquidity[dex][pair]['reserve_out']
            fee = liquidity[dex].get('fee', 0.003)  # 0.3% default
            
            # Calculate output using constant product formula
            amount_in_with_fee = current_amount * (1 - fee)
            numerator = amount_in_with_fee * reserve_out
            denominator = reserve_in + amount_in_with_fee
            amount_out = numerator / denominator
            
            current_amount = amount_out
        
        return current_amount
    
    def _optimize_split_routing(
        self,
        total_amount: float,
        paths: List[List[str]],
        liquidity: Dict
    ) -> Dict:
        """Optimize split routing across multiple paths"""
        
        def objective(splits):
            # Ensure splits sum to 1
            normalized_splits = splits / splits.sum()
            total_output = 0
            
            for i, path in enumerate(paths):
                if normalized_splits[i] > 0:
                    amount = total_amount * normalized_splits[i]
                    output = self._calculate_path_output(amount, path, liquidity)
                    total_output += output
            
            return -total_output  # Negative for minimization
        
        # Initial guess: equal split
        initial_splits = np.ones(len(paths)) / len(paths)
        
        # Constraints: splits must be non-negative and sum to 1
        constraints = {'type': 'eq', 'fun': lambda x: x.sum() - 1}
        bounds = [(0, 1) for _ in paths]
        
        result = minimize(
            objective,
            initial_splits,
            method='SLSQP',
            bounds=bounds,
            constraints=constraints
        )
        
        optimal_splits = result.x / result.x.sum()
        
        routes = []
        for i, (path, split) in enumerate(zip(paths, optimal_splits)):
            if split > 0.01:  # Only include if more than 1%
                routes.append({
                    'path': path,
                    'amount': total_amount * split,
                    'percentage': split * 100
                })
        
        return {
            'routes': routes,
            'total_output': -result.fun
        }
    
    def calculate_optimal_bundle_size(
        self,
        opportunities: List[Dict],
        gas_price: float,
        block_space_limit: int = 30000000
    ) -> List[Dict]:
        """Calculate optimal bundle size and composition"""
        
        # Sort opportunities by profit per gas
        for opp in opportunities:
            opp['profit_per_gas'] = opp['estimated_profit'] / opp['gas_estimate']
        
        opportunities.sort(key=lambda x: x['profit_per_gas'], reverse=True)
        
        bundle = []
        total_gas = 0
        total_profit = 0
        
        for opp in opportunities:
            if total_gas + opp['gas_estimate'] <= block_space_limit * 0.3:  # Max 30% of block
                # Check if profitable after gas
                gas_cost = opp['gas_estimate'] * gas_price / 1e9
                net_profit = opp['estimated_profit'] - gas_cost
                
                if net_profit > 0.001:  # Min 0.001 ETH profit
                    bundle.append(opp)
                    total_gas += opp['gas_estimate']
                    total_profit += net_profit
        
        return {
            'bundle': bundle,
            'total_gas': total_gas,
            'total_profit': total_profit,
            'bundle_efficiency': total_profit / (total_gas / 1e6) if total_gas > 0 else 0
        }

# Profit tracking and analysis
class ProfitAnalyzer:
    def __init__(self):
        self.db_path = "/data/blockchain/nodes/mev/profit_analysis.db"
        self.init_database()
    
    def init_database(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS profit_analysis (
                timestamp TIMESTAMP,
                strategy TEXT,
                gross_profit_eth REAL,
                gas_cost_eth REAL,
                net_profit_eth REAL,
                roi REAL,
                opportunity_source TEXT,
                optimization_score REAL
            )
        ''')
        conn.commit()
        conn.close()
    
    def analyze_profit_factors(self, time_period: str = "24h") -> Dict:
        """Analyze factors contributing to profit"""
        conn = sqlite3.connect(self.db_path)
        
        # Profit by strategy
        strategy_profits = {}
        cursor = conn.execute('''
            SELECT strategy, 
                   SUM(net_profit_eth) as total_profit,
                   AVG(roi) as avg_roi,
                   COUNT(*) as count
            FROM profit_analysis
            WHERE timestamp > datetime('now', ?)
            GROUP BY strategy
            ORDER BY total_profit DESC
        ''', (f'-{time_period}',))
        
        for row in cursor.fetchall():
            strategy_profits[row[0]] = {
                'total_profit': row[1],
                'avg_roi': row[2],
                'execution_count': row[3]
            }
        
        # Profit by time of day
        hourly_profits = {}
        cursor = conn.execute('''
            SELECT strftime('%H', timestamp) as hour,
                   AVG(net_profit_eth) as avg_profit
            FROM profit_analysis
            WHERE timestamp > datetime('now', ?)
            GROUP BY hour
            ORDER BY hour
        ''', (f'-{time_period}',))
        
        for row in cursor.fetchall():
            hourly_profits[int(row[0])] = row[1]
        
        # Gas efficiency analysis
        cursor = conn.execute('''
            SELECT AVG(gas_cost_eth / gross_profit_eth) as avg_gas_ratio,
                   MIN(gas_cost_eth / gross_profit_eth) as best_gas_ratio,
                   MAX(gas_cost_eth / gross_profit_eth) as worst_gas_ratio
            FROM profit_analysis
            WHERE timestamp > datetime('now', ?) AND gross_profit_eth > 0
        ''', (f'-{time_period}',))
        
        gas_analysis = cursor.fetchone()
        
        conn.close()
        
        return {
            'strategy_performance': strategy_profits,
            'hourly_performance': hourly_profits,
            'gas_efficiency': {
                'average_gas_ratio': gas_analysis[0],
                'best_gas_ratio': gas_analysis[1],
                'worst_gas_ratio': gas_analysis[2]
            },
            'optimization_recommendations': self._generate_recommendations(
                strategy_profits, hourly_profits, gas_analysis
            )
        }
    
    def _generate_recommendations(
        self,
        strategy_profits: Dict,
        hourly_profits: Dict,
        gas_analysis: Tuple
    ) -> List[str]:
        """Generate profit optimization recommendations"""
        recommendations = []
        
        # Strategy recommendations
        if strategy_profits:
            best_strategy = max(strategy_profits.items(), key=lambda x: x[1]['total_profit'])[0]
            recommendations.append(f"Focus on {best_strategy} strategy - highest profit generator")
        
        # Time-based recommendations
        if hourly_profits:
            best_hours = sorted(hourly_profits.items(), key=lambda x: x[1], reverse=True)[:3]
            hours_str = ', '.join([f"{h}:00" for h, _ in best_hours])
            recommendations.append(f"Concentrate efforts during peak hours: {hours_str}")
        
        # Gas optimization
        if gas_analysis[0] and gas_analysis[0] > 0.3:
            recommendations.append("High gas costs detected - optimize gas bidding strategy")
        
        return recommendations
EOF
```

---

## Multi-Chain Coordination

### Cross-Chain MEV Orchestration

```python
# Multi-chain coordinator
cat > /data/blockchain/nodes/mev/multichain_coordinator.py << 'EOF'
#!/usr/bin/env python3
import asyncio
from typing import Dict, List, Optional, Tuple
import json
from web3 import Web3
from dataclasses import dataclass
from enum import Enum

class Chain(Enum):
    ETHEREUM = 1
    ARBITRUM = 42161
    OPTIMISM = 10
    BASE = 8453
    POLYGON = 137

@dataclass
class CrossChainOpportunity:
    source_chain: Chain
    target_chain: Chain
    token_address: str
    price_difference: float
    estimated_profit_eth: float
    bridge_time_seconds: int
    liquidity_available: float

class MultiChainCoordinator:
    def __init__(self, chain_configs: Dict):
        self.chains = {}
        self.bridges = {
            'layerzero': {
                'supported_chains': [Chain.ETHEREUM, Chain.ARBITRUM, Chain.OPTIMISM, Chain.BASE, Chain.POLYGON],
                'fee_percent': 0.1,
                'time_seconds': 180
            },
            'stargate': {
                'supported_chains': [Chain.ETHEREUM, Chain.ARBITRUM, Chain.OPTIMISM, Chain.POLYGON],
                'fee_percent': 0.06,
                'time_seconds': 120
            },
            'hop': {
                'supported_chains': [Chain.ETHEREUM, Chain.ARBITRUM, Chain.OPTIMISM, Chain.POLYGON],
                'fee_percent': 0.04,
                'time_seconds': 300
            }
        }
        
        # Initialize chain connections
        for chain, config in chain_configs.items():
            self.chains[Chain[chain.upper()]] = {
                'w3': Web3(Web3.HTTPProvider(config['rpc_url'])),
                'dexes': config['dexes']
            }
    
    async def scan_cross_chain_opportunities(self) -> List[CrossChainOpportunity]:
        """Scan for cross-chain arbitrage opportunities"""
        opportunities = []
        
        # Common tokens to check across chains
        tokens = [
            {'symbol': 'USDC', 'addresses': {
                Chain.ETHEREUM: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
                Chain.ARBITRUM: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
                Chain.OPTIMISM: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
                Chain.BASE: '0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA',
                Chain.POLYGON: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'
            }},
            {'symbol': 'WETH', 'addresses': {
                Chain.ETHEREUM: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
                Chain.ARBITRUM: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
                Chain.OPTIMISM: '0x4200000000000000000000000000000000000006',
                Chain.BASE: '0x4200000000000000000000000000000000000006',
                Chain.POLYGON: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619'
            }}
        ]
        
        # Check prices across all chain pairs
        for token in tokens:
            prices = await self._get_token_prices_all_chains(token)
            
            # Find profitable arbitrage opportunities
            for source_chain, source_price in prices.items():
                for target_chain, target_price in prices.items():
                    if source_chain != target_chain and source_price > 0 and target_price > 0:
                        # Calculate price difference
                        price_diff_percent = ((target_price - source_price) / source_price) * 100
                        
                        # Check if profitable after bridge fees
                        bridge_cost = self._calculate_bridge_cost(source_chain, target_chain)
                        
                        if price_diff_percent > bridge_cost + 0.5:  # 0.5% minimum profit
                            opportunity = CrossChainOpportunity(
                                source_chain=source_chain,
                                target_chain=target_chain,
                                token_address=token['addresses'][source_chain],
                                price_difference=price_diff_percent,
                                estimated_profit_eth=self._estimate_profit(
                                    price_diff_percent, bridge_cost
                                ),
                                bridge_time_seconds=self._get_bridge_time(source_chain, target_chain),
                                liquidity_available=min(
                                    prices[source_chain]['liquidity'],
                                    prices[target_chain]['liquidity']
                                )
                            )
                            opportunities.append(opportunity)
        
        return sorted(opportunities, key=lambda x: x.estimated_profit_eth, reverse=True)
    
    async def _get_token_prices_all_chains(self, token: Dict) -> Dict:
        """Get token prices across all chains"""
        prices = {}
        
        async def get_price_for_chain(chain: Chain, address: str):
            if chain not in self.chains or chain not in token['addresses']:
                return None
            
            try:
                # Get price from primary DEX
                dex = self.chains[chain]['dexes'][0]
                price_data = await self._get_token_price(
                    self.chains[chain]['w3'],
                    address,
                    dex['router_address']
                )
                prices[chain] = price_data
            except Exception as e:
                print(f"Error getting price for {token['symbol']} on {chain.name}: {e}")
                prices[chain] = {'price': 0, 'liquidity': 0}
        
        # Fetch prices concurrently
        tasks = []
        for chain, address in token['addresses'].items():
            tasks.append(get_price_for_chain(chain, address))
        
        await asyncio.gather(*tasks)
        return prices
    
    async def execute_cross_chain_arbitrage(
        self,
        opportunity: CrossChainOpportunity,
        amount_eth: float
    ) -> Dict:
        """Execute cross-chain arbitrage"""
        
        # Step 1: Buy token on source chain
        buy_tx = await self._execute_swap(
            opportunity.source_chain,
            'ETH',
            opportunity.token_address,
            amount_eth
        )
        
        if not buy_tx['success']:
            return {
                'success': False,
                'reason': 'Failed to buy on source chain',
                'tx': buy_tx
            }
        
        # Step 2: Bridge tokens to target chain
        bridge_tx = await self._execute_bridge(
            opportunity.source_chain,
            opportunity.target_chain,
            opportunity.token_address,
            buy_tx['token_amount']
        )
        
        if not bridge_tx['success']:
            return {
                'success': False,
                'reason': 'Failed to bridge tokens',
                'tx': bridge_tx
            }
        
        # Step 3: Wait for bridge confirmation
        await asyncio.sleep(opportunity.bridge_time_seconds)
        
        # Step 4: Sell tokens on target chain
        sell_tx = await self._execute_swap(
            opportunity.target_chain,
            opportunity.token_address,
            'ETH',
            bridge_tx['bridged_amount']
        )
        
        # Calculate final profit
        total_gas_cost = (
            buy_tx.get('gas_cost_eth', 0) +
            bridge_tx.get('gas_cost_eth', 0) +
            sell_tx.get('gas_cost_eth', 0)
        )
        
        gross_profit = sell_tx.get('eth_received', 0) - amount_eth
        net_profit = gross_profit - total_gas_cost
        
        return {
            'success': sell_tx['success'],
            'gross_profit_eth': gross_profit,
            'net_profit_eth': net_profit,
            'transactions': {
                'buy': buy_tx,
                'bridge': bridge_tx,
                'sell': sell_tx
            }
        }
    
    def _calculate_bridge_cost(self, source: Chain, target: Chain) -> float:
        """Calculate total cost of bridging between chains"""
        best_bridge_fee = float('inf')
        
        for bridge_name, bridge_info in self.bridges.items():
            if source in bridge_info['supported_chains'] and target in bridge_info['supported_chains']:
                best_bridge_fee = min(best_bridge_fee, bridge_info['fee_percent'])
        
        # Add gas costs (approximate)
        gas_cost_percent = 0.2  # Rough estimate
        
        return best_bridge_fee + gas_cost_percent
    
    def _get_bridge_time(self, source: Chain, target: Chain) -> int:
        """Get estimated bridge time between chains"""
        fastest_time = float('inf')
        
        for bridge_name, bridge_info in self.bridges.items():
            if source in bridge_info['supported_chains'] and target in bridge_info['supported_chains']:
                fastest_time = min(fastest_time, bridge_info['time_seconds'])
        
        return int(fastest_time)
    
    async def coordinate_multi_chain_bundle(
        self,
        opportunities: List[Dict],
        max_chains: int = 3
    ) -> Dict:
        """Coordinate MEV execution across multiple chains"""
        
        # Group opportunities by chain
        chain_opportunities = {}
        for opp in opportunities:
            chain = Chain(opp['chain_id'])
            if chain not in chain_opportunities:
                chain_opportunities[chain] = []
            chain_opportunities[chain].append(opp)
        
        # Select best opportunities per chain
        selected_chains = []
        for chain, opps in chain_opportunities.items():
            if len(selected_chains) < max_chains:
                # Sort by profit and select top opportunity
                best_opp = max(opps, key=lambda x: x['estimated_profit_eth'])
                selected_chains.append({
                    'chain': chain,
                    'opportunity': best_opp
                })
        
        # Execute in parallel across chains
        execution_tasks = []
        for chain_opp in selected_chains:
            task = self._execute_chain_specific_mev(
                chain_opp['chain'],
                chain_opp['opportunity']
            )
            execution_tasks.append(task)
        
        results = await asyncio.gather(*execution_tasks, return_exceptions=True)
        
        # Aggregate results
        total_profit = 0
        successful_chains = []
        failed_chains = []
        
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                failed_chains.append(selected_chains[i]['chain'])
            elif result.get('success'):
                successful_chains.append(selected_chains[i]['chain'])
                total_profit += result.get('net_profit_eth', 0)
            else:
                failed_chains.append(selected_chains[i]['chain'])
        
        return {
            'total_profit_eth': total_profit,
            'successful_chains': successful_chains,
            'failed_chains': failed_chains,
            'execution_results': results
        }

# Multi-chain monitoring dashboard
class MultiChainMonitor:
    def __init__(self, chains: List[Chain]):
        self.chains = chains
        self.metrics = {chain: {} for chain in chains}
    
    async def update_chain_metrics(self):
        """Update metrics for all chains"""
        for chain in self.chains:
            self.metrics[chain] = await self._get_chain_metrics(chain)
    
    async def _get_chain_metrics(self, chain: Chain) -> Dict:
        """Get metrics for a specific chain"""
        # Implementation would fetch real metrics
        return {
            'block_number': 0,
            'gas_price': 0,
            'mempool_size': 0,
            'mev_opportunities': 0,
            'success_rate': 0,
            'daily_profit': 0
        }
    
    def get_chain_health_scores(self) -> Dict[Chain, float]:
        """Calculate health score for each chain"""
        scores = {}
        
        for chain, metrics in self.metrics.items():
            score = 100.0
            
            # Deduct points for high gas
            if metrics.get('gas_price', 0) > 100:
                score -= 20
            
            # Deduct points for low success rate
            if metrics.get('success_rate', 0) < 0.5:
                score -= 30
            
            # Add points for opportunities
            score += min(metrics.get('mev_opportunities', 0) * 2, 20)
            
            scores[chain] = max(0, min(100, score))
        
        return scores
EOF
```

---

## Flash Loan Integration

### Advanced Flash Loan Strategies

```python
# Flash loan integration
cat > /data/blockchain/nodes/mev/flash_loan_manager.py << 'EOF'
#!/usr/bin/env python3
from typing import Dict, List, Optional, Tuple
import json
from web3 import Web3
from eth_abi import encode_abi

class FlashLoanProvider(Enum):
    AAVE_V3 = "aave_v3"
    DYDX = "dydx"
    UNISWAP_V3 = "uniswap_v3"
    BALANCER = "balancer"

class FlashLoanManager:
    def __init__(self, web3: Web3):
        self.w3 = web3
        self.providers = {
            FlashLoanProvider.AAVE_V3: {
                'address': '0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2',
                'fee': 0.0005,  # 0.05%
                'max_loan': 10000,  # ETH
                'function': 'flashLoanSimple'
            },
            FlashLoanProvider.DYDX: {
                'address': '0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e',
                'fee': 0,  # No fee
                'max_loan': 5000,  # ETH
                'function': 'operate'
            },
            FlashLoanProvider.UNISWAP_V3: {
                'address': '0x',  # Various pools
                'fee': 0.0005,  # 0.05% per pool
                'max_loan': 1000,  # ETH per pool
                'function': 'flash'
            }
        }
    
    def calculate_flash_loan_profitability(
        self,
        opportunity: Dict,
        required_capital: float
    ) -> Dict:
        """Calculate if flash loan is profitable for opportunity"""
        
        best_provider = None
        best_profit = 0
        
        for provider, config in self.providers.items():
            if required_capital <= config['max_loan']:
                # Calculate fees
                loan_fee = required_capital * config['fee']
                
                # Calculate net profit
                gross_profit = opportunity['estimated_profit_eth']
                net_profit = gross_profit - loan_fee - opportunity['gas_cost_eth']
                
                if net_profit > best_profit:
                    best_profit = net_profit
                    best_provider = provider
        
        return {
            'profitable': best_profit > 0.01,  # Min 0.01 ETH profit
            'best_provider': best_provider,
            'loan_amount': required_capital,
            'loan_fee': required_capital * self.providers[best_provider]['fee'] if best_provider else 0,
            'net_profit': best_profit,
            'break_even_profit': required_capital * self.providers[best_provider]['fee'] if best_provider else 0
        }
    
    async def build_flash_loan_transaction(
        self,
        provider: FlashLoanProvider,
        loan_amount: float,
        profit_logic_calldata: bytes,
        receiver_address: str
    ) -> Dict:
        """Build flash loan transaction"""
        
        if provider == FlashLoanProvider.AAVE_V3:
            return self._build_aave_flash_loan(
                loan_amount,
                profit_logic_calldata,
                receiver_address
            )
        elif provider == FlashLoanProvider.DYDX:
            return self._build_dydx_flash_loan(
                loan_amount,
                profit_logic_calldata,
                receiver_address
            )
        else:
            raise ValueError(f"Unsupported provider: {provider}")
    
    def _build_aave_flash_loan(
        self,
        amount: float,
        calldata: bytes,
        receiver: str
    ) -> Dict:
        """Build Aave V3 flash loan transaction"""
        
        # Convert amount to Wei
        amount_wei = int(amount * 1e18)
        
        # Encode parameters
        params = encode_abi(
            ['address', 'uint256', 'bytes', 'uint16'],
            [
                '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',  # WETH
                amount_wei,
                calldata,
                0  # Referral code
            ]
        )
        
        return {
            'to': self.providers[FlashLoanProvider.AAVE_V3]['address'],
            'data': self.w3.keccak(text='flashLoanSimple(address,address,uint256,bytes,uint16)')[:4] + params,
            'value': 0,
            'gas': 3000000
        }
    
    async def execute_flash_loan_arbitrage(
        self,
        arbitrage_path: List[Dict],
        loan_amount: float,
        provider: FlashLoanProvider = FlashLoanProvider.AAVE_V3
    ) -> Dict:
        """Execute arbitrage using flash loan"""
        
        # Deploy flash loan receiver contract if not exists
        receiver_address = await self._ensure_flash_loan_receiver()
        
        # Encode arbitrage logic
        arbitrage_calldata = self._encode_arbitrage_logic(arbitrage_path)
        
        # Build flash loan transaction
        tx = await self.build_flash_loan_transaction(
            provider,
            loan_amount,
            arbitrage_calldata,
            receiver_address
        )
        
        # Simulate transaction
        simulation = await self._simulate_transaction(tx)
        
        if not simulation['success']:
            return {
                'success': False,
                'reason': 'Simulation failed',
                'error': simulation.get('error')
            }
        
        # Execute transaction
        tx_hash = await self._send_transaction(tx)
        
        # Wait for confirmation
        receipt = await self.w3.eth.wait_for_transaction_receipt(tx_hash)
        
        return {
            'success': receipt.status == 1,
            'tx_hash': tx_hash.hex(),
            'gas_used': receipt.gasUsed,
            'profit': self._calculate_actual_profit(receipt)
        }

# Flash loan receiver contract template
FLASH_LOAN_RECEIVER_CONTRACT = '''
pragma solidity ^0.8.0;

interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract FlashLoanArbitrage is IFlashLoanReceiver {
    address private owner;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Decode arbitrage parameters
        (address[] memory path, address[] memory routers) = abi.decode(
            params, 
            (address[], address[])
        );
        
        // Execute arbitrage logic
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        
        // Perform swaps through the path
        for (uint i = 0; i < path.length - 1; i++) {
            _swap(
                path[i], 
                path[i + 1], 
                routers[i], 
                IERC20(path[i]).balanceOf(address(this))
            );
        }
        
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        
        // Ensure profit
        require(balanceAfter > balanceBefore + premium, "No profit");
        
        // Repay flash loan
        IERC20(asset).approve(msg.sender, amount + premium);
        
        // Transfer profit to owner
        IERC20(asset).transfer(owner, balanceAfter - amount - premium);
        
        return true;
    }
    
    function _swap(
        address tokenIn,
        address tokenOut,
        address router,
        uint256 amountIn
    ) private {
        // Implementation depends on DEX
        // This is a simplified example
        IERC20(tokenIn).approve(router, amountIn);
        IRouter(router).swapExactTokensForTokens(
            amountIn,
            0,
            getPath(tokenIn, tokenOut),
            address(this),
            block.timestamp
        );
    }
}
'''

# Advanced flash loan strategies
class AdvancedFlashLoanStrategies:
    def __init__(self, flash_loan_manager: FlashLoanManager):
        self.flash_manager = flash_loan_manager
    
    async def multi_dex_arbitrage(
        self,
        token_pair: Tuple[str, str],
        dex_prices: Dict[str, float],
        max_loan: float = 100
    ) -> Optional[Dict]:
        """Execute multi-DEX arbitrage with flash loan"""
        
        # Find best arbitrage path
        best_path = self._find_best_arbitrage_path(token_pair, dex_prices)
        
        if not best_path or best_path['profit'] < 0.02:  # Min 0.02 ETH profit
            return None
        
        # Calculate required loan amount
        optimal_loan = self._calculate_optimal_loan_amount(
            best_path['price_impact_curve'],
            max_loan
        )
        
        # Check profitability with flash loan
        profitability = self.flash_manager.calculate_flash_loan_profitability(
            {'estimated_profit_eth': best_path['profit'], 'gas_cost_eth': 0.01},
            optimal_loan
        )
        
        if not profitability['profitable']:
            return None
        
        # Execute flash loan arbitrage
        result = await self.flash_manager.execute_flash_loan_arbitrage(
            best_path['swaps'],
            optimal_loan,
            profitability['best_provider']
        )
        
        return result
    
    async def liquidation_with_flash_loan(
        self,
        liquidation_opportunity: Dict,
        collateral_asset: str,
        debt_asset: str
    ) -> Dict:
        """Execute liquidation using flash loan"""
        
        # Calculate required flash loan amount
        debt_amount = liquidation_opportunity['debt_amount']
        
        # Build liquidation sequence
        sequence = [
            {
                'action': 'flash_loan',
                'asset': debt_asset,
                'amount': debt_amount
            },
            {
                'action': 'liquidate',
                'protocol': liquidation_opportunity['protocol'],
                'user': liquidation_opportunity['user'],
                'debt_to_cover': debt_amount
            },
            {
                'action': 'swap',
                'from': collateral_asset,
                'to': debt_asset,
                'amount': 'received_collateral'
            },
            {
                'action': 'repay_flash_loan',
                'amount': debt_amount,
                'fee': 'calculated'
            }
        ]
        
        # Simulate to ensure profitability
        simulation = await self._simulate_liquidation_sequence(sequence)
        
        if simulation['net_profit'] < 0.05:  # Min 0.05 ETH profit
            return {
                'success': False,
                'reason': 'Insufficient profit',
                'expected_profit': simulation['net_profit']
            }
        
        # Execute
        return await self._execute_liquidation_sequence(sequence)
    
    def _calculate_optimal_loan_amount(
        self,
        price_impact_curve: List[Tuple[float, float]],
        max_loan: float
    ) -> float:
        """Calculate optimal loan amount considering price impact"""
        
        # Find amount that maximizes profit
        best_amount = 0
        best_profit = 0
        
        for amount, expected_profit in price_impact_curve:
            if amount <= max_loan and expected_profit > best_profit:
                best_amount = amount
                best_profit = expected_profit
        
        return best_amount
EOF
```

---

## Bundle Optimization Strategies

### Advanced Bundle Construction

```python
# Bundle optimizer
cat > /data/blockchain/nodes/mev/bundle_optimizer.py << 'EOF'
#!/usr/bin/env python3
from typing import Dict, List, Optional, Tuple
import json
from dataclasses import dataclass
from enum import Enum

@dataclass
class Transaction:
    tx_hash: str
    from_address: str
    to_address: str
    value: int
    gas_price: int
    gas_limit: int
    data: str
    nonce: int

@dataclass
class MEVBundle:
    transactions: List[Transaction]
    block_number: int
    min_timestamp: Optional[int]
    max_timestamp: Optional[int]
    reverting_tx_hashes: List[str]
    target_profit_eth: float

class BundleOptimizer:
    def __init__(self):
        self.max_bundle_size = 10
        self.min_profit_wei = int(0.01 * 1e18)  # 0.01 ETH
        self.max_gas_per_bundle = 10_000_000  # 10M gas
    
    def optimize_bundle_composition(
        self,
        opportunities: List[Dict],
        block_base_fee: int,
        priority_fee: int
    ) -> MEVBundle:
        """Optimize bundle composition for maximum profit"""
        
        # Calculate effective gas price
        gas_price = block_base_fee + priority_fee
        
        # Score and sort opportunities
        scored_opportunities = []
        for opp in opportunities:
            score = self._calculate_opportunity_score(opp, gas_price)
            scored_opportunities.append((score, opp))
        
        scored_opportunities.sort(reverse=True, key=lambda x: x[0])
        
        # Build optimal bundle
        bundle_txs = []
        total_gas = 0
        total_profit = 0
        included_targets = set()  # Avoid conflicts
        
        for score, opp in scored_opportunities:
            if len(bundle_txs) >= self.max_bundle_size:
                break
            
            # Check gas limit
            if total_gas + opp['gas_estimate'] > self.max_gas_per_bundle:
                continue
            
            # Check for conflicts
            if opp['target_address'] in included_targets:
                continue
            
            # Check profitability
            gas_cost = opp['gas_estimate'] * gas_price
            net_profit = opp['profit_wei'] - gas_cost
            
            if net_profit < self.min_profit_wei:
                continue
            
            # Add to bundle
            tx = self._build_transaction(opp, gas_price)
            bundle_txs.append(tx)
            total_gas += opp['gas_estimate']
            total_profit += net_profit
            included_targets.add(opp['target_address'])
        
        return MEVBundle(
            transactions=bundle_txs,
            block_number=opp.get('target_block', 0),
            min_timestamp=None,
            max_timestamp=None,
            reverting_tx_hashes=[],
            target_profit_eth=total_profit / 1e18
        )
    
    def _calculate_opportunity_score(
        self,
        opportunity: Dict,
        gas_price: int
    ) -> float:
        """Calculate opportunity score for prioritization"""
        
        # Base score from profit
        gas_cost = opportunity['gas_estimate'] * gas_price
        net_profit = opportunity['profit_wei'] - gas_cost
        profit_score = net_profit / 1e18  # Convert to ETH
        
        # Adjust for success probability
        success_prob = opportunity.get('success_probability', 0.8)
        risk_adjusted_score = profit_score * success_prob
        
        # Boost for time-sensitive opportunities
        if opportunity.get('time_sensitive', False):
            risk_adjusted_score *= 1.2
        
        # Penalty for high gas usage
        gas_efficiency = opportunity['profit_wei'] / opportunity['gas_estimate']
        if gas_efficiency < gas_price * 2:  # Less than 2x gas price
            risk_adjusted_score *= 0.8
        
        return risk_adjusted_score
    
    def optimize_bundle_ordering(
        self,
        bundle: MEVBundle
    ) -> MEVBundle:
        """Optimize transaction ordering within bundle"""
        
        # Group transactions by dependency
        dependency_graph = self._build_dependency_graph(bundle.transactions)
        
        # Topological sort with profit optimization
        ordered_txs = self._topological_sort_with_profit(
            bundle.transactions,
            dependency_graph
        )
        
        bundle.transactions = ordered_txs
        return bundle
    
    def _build_dependency_graph(
        self,
        transactions: List[Transaction]
    ) -> Dict[int, List[int]]:
        """Build dependency graph for transactions"""
        
        graph = {i: [] for i in range(len(transactions))}
        
        for i, tx1 in enumerate(transactions):
            for j, tx2 in enumerate(transactions):
                if i != j:
                    # Check for dependencies
                    if self._has_dependency(tx1, tx2):
                        graph[i].append(j)
        
        return graph
    
    def _has_dependency(self, tx1: Transaction, tx2: Transaction) -> bool:
        """Check if tx1 must execute before tx2"""
        
        # Simple heuristic: same target contract
        if tx1.to_address == tx2.to_address:
            # tx1 should go first if it has lower nonce
            return tx1.nonce < tx2.nonce
        
        # Check for token approval patterns
        if 'approve' in str(tx1.data) and tx1.to_address == tx2.from_address:
            return True
        
        return False
    
    def apply_bundle_protection(
        self,
        bundle: MEVBundle,
        protection_level: str = "standard"
    ) -> MEVBundle:
        """Apply protection strategies to bundle"""
        
        if protection_level == "maximum":
            # Add reverting transaction at the end
            revert_tx = self._create_reverting_transaction()
            bundle.transactions.append(revert_tx)
            bundle.reverting_tx_hashes.append(revert_tx.tx_hash)
        
        elif protection_level == "standard":
            # Set tight time bounds
            bundle.min_timestamp = int(time.time())
            bundle.max_timestamp = bundle.min_timestamp + 12  # One block
        
        return bundle
    
    def calculate_bundle_metrics(
        self,
        bundle: MEVBundle,
        gas_price: int
    ) -> Dict:
        """Calculate comprehensive bundle metrics"""
        
        total_gas = sum(tx.gas_limit for tx in bundle.transactions)
        total_value = sum(tx.value for tx in bundle.transactions)
        
        # Calculate gas costs
        total_gas_cost = total_gas * gas_price
        
        # Efficiency metrics
        gas_efficiency = bundle.target_profit_eth / (total_gas / 1e6) if total_gas > 0 else 0
        value_efficiency = bundle.target_profit_eth / (total_value / 1e18) if total_value > 0 else 0
        
        return {
            'transaction_count': len(bundle.transactions),
            'total_gas': total_gas,
            'total_value_eth': total_value / 1e18,
            'gas_cost_eth': total_gas_cost / 1e18,
            'target_profit_eth': bundle.target_profit_eth,
            'net_profit_eth': bundle.target_profit_eth - (total_gas_cost / 1e18),
            'gas_efficiency': gas_efficiency,  # Profit per million gas
            'value_efficiency': value_efficiency,  # Profit per ETH moved
            'average_gas_per_tx': total_gas / len(bundle.transactions) if bundle.transactions else 0
        }

# Bundle submission manager
class BundleSubmissionManager:
    def __init__(self, flashbots_provider):
        self.flashbots = flashbots_provider
        self.submission_history = []
    
    async def submit_bundle_with_retry(
        self,
        bundle: MEVBundle,
        target_blocks: List[int],
        max_retries: int = 3
    ) -> Dict:
        """Submit bundle with retry logic"""
        
        submission_results = []
        
        for block_number in target_blocks:
            bundle.block_number = block_number
            
            for attempt in range(max_retries):
                try:
                    # Submit to Flashbots
                    result = await self.flashbots.send_bundle(
                        bundle.transactions,
                        target_block_number=block_number
                    )
                    
                    # Check submission status
                    bundle_hash = result['bundleHash']
                    status = await self._wait_for_bundle_status(
                        bundle_hash,
                        block_number
                    )
                    
                    submission_results.append({
                        'block': block_number,
                        'attempt': attempt + 1,
                        'bundle_hash': bundle_hash,
                        'status': status,
                        'included': status == 'included'
                    })
                    
                    if status == 'included':
                        return {
                            'success': True,
                            'block_number': block_number,
                            'bundle_hash': bundle_hash,
                            'attempts': submission_results
                        }
                    
                except Exception as e:
                    submission_results.append({
                        'block': block_number,
                        'attempt': attempt + 1,
                        'error': str(e)
                    })
        
        return {
            'success': False,
            'reason': 'Bundle not included in any target block',
            'attempts': submission_results
        }
    
    async def _wait_for_bundle_status(
        self,
        bundle_hash: str,
        target_block: int,
        timeout: int = 15
    ) -> str:
        """Wait for bundle inclusion status"""
        
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            status = await self.flashbots.get_bundle_status(
                bundle_hash,
                target_block
            )
            
            if status['status'] != 'pending':
                return status['status']
            
            await asyncio.sleep(1)
        
        return 'timeout'
    
    def analyze_submission_performance(self) -> Dict:
        """Analyze bundle submission performance"""
        
        if not self.submission_history:
            return {}
        
        total_submissions = len(self.submission_history)
        successful = sum(1 for s in self.submission_history if s['included'])
        
        return {
            'total_submissions': total_submissions,
            'successful_submissions': successful,
            'success_rate': successful / total_submissions if total_submissions > 0 else 0,
            'average_attempts': sum(s['attempts'] for s in self.submission_history) / total_submissions,
            'common_failure_reasons': self._analyze_failure_reasons()
        }
    
    def _analyze_failure_reasons(self) -> Dict[str, int]:
        """Analyze common failure reasons"""
        reasons = {}
        
        for submission in self.submission_history:
            if not submission['included']:
                reason = submission.get('failure_reason', 'unknown')
                reasons[reason] = reasons.get(reason, 0) + 1
        
        return reasons
EOF
```

---

## Appendix: MEV Strategy Quick Reference

### Strategy Selection Flowchart
```
Start → Check Market Conditions → Identify Opportunity Type
  ↓
Price Difference > 2% AND Liquidity > $100k
  → Arbitrage Strategy
  
Large Pending Transaction AND Slippage > 1%
  → Sandwich Strategy
  
Liquidatable Position AND Collateral > $50k
  → Liquidation Strategy
  
Cross-Chain Price Difference > 3%
  → Cross-Chain Arbitrage
  
High Capital Required AND Profit > 0.1 ETH
  → Flash Loan Strategy
```

### Key Performance Metrics
| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Success Rate | >70% | <50% |
| Average Profit | >0.05 ETH | <0.02 ETH |
| Gas Efficiency | >2x | <1.5x |
| Bundle Inclusion | >80% | <60% |
| ROI | >20% | <10% |

### Emergency Procedures
```bash
# Stop all MEV activities
systemctl stop mev-infra mev-artemis

# Clear pending transactions
./mev/clear_pending.sh

# Reset strategy engine
./mev/reset_strategies.sh

# Resume with safe mode
MEV_SAFE_MODE=true ./mev/start_mev.sh
```

---

**Document Classification**: CONFIDENTIAL - PROPRIETARY TRADING STRATEGIES  
**Last Updated**: July 17, 2025  
**Next Review**: July 24, 2025