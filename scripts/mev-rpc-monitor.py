#!/usr/bin/env python3
"""
MEV RPC Monitoring System with Advanced Metrics
Comprehensive monitoring of Ethereum RPC endpoints for MEV operations
"""

import asyncio
import aiohttp
import json
import time
import statistics
import logging
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import sys
import signal

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class RPCMetrics:
    """Metrics for a single RPC endpoint"""
    endpoint: str
    response_times: List[float] = field(default_factory=list)
    error_count: int = 0
    success_count: int = 0
    last_block: int = 0
    last_check: datetime = field(default_factory=datetime.now)
    availability: float = 100.0
    gas_price: float = 0.0
    tx_pool_size: int = 0
    mev_methods: Dict[str, float] = field(default_factory=dict)

@dataclass
class MEVMetrics:
    """MEV-specific metrics and analytics"""
    total_tx_per_second: float = 0.0
    avg_gas_price: float = 0.0
    mempool_size: int = 0
    block_propagation_delay: float = 0.0
    sandwich_opportunities: int = 0
    arbitrage_opportunities: int = 0
    failed_tx_rate: float = 0.0
    mev_profit_potential: float = 0.0

class MEVRPCMonitor:
    """Enhanced RPC monitoring for MEV operations"""

    def __init__(self):
        self.rpc_endpoints = [
            "http://127.0.0.1:8545",  # Geth
            "http://127.0.0.1:8549",  # Erigon
            "http://127.0.0.1:8554"   # Execution API
        ]

        self.metrics: Dict[str, RPCMetrics] = {}
        self.mev_metrics = MEVMetrics()
        self.monitoring = True
        self.session: Optional[aiohttp.ClientSession] = None

        # MEV-critical methods for special monitoring
        self.mev_critical_methods = {
            'eth_call', 'eth_sendRawTransaction', 'eth_getTransactionCount',
            'eth_getBlockByNumber', 'eth_getTransactionReceipt',
            'eth_getBlockByHash', 'debug_traceTransaction',
            'engine_forkchoiceUpdatedV1', 'engine_newPayloadV1',
            'eth_mining', 'eth_submitWork', 'eth_submitHashrate'
        }

        # Initialize metrics for each endpoint
        for endpoint in self.rpc_endpoints:
            self.metrics[endpoint] = RPCMetrics(endpoint=endpoint)

    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def measure_rpc_latency(self, endpoint: str, method: str, params: List = None) -> Tuple[float, bool, Any]:
        """Measure RPC call latency and success rate"""
        if params is None:
            params = []

        start_time = time.time()
        try:
            payload = {
                "jsonrpc": "2.0",
                "method": method,
                "params": params,
                "id": int(time.time() * 1000) % 1000000
            }

            timeout = aiohttp.ClientTimeout(total=3.0)
            async with self.session.post(endpoint, json=payload, timeout=timeout) as response:
                response_time = (time.time() - start_time) * 1000  # ms

                if response.status == 200:
                    result = await response.json()

                    # Update metrics based on method
                    if method in ['eth_blockNumber', 'eth_getBlockByNumber']:
                        if 'result' in result and isinstance(result['result'], str):
                            self.metrics[endpoint].last_block = int(result['result'], 16)

                    if method == 'eth_gasPrice' and 'result' in result:
                        try:
                            self.metrics[endpoint].gas_price = int(result['result'], 16) / 1e9  # Convert to GWEI
                        except (ValueError, TypeError):
                            pass

                    if method == 'txpool_status' and 'result' in result:
                        if isinstance(result['result'], dict):
                            self.metrics[endpoint].tx_pool_size = result['result'].get('pending', 0)

                    # Update MEV method-specific metrics
                    if method in self.mev_critical_methods:
                        if endpoint not in self.metrics[endpoint].mev_methods:
                            self.metrics[endpoint].mev_methods[method] = []
                        self.metrics[endpoint].mev_methods[method].append(response_time)

                    return response_time, True, result
                else:
                    return float('inf'), False, None

        except Exception as e:
            logger.error(f"RPC call failed for {endpoint} {method}: {e}")
            return float('inf'), False, None

    async def update_endpoint_health(self, endpoint: str):
        """Update health metrics for a specific endpoint"""
        try:
            # Test basic connectivity
            latency, success, _ = await self.measure_rpc_latency(endpoint, "eth_blockNumber")

            metrics = self.metrics[endpoint]
            metrics.last_check = datetime.now()

            if success and latency < 1000:  # 1 second threshold
                metrics.success_count += 1
                metrics.response_times.append(latency)

                # Keep only last 50 measurements
                if len(metrics.response_times) > 50:
                    metrics.response_times.pop(0)
            else:
                metrics.error_count += 1

            # Calculate availability (last 100 attempts)
            total_attempts = metrics.success_count + metrics.error_count
            if total_attempts > 0:
                metrics.availability = (metrics.success_count / total_attempts) * 100

            # Test MEV-critical methods
            await self._test_mev_methods(endpoint)

        except Exception as e:
            logger.error(f"Health check failed for {endpoint}: {e}")
            self.metrics[endpoint].error_count += 1

    async def _test_mev_methods(self, endpoint: str):
        """Test MEV-critical RPC methods"""
        critical_tests = [
            ("eth_blockNumber", []),
            ("eth_syncing", []),
            ("eth_gasPrice", []),
            ("txpool_status", [])
        ]

        for method, params in critical_tests:
            await self.measure_rpc_latency(endpoint, method, params)

    async def calculate_mev_metrics(self):
        """Calculate MEV-specific metrics across all endpoints"""
        try:
            total_gas_prices = []
            total_tx_pools = 0

            for metrics in self.metrics.values():
                if isinstance(metrics.gas_price, (int, float)) and metrics.gas_price > 0:
                    total_gas_prices.append(metrics.gas_price)
                total_tx_pools += metrics.tx_pool_size if isinstance(metrics.tx_pool_size, int) else 0

            if total_gas_prices:
                self.mev_metrics.avg_gas_price = statistics.mean(total_gas_prices)

            self.mev_metrics.mempool_size = total_tx_pools

            # Calculate transaction throughput (simplified estimation)
            if len(self.metrics) > 0:
                avg_response_time = statistics.mean([
                    statistics.mean(m.response_times) if m.response_times else 1000
                    for m in self.metrics.values()
                ])
                self.mev_metrics.total_tx_per_second = 1000 / avg_response_time

            # Estimate MEV opportunities based on gas price volatility
            if len(total_gas_prices) > 1:
                gas_volatility = statistics.stdev(total_gas_prices) / statistics.mean(total_gas_prices)
                self.mev_metrics.sandwich_opportunities = int(gas_volatility * 10)
                self.mev_metrics.mev_profit_potential = gas_volatility * 100

        except Exception as e:
            logger.error(f"Failed to calculate MEV metrics: {e}")

    async def monitor_mempool_activity(self):
        """Monitor mempool for MEV opportunities"""
        try:
            # Use best performing endpoint for mempool monitoring
            best_endpoint = self._get_best_endpoint()
            if not best_endpoint:
                return

            # Get pending transactions count
            _, _, result = await self.measure_rpc_latency(
                best_endpoint, "txpool_status"
            )

            if result and 'result' in result and isinstance(result['result'], dict):
                pending_count = result['result'].get('pending', 0)
                queued_count = result['result'].get('queued', 0)

                # Log mempool activity
                if isinstance(pending_count, int) and pending_count > 100:
                    logger.info(f"High mempool activity: {pending_count} pending, {queued_count} queued")

                # Detect potential MEV activity spikes
                if isinstance(pending_count, int) and pending_count > 500:
                    logger.warning(f"MEV activity spike detected: {pending_count} pending transactions")

        except Exception as e:
            logger.error(f"Mempool monitoring failed: {e}")

    def _get_best_endpoint(self) -> Optional[str]:
        """Get the best performing RPC endpoint"""
        best_endpoint = None
        best_score = float('inf')

        for endpoint, metrics in self.metrics.items():
            if metrics.response_times and metrics.availability > 95:
                avg_latency = statistics.mean(metrics.response_times)
                # Weight by availability and block height
                score = avg_latency / (metrics.availability / 100)

                if score < best_score:
                    best_score = score
                    best_endpoint = endpoint

        return best_endpoint

    async def generate_health_report(self) -> Dict[str, Any]:
        """Generate comprehensive health report"""
        report = {
            "timestamp": datetime.now().isoformat(),
            "summary": {
                "total_endpoints": len(self.rpc_endpoints),
                "healthy_endpoints": len([m for m in self.metrics.values() if m.availability > 95]),
                "avg_response_time": 0.0,
                "total_errors": sum(m.error_count for m in self.metrics.values())
            },
            "endpoints": {},
            "mev_metrics": {
                "total_tx_per_second": self.mev_metrics.total_tx_per_second,
                "avg_gas_price_gwei": self.mev_metrics.avg_gas_price,
                "mempool_size": self.mev_metrics.mempool_size,
                "sandwich_opportunities": self.mev_metrics.sandwich_opportunities,
                "mev_profit_potential": self.mev_metrics.mev_profit_potential
            }
        }

        all_response_times = []
        for endpoint, metrics in self.metrics.items():
            endpoint_data = {
                "endpoint": endpoint,
                "availability": metrics.availability,
                "avg_response_time_ms": statistics.mean(metrics.response_times) if metrics.response_times else 0,
                "last_block": metrics.last_block,
                "error_count": metrics.error_count,
                "success_count": metrics.success_count,
                "gas_price_gwei": metrics.gas_price,
                "tx_pool_size": metrics.tx_pool_size,
                "mev_method_performance": {}
            }

            # Add MEV method-specific performance
            for method, times in metrics.mev_methods.items():
                if times:
                    endpoint_data["mev_method_performance"][method] = {
                        "avg_latency_ms": statistics.mean(times),
                        "count": len(times),
                        "min_latency_ms": min(times),
                        "max_latency_ms": max(times)
                    }

            report["endpoints"][endpoint] = endpoint_data

            if metrics.response_times:
                all_response_times.extend(metrics.response_times)

        if all_response_times:
            report["summary"]["avg_response_time"] = statistics.mean(all_response_times)

        return report

    def print_status_dashboard(self, report: Dict[str, Any]):
        """Print formatted status dashboard"""
        print("\n" + "="*60)
        print("🚀 MEV RPC MONITOR DASHBOARD")
        print("="*60)
        print(f"📊 Timestamp: {report['timestamp']}")
        print(f"🔌 Healthy Endpoints: {report['summary']['healthy_endpoints']}/{report['summary']['total_endpoints']}")
        print(f"⚡ Avg Response Time: {report['summary']['avg_response_time']:.2f}ms")
        print(f"❌ Total Errors: {report['summary']['total_errors']}")

        print("\n📈 MEV Metrics:")
        print(f"   TX/sec: {report['mev_metrics']['total_tx_per_second']:.2f}")
        print(f"   Gas Price: {report['mev_metrics']['avg_gas_price_gwei']:.2f} GWEI")
        print(f"   Mempool Size: {report['mev_metrics']['mempool_size']:,}")
        print(f"   Sandwich Opportunities: {report['mev_metrics']['sandwich_opportunities']}")
        print(f"   MEV Profit Potential: ${report['mev_metrics']['mev_profit_potential']:.2f}")

        print("\n🔌 Endpoint Details:")
        for endpoint, data in report['endpoints'].items():
            status = "🟢" if data['availability'] > 95 else "🔴" if data['availability'] > 50 else "⚠️"
            print(f"   {status} {endpoint}")
            print(f"      Availability: {data['availability']:.1f}%")
            print(f"      Response Time: {data['avg_response_time_ms']:.2f}ms")
            print(f"      Block: {data['last_block']:,}")
            print(f"      Gas: {data['gas_price_gwei']:.2f} GWEI")
            print(f"      Errors: {data['error_count']}")

    async def monitoring_loop(self):
        """Main monitoring loop"""
        logger.info("Starting MEV RPC monitoring loop...")

        while self.monitoring:
            try:
                # Update all endpoint health
                tasks = []
                for endpoint in self.rpc_endpoints:
                    tasks.append(self.update_endpoint_health(endpoint))

                await asyncio.gather(*tasks, return_exceptions=True)

                # Calculate MEV metrics
                await self.calculate_mev_metrics()

                # Monitor mempool activity
                await self.monitor_mempool_activity()

                # Generate and display report
                report = await self.generate_health_report()
                self.print_status_dashboard(report)

                # Log to file for persistence
                with open("/var/log/mev-rpc-monitor.log", "a") as f:
                    f.write(f"{json.dumps(report)}\n")

                # Sleep for 30 seconds before next check
                await asyncio.sleep(30)

            except Exception as e:
                logger.error(f"Monitoring loop error: {e}")
                await asyncio.sleep(60)  # Wait longer on error

    async def start_monitoring(self):
        """Start the monitoring system"""
        print("🚀 Starting MEV RPC Monitoring System")
        print("=" * 50)

        # Create log directory
        import os
        os.makedirs("/var/log", exist_ok=True)

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
    async with MEVRPCMonitor() as monitor:
        await monitor.start_monitoring()

if __name__ == "__main__":
    asyncio.run(main())