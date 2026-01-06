#!/usr/bin/env python3
"""
MEV Operations Dashboard
Real-time monitoring and analytics for MEV infrastructure components
"""

import asyncio
import aiohttp
import json
import time
import statistics
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
import logging
import sys
import signal
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class DashboardMetrics:
    """Dashboard metrics aggregation"""
    timestamp: datetime = field(default_factory=datetime.now)
    
    # RPC Endpoint Health
    rpc_endpoints_health: Dict[str, float] = field(default_factory=dict)
    rpc_response_times: Dict[str, List[float]] = field(default_factory=dict)
    rpc_error_rates: Dict[str, float] = field(default_factory=dict)
    
    # MEV Performance
    mev_opportunities: int = 0
    mev_profit_potential: float = 0.0
    mempool_size: int = 0
    gas_price_volatility: float = 0.0
    
    # Consensus Layer
    lighthouse_peers: int = 0
    lighthouse_sync_status: str = "unknown"
    lighthouse_finalized_epoch: int = 0
    
    # Storage Metrics
    storage_usage_percent: float = 0.0
    storage_growth_rate: float = 0.0
    chain_data_size: str = "0B"
    
    # System Health
    cpu_usage: float = 0.0
    memory_usage: float = 0.0
    network_latency: float = 0.0

class MEVDashboard:
    """MEV Operations Dashboard"""
    
    def __init__(self):
        self.metrics = DashboardMetrics()
        self.monitoring = True
        self.session: Optional[aiohttp.ClientSession] = None
        
        # Configuration
        self.rpc_endpoints = [
            "http://127.0.0.1:8545",  # Geth
            "http://127.0.0.1:8549",  # Erigon
            "http://127.0.0.1:8554"   # Execution API
        ]
        
        self.update_interval = 30  # seconds
        self.history_window = 100  # data points
        
        # Historical data for trends
        self.historical_data: List[DashboardMetrics] = []
        
        # Alert thresholds
        self.alert_thresholds = {
            "rpc_availability": 95.0,
            "storage_usage": 85.0,
            "memory_usage": 80.0,
            "cpu_usage": 75.0,
            "peer_count": 30
        }

    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def collect_rpc_metrics(self) -> Dict[str, Any]:
        """Collect RPC endpoint metrics"""
        rpc_stats = {}

        for endpoint in self.rpc_endpoints:
            try:
                # Test basic connectivity with eth_syncing
                start_time = time.time()
                payload = {
                    "jsonrpc": "2.0",
                    "method": "eth_syncing",
                    "params": [],
                    "id": int(time.time() * 1000) % 1000000
                }

                timeout = aiohttp.ClientTimeout(total=5.0)
                async with self.session.post(endpoint, json=payload, timeout=timeout) as response:
                    response_time = (time.time() - start_time) * 1000

                    if response.status == 200:
                        result = await response.json()

                        # Store response time
                        if endpoint not in self.metrics.rpc_response_times:
                            self.metrics.rpc_response_times[endpoint] = []
                        self.metrics.rpc_response_times[endpoint].append(response_time)

                        # Keep only recent measurements
                        if len(self.metrics.rpc_response_times[endpoint]) > self.history_window:
                            self.metrics.rpc_response_times[endpoint].pop(0)

                        # Calculate health score
                        recent_times = self.metrics.rpc_response_times[endpoint][-20:]
                        if recent_times:
                            avg_time = statistics.mean(recent_times)
                            availability = 100.0 if avg_time < 1000 else max(0, 100 - (avg_time - 1000) / 10)
                        else:
                            availability = 100.0

                        self.metrics.rpc_endpoints_health[endpoint] = availability

                        # Extract detailed sync information
                        sync_data = self._extract_sync_info(result, endpoint)
                        rpc_stats[endpoint] = {
                            "status": "healthy",
                            "response_time_ms": response_time,
                            "availability": availability,
                            **sync_data
                        }

                        # Also get current block number if syncing is complete
                        if sync_data.get("is_syncing") == False:
                            try:
                                block_payload = {
                                    "jsonrpc": "2.0",
                                    "method": "eth_blockNumber",
                                    "params": [],
                                    "id": int(time.time() * 1000) % 1000000 + 1
                                }
                                async with self.session.post(endpoint, json=block_payload, timeout=timeout) as block_response:
                                    if block_response.status == 200:
                                        block_result = await block_response.json()
                                        if "result" in block_result:
                                            rpc_stats[endpoint]["current_block"] = int(block_result["result"], 16)
                            except Exception:
                                pass  # Block number is optional

                    else:
                        self.metrics.rpc_error_rates[endpoint] = self.metrics.rpc_error_rates.get(endpoint, 0) + 1
                        rpc_stats[endpoint] = {
                            "status": "unhealthy",
                            "response_time_ms": None,
                            "availability": 0.0,
                            "error": f"HTTP {response.status}"
                        }

            except Exception as e:
                logger.error(f"RPC metrics collection failed for {endpoint}: {e}")
                self.metrics.rpc_error_rates[endpoint] = self.metrics.rpc_error_rates.get(endpoint, 0) + 1
                rpc_stats[endpoint] = {
                    "status": "error",
                    "response_time_ms": None,
                    "availability": 0.0,
                    "error": str(e)
                }

        return rpc_stats

    def _extract_sync_info(self, result: Dict, endpoint: str) -> Dict[str, Any]:
        """Extract detailed sync information from RPC response"""
        try:
            if "result" not in result:
                return {"sync_status": "unknown", "is_syncing": None}

            sync_result = result["result"]

            # Case 1: False (not syncing)
            if sync_result is False:
                return {
                    "sync_status": "synced",
                    "is_syncing": False,
                    "current_block": "N/A",
                    "highest_block": "N/A",
                    "sync_progress": 100.0
                }

            # Case 2: Object with sync details
            elif isinstance(sync_result, dict):
                current_block = sync_result.get("currentBlock", "0x0")
                highest_block = sync_result.get("highestBlock", "0x0")

                try:
                    current_int = int(current_block, 16) if isinstance(current_block, str) else int(current_block)
                    highest_int = int(highest_block, 16) if isinstance(highest_block, str) else int(highest_block)

                    progress = (current_int / highest_int * 100) if highest_int > 0 else 0.0
                    blocks_remaining = max(0, highest_int - current_int)

                    return {
                        "sync_status": "syncing" if progress < 100 else "synced",
                        "is_syncing": progress < 100,
                        "current_block": current_int,
                        "highest_block": highest_int,
                        "sync_progress": progress,
                        "blocks_remaining": blocks_remaining,
                        "starting_block": sync_result.get("startingBlock", "0x0")
                    }
                except (ValueError, TypeError):
                    return {
                        "sync_status": "syncing",
                        "is_syncing": True,
                        "current_block": current_block,
                        "highest_block": highest_block,
                        "sync_progress": 0.0
                    }

            else:
                return {"sync_status": "unknown", "is_syncing": None}

        except Exception as e:
            logger.error(f"Failed to extract sync info: {e}")
            return {"sync_status": "error", "is_syncing": None, "error": str(e)}

    def _extract_block_number(self, result: Dict) -> int:
        """Extract block number from RPC response"""
        try:
            if 'result' in result and result['result']:
                if isinstance(result['result'], dict) and 'number' in result['result']:
                    return result['result']['number']
                elif isinstance(result['result'], str) and result['result'].startswith('0x'):
                    return int(result['result'], 16)
        except (ValueError, TypeError, KeyError):
            pass
        return 0

    async def collect_lighthouse_metrics(self) -> Dict[str, Any]:
        """Collect Lighthouse consensus layer metrics"""
        lighthouse_stats = {}

        try:
            # Check if Lighthouse service is running first
            import subprocess
            result = subprocess.run(['systemctl', 'is-active', 'lighthouse'],
                                  capture_output=True, text=True, timeout=5)

            if result.returncode != 0 or result.stdout.strip() != 'active':
                lighthouse_stats = {
                    "status": "inactive",
                    "peer_count": 0,
                    "sync_status": "offline",
                    "current_epoch": 0,
                    "error": "Lighthouse service not running"
                }
                self.metrics.lighthouse_peers = 0
                self.metrics.lighthouse_sync_status = "offline"
                self.metrics.lighthouse_finalized_epoch = 0
                return lighthouse_stats

            # Get peer count
            peer_count_url = "http://127.0.0.1:5052/eth/v1/node/peer_count"
            async with self.session.get(peer_count_url, timeout=aiohttp.ClientTimeout(total=5.0)) as response:
                if response.status == 200:
                    data = await response.json()
                    if 'data' in data:
                        self.metrics.lighthouse_peers = data['data'].get('connected', 0)
                        lighthouse_stats['peer_count'] = self.metrics.lighthouse_peers
                else:
                    lighthouse_stats['peer_count_error'] = f"HTTP {response.status}"

            # Get sync status
            sync_url = "http://127.0.0.1:5052/eth/v1/node/syncing"
            async with self.session.get(sync_url, timeout=aiohttp.ClientTimeout(total=5.0)) as response:
                if response.status == 200:
                    data = await response.json()
                    if 'data' in data:
                        is_syncing = data['data'].get('is_syncing', False)
                        self.metrics.lighthouse_sync_status = "syncing" if is_syncing else "synced"
                        lighthouse_stats['sync_status'] = self.metrics.lighthouse_sync_status

                        # Get head slot for approximate epoch
                        head_slot = data['data'].get('head_slot', 0)
                        try:
                            head_slot_int = int(head_slot) if head_slot else 0
                            self.metrics.lighthouse_finalized_epoch = head_slot_int // 32  # Approximate
                        except (ValueError, TypeError):
                            self.metrics.lighthouse_finalized_epoch = 0
                        lighthouse_stats['current_epoch'] = self.metrics.lighthouse_finalized_epoch
                else:
                    lighthouse_stats['sync_status_error'] = f"HTTP {response.status}"

        except Exception as e:
            logger.error(f"Lighthouse metrics collection failed: {e}")
            lighthouse_stats = {
                "status": "error",
                "peer_count": 0,
                "sync_status": "unknown",
                "current_epoch": 0,
                "error": str(e)
            }
            self.metrics.lighthouse_peers = 0
            self.metrics.lighthouse_sync_status = "error"
            self.metrics.lighthouse_finalized_epoch = 0

        return lighthouse_stats

    async def collect_storage_metrics(self) -> Dict[str, Any]:
        """Collect storage usage metrics"""
        storage_stats = {}
        
        try:
            # Get storage usage from df command
            import subprocess
            result = subprocess.run(
                ['df', '-h', '/data/blockchain'],
                capture_output=True, text=True, timeout=10
            )
            
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) > 1:
                    stats_line = lines[-1]
                    parts = stats_line.split()
                    if len(parts) >= 5:
                        usage_str = parts[4].replace('%', '')
                        self.metrics.storage_usage_percent = float(usage_str)
                        self.metrics.chain_data_size = parts[2]
                        
                        storage_stats = {
                            "usage_percent": self.metrics.storage_usage_percent,
                            "total_space": parts[1],
                            "used_space": parts[2],
                            "available_space": parts[3],
                            "chain_data_size": self.metrics.chain_data_size
                        }

            # Calculate growth rate (simplified)
            if len(self.historical_data) > 1:
                previous_usage = self.historical_data[-2].storage_usage_percent
                current_usage = self.metrics.storage_usage_percent
                time_diff = (datetime.now() - self.historical_data[-2].timestamp).total_seconds() / 3600  # hours
                if time_diff > 0:
                    try:
                        self.metrics.storage_growth_rate = float(current_usage - previous_usage) / time_diff
                    except (TypeError, ZeroDivisionError):
                        self.metrics.storage_growth_rate = 0.0
                    storage_stats['growth_rate_per_hour'] = self.metrics.storage_growth_rate

        except Exception as e:
            logger.error(f"Storage metrics collection failed: {e}")
            storage_stats = {"error": str(e)}
        
        return storage_stats

    async def collect_system_metrics(self) -> Dict[str, Any]:
        """Collect system performance metrics"""
        system_stats = {}
        
        try:
            # Get CPU usage (simplified)
            import subprocess
            cpu_result = subprocess.run(
                ['top', '-bn1', '-o', '%C'],
                capture_output=True, text=True, timeout=5
            )
            
            if cpu_result.returncode == 0:
                cpu_lines = cpu_result.stdout.strip().split('\n')
                if cpu_lines:
                    try:
                        cpu_usage = float(cpu_lines[0])
                        self.metrics.cpu_usage = cpu_usage
                        system_stats['cpu_usage'] = cpu_usage
                    except (ValueError, IndexError):
                        pass

            # Get memory usage
            memory_result = subprocess.run(
                ['free', '-m'],
                capture_output=True, text=True, timeout=5
            )
            
            if memory_result.returncode == 0:
                lines = memory_result.stdout.strip().split('\n')
                for line in lines:
                    if line.startswith('Mem:'):
                        parts = line.split()
                        if len(parts) >= 7:
                            total_mb = float(parts[1])
                            used_mb = float(parts[2])
                            self.metrics.memory_usage = (used_mb / total_mb) * 100
                            system_stats['memory_usage'] = self.metrics.memory_usage
                            system_stats['memory_total_mb'] = total_mb
                            system_stats['memory_used_mb'] = used_mb

        except Exception as e:
            logger.error(f"System metrics collection failed: {e}")
            system_stats = {"error": str(e)}
        
        return system_stats

    async def calculate_mev_metrics(self):
        """Calculate MEV-specific metrics"""
        try:
            # Estimate MEV opportunities based on RPC activity
            total_requests = sum(len(times) for times in self.metrics.rpc_response_times.values())
            
            # Calculate gas price volatility from different endpoints
            gas_prices = []
            for endpoint, times in self.metrics.rpc_response_times.items():
                if times:
                    avg_latency = statistics.mean(times)
                    gas_prices.append(avg_latency)
            
            if len(gas_prices) > 1:
                self.metrics.gas_price_volatility = statistics.stdev(gas_prices) / statistics.mean(gas_prices) if statistics.mean(gas_prices) > 0 else 0
            
            # Estimate MEV opportunities (simplified heuristic)
            self.metrics.mev_opportunities = int(self.metrics.gas_price_volatility * 10)
            self.metrics.mev_profit_potential = self.metrics.gas_price_volatility * 100
            
            # Estimate mempool size based on RPC activity
            self.metrics.mempool_size = total_requests * 50  # Rough estimate
            
        except Exception as e:
            logger.error(f"MEV metrics calculation failed: {e}")

    def check_alerts(self) -> List[Dict[str, Any]]:
        """Check for alert conditions"""
        alerts = []
        
        # RPC availability alerts
        for endpoint, health in self.metrics.rpc_endpoints_health.items():
            if health < self.alert_thresholds["rpc_availability"]:
                alerts.append({
                    "type": "rpc_health",
                    "severity": "warning" if health > 80 else "critical",
                    "endpoint": endpoint,
                    "health": health,
                    "message": f"RPC endpoint {endpoint} has low availability: {health:.1f}%"
                })
        
        # Storage usage alerts
        if self.metrics.storage_usage_percent > self.alert_thresholds["storage_usage"]:
            alerts.append({
                "type": "storage_usage",
                "severity": "warning" if self.metrics.storage_usage_percent < 95 else "critical",
                "usage_percent": self.metrics.storage_usage_percent,
                "growth_rate": self.metrics.storage_growth_rate,
                "message": f"Storage usage is {self.metrics.storage_usage_percent:.1f}% (growing at {self.metrics.storage_growth_rate:.2f}%/hour)"
            })
        
        # System resource alerts
        if self.metrics.memory_usage > self.alert_thresholds["memory_usage"]:
            alerts.append({
                "type": "memory_usage",
                "severity": "warning" if self.metrics.memory_usage < 90 else "critical",
                "usage_percent": self.metrics.memory_usage,
                "message": f"Memory usage is high: {self.metrics.memory_usage:.1f}%"
            })
        
        if self.metrics.cpu_usage > self.alert_thresholds["cpu_usage"]:
            alerts.append({
                "type": "cpu_usage",
                "severity": "warning" if self.metrics.cpu_usage < 85 else "critical",
                "usage_percent": self.metrics.cpu_usage,
                "message": f"CPU usage is high: {self.metrics.cpu_usage:.1f}%"
            })
        
        # Lighthouse peer alerts
        if self.metrics.lighthouse_peers < self.alert_thresholds["peer_count"]:
            alerts.append({
                "type": "peer_count",
                "severity": "warning",
                "peer_count": self.metrics.lighthouse_peers,
                "message": f"Lighthouse has low peer count: {self.metrics.lighthouse_peers}"
            })
        
        return alerts

    def generate_dashboard_data(self) -> Dict[str, Any]:
        """Generate complete dashboard data"""
        # Extract sync information from existing metrics
        sync_data = {}
        for endpoint in self.rpc_endpoints:
            sync_data[endpoint] = {
                "sync_status": "checking",
                "is_syncing": None,
                "current_block": None,
                "highest_block": None,
                "sync_progress": 0.0,
                "blocks_remaining": 0
            }

        return {
            "timestamp": self.metrics.timestamp.isoformat(),
            "summary": {
                "overall_health": self._calculate_overall_health(),
                "total_alerts": len(self.check_alerts()),
                "rpc_endpoints": len(self.rpc_endpoints),
                "lighthouse_peers": self.metrics.lighthouse_peers,
                "storage_usage": self.metrics.storage_usage_percent
            },
            "metrics": {
                "rpc": {
                    "endpoints": self.metrics.rpc_endpoints_health,
                    "sync_data": sync_data,
                    "response_times": {
                        endpoint: {
                            "avg_ms": statistics.mean(times) if times else 0,
                            "min_ms": min(times) if times else 0,
                            "max_ms": max(times) if times else 0,
                            "count": len(times)
                        } for endpoint, times in self.metrics.rpc_response_times.items()
                    },
                    "error_rates": self.metrics.rpc_error_rates
                },
                "consensus": {
                    "peer_count": self.metrics.lighthouse_peers,
                    "sync_status": self.metrics.lighthouse_sync_status,
                    "current_epoch": self.metrics.lighthouse_finalized_epoch
                },
                "storage": {
                    "usage_percent": self.metrics.storage_usage_percent,
                    "growth_rate": self.metrics.storage_growth_rate,
                    "chain_data_size": self.metrics.chain_data_size
                },
                "system": {
                    "cpu_usage": self.metrics.cpu_usage,
                    "memory_usage": self.metrics.memory_usage
                },
                "mev": {
                    "opportunities": self.metrics.mev_opportunities,
                    "profit_potential": self.metrics.mev_profit_potential,
                    "mempool_size": self.metrics.mempool_size,
                    "gas_price_volatility": self.metrics.gas_price_volatility
                }
            },
            "alerts": self.check_alerts(),
            "trends": self._calculate_trends()
        }

    def _calculate_overall_health(self) -> float:
        """Calculate overall system health score"""
        weights = {
            "rpc_availability": 0.3,
            "storage_health": 0.2,
            "system_health": 0.2,
            "consensus_health": 0.2,
            "mev_health": 0.1
        }
        
        scores = {
            "rpc_availability": statistics.mean(list(self.metrics.rpc_endpoints_health.values())) if self.metrics.rpc_endpoints_health else 0,
            "storage_health": max(0, 100 - self.metrics.storage_usage_percent),
            "system_health": max(0, 100 - max(self.metrics.cpu_usage, self.metrics.memory_usage)),
            "consensus_health": min(100, self.metrics.lighthouse_peers * 2) if self.metrics.lighthouse_peers > 0 else 0,
            "mev_health": max(0, 100 - (self.metrics.gas_price_volatility * 50))
        }
        
        return sum(weights[key] * scores[key] for key in weights.keys())

    def _calculate_trends(self) -> Dict[str, Any]:
        """Calculate trend data from historical metrics"""
        if len(self.historical_data) < 2:
            return {}
        
        current = self.metrics
        previous = self.historical_data[-1]
        
        trends = {}
        
        # RPC availability trend
        current_rpc_health = statistics.mean(list(current.rpc_endpoints_health.values())) if current.rpc_endpoints_health else 0
        previous_rpc_health = statistics.mean(list(previous.rpc_endpoints_health.values())) if previous.rpc_endpoints_health else 0
        trends["rpc_availability"] = current_rpc_health - previous_rpc_health
        
        # Storage usage trend
        trends["storage_usage"] = current.storage_usage_percent - previous.storage_usage_percent
        
        # System usage trends
        trends["cpu_usage"] = current.cpu_usage - previous.cpu_usage
        trends["memory_usage"] = current.memory_usage - previous.memory_usage
        
        return trends

    def display_dashboard(self):
        """Display formatted dashboard in terminal"""
        data = self.generate_dashboard_data()

        # Update sync data with latest RPC metrics
        if hasattr(self, 'latest_rpc_metrics'):
            for endpoint, stats in self.latest_rpc_metrics.items():
                if 'sync_data' in data['metrics']['rpc'] and endpoint in data['metrics']['rpc']['sync_data']:
                    data['metrics']['rpc']['sync_data'][endpoint].update({
                        "sync_status": stats.get("sync_status", "unknown"),
                        "is_syncing": stats.get("is_syncing", None),
                        "current_block": stats.get("current_block", None),
                        "highest_block": stats.get("highest_block", None),
                        "sync_progress": stats.get("sync_progress", 0.0),
                        "blocks_remaining": stats.get("blocks_remaining", 0)
                    })
        
        # Clear screen
        os.system('clear' if os.name == 'posix' else 'cls')
        
        # Header
        print("🚀 MEV OPERATIONS DASHBOARD")
        print("=" * 60)
        print(f"📊 Last Updated: {data['timestamp']}")
        print(f"🏥 Overall Health: {data['summary']['overall_health']:.1f}%")
        print(f"🚨 Active Alerts: {data['summary']['total_alerts']}")
        print()
        
        # Alerts Section
        if data['alerts']:
            print("🚨 ALERTS")
            print("-" * 30)
            for alert in data['alerts'][:5]:  # Show top 5 alerts
                severity_icon = "🔴" if alert['severity'] == 'critical' else "🟡"
                print(f"  {severity_icon} {alert['message']}")
            print()
        
        # RPC Endpoints with Sync Status
        print("📡 BLOCKCHAIN NODES")
        print("-" * 30)
        for endpoint, health in data['metrics']['rpc']['endpoints'].items():
            status = "🟢" if health > 95 else "🟡" if health > 80 else "🔴"
            avg_time = data['metrics']['rpc']['response_times'].get(endpoint, {}).get('avg_ms', 0)

            # Get sync information
            sync_status = data['metrics']['rpc'].get('sync_data', {}).get(endpoint, {})
            sync_progress = sync_status.get('sync_progress', 0)
            current_block = sync_status.get('current_block', 'N/A')
            highest_block = sync_status.get('highest_block', 'N/A')
            blocks_remaining = sync_status.get('blocks_remaining', 0)

            print(f"  {status} {endpoint}")
            print(f"     Health: {health:.1f}% | Latency: {avg_time:.1f}ms")

            if isinstance(current_block, int):
                node_name = endpoint.split('/')[-1] if ':' in endpoint else endpoint
                print(f"     Block: {current_block:,} | Sync: {sync_progress:.1f}%")
                if blocks_remaining > 0:
                    print(f"     Remaining: {blocks_remaining:,} blocks")
            elif current_block == "N/A" and sync_progress == 100.0:
                print(f"     Status: Synced ✅")
            else:
                sync_label = sync_status.get('sync_status', 'unknown')
                print(f"     Status: {sync_label}")
        print()
        
        # Consensus Layer
        print("⛓ CONSENSUS LAYER")
        print("-" * 30)
        print(f"  Peers: {data['metrics']['consensus']['peer_count']}")
        print(f"  Sync Status: {data['metrics']['consensus']['sync_status']}")
        print(f"  Current Epoch: {data['metrics']['consensus']['current_epoch']}")
        print()
        
        # Storage
        print("💾 STORAGE")
        print("-" * 30)
        print(f"  Usage: {data['metrics']['storage']['usage_percent']:.1f}%")
        print(f"  Chain Data: {data['metrics']['storage']['chain_data_size']}")
        print(f"  Growth Rate: {data['metrics']['storage']['growth_rate']:.2f}%/hr")
        print()
        
        # MEV Metrics
        print("💰 MEV METRICS")
        print("-" * 30)
        print(f"  Opportunities: {data['metrics']['mev']['opportunities']}")
        print(f"  Profit Potential: ${data['metrics']['mev']['profit_potential']:.2f}")
        print(f"  Mempool Size: {data['metrics']['mev']['mempool_size']:,}")
        print(f"  Gas Volatility: {data['metrics']['mev']['gas_price_volatility']:.3f}")
        print()
        
        # System Resources
        print("🖥️ SYSTEM RESOURCES")
        print("-" * 30)
        print(f"  CPU: {data['metrics']['system']['cpu_usage']:.1f}%")
        print(f"  Memory: {data['metrics']['system']['memory_usage']:.1f}%")
        print()

    async def save_dashboard_data(self):
        """Save dashboard data to file"""
        try:
            data = self.generate_dashboard_data()
            
            # Create directory if it doesn't exist
            os.makedirs("/var/log/mev-dashboard", exist_ok=True)
            
            # Save current data
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"/var/log/mev-dashboard/dashboard_{timestamp}.json"
            
            with open(filename, 'w') as f:
                json.dump(data, f, indent=2, default=str)
            
            # Keep only last 100 files
            import glob
            files = glob.glob("/var/log/mev-dashboard/dashboard_*.json")
            files.sort()
            for old_file in files[:-100]:
                try:
                    os.remove(old_file)
                except OSError:
                    pass
            
            logger.info(f"Dashboard data saved to {filename}")
            
        except Exception as e:
            logger.error(f"Failed to save dashboard data: {e}")

    async def monitoring_loop(self):
        """Main monitoring loop"""
        logger.info("Starting MEV dashboard monitoring...")

        # Store latest RPC metrics for dashboard display
        self.latest_rpc_metrics = {}

        while self.monitoring:
            try:
                # Collect all metrics
                rpc_metrics = await self.collect_rpc_metrics()
                self.latest_rpc_metrics = rpc_metrics  # Store for display

                lighthouse_metrics = await self.collect_lighthouse_metrics()
                storage_metrics = await self.collect_storage_metrics()
                system_metrics = await self.collect_system_metrics()

                # Calculate MEV metrics
                await self.calculate_mev_metrics()

                # Display dashboard
                self.display_dashboard()

                # Save data
                await self.save_dashboard_data()

                # Store historical data
                self.historical_data.append(self.metrics)
                if len(self.historical_data) > self.history_window:
                    self.historical_data.pop(0)

                # Sleep until next update
                await asyncio.sleep(self.update_interval)

            except Exception as e:
                logger.error(f"Dashboard monitoring error: {e}")
                await asyncio.sleep(60)  # Wait longer on error

    async def start_dashboard(self):
        """Start the dashboard monitoring"""
        print("🚀 Starting MEV Operations Dashboard")
        print("=" * 50)
        
        # Create log directory
        import os
        os.makedirs("/var/log/mev-dashboard", exist_ok=True)
        
        # Handle shutdown gracefully
        def signal_handler(signum, frame):
            print(f"\n🛑 Received signal {signum}. Shutting down gracefully...")
            self.monitoring = False
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
        
        # Run monitoring loop
        await self.monitoring_loop()

async def main():
    """Main function"""
    async with MEVDashboard() as dashboard:
        await dashboard.start_dashboard()

if __name__ == "__main__":
    asyncio.run(main())