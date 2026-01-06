#!/usr/bin/env python3
"""
Real-time Blockchain Sync Monitoring Script

Monitors blockchain node sync status in real-time with advanced alerting and analytics.
"""

import asyncio
import json
import time
import signal
import sys
import logging
from datetime import datetime, timedelta
from pathlib import Path
from blockchain_sync_verification_comprehensive import BlockchainSyncVerifier
import argparse

logger = logging.getLogger(__name__)

class RealTimeMonitor:
    """Real-time monitoring system with advanced features"""

    def __init__(self, config_file: str = "/data/blockchain/nodes/sync_verifier.conf"):
        self.verifier = BlockchainSyncVerifier(config_file)
        self.running = False
        self.start_time = None
        self.alert_counts = {"CRITICAL": 0, "WARNING": 0, "INFO": 0}
        self.performance_history = []
        self.last_export = None

    async def start_monitoring(self, duration_minutes: int = 60,
                             alert_threshold: str = "moderate",
                             output_format: str = "dashboard",
                             export_interval: int = 10):
        """Start real-time monitoring with advanced features"""
        self.running = True
        self.start_time = time.time()
        end_time = self.start_time + (duration_minutes * 60)
        iteration = 0

        print("🚀 BLOCKCHAIN SYNC REAL-TIME MONITOR")
        print("=" * 80)
        print(f"Duration: {duration_minutes} minutes")
        print(f"Alert Threshold: {alert_threshold}")
        print(f"Export Interval: {export_interval} minutes")
        print(f"Networks: {', '.join(self.verifier.config.networks)}")
        print(f"Node Types: {', '.join(self.verifier.config.node_types)}")
        print("=" * 80)

        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

        try:
            while self.running and time.time() < end_time:
                iteration += 1
                timestamp = datetime.now()
                elapsed = time.time() - self.start_time

                # Clear screen for dashboard view
                if output_format == "dashboard":
                    self._clear_screen()

                print(f"🕐 Iteration {iteration} - {timestamp.strftime('%H:%M:%S')}")
                print(f"⏱️  Elapsed: {elapsed/60:.1f}m | Remaining: {max(0, (end_time - time.time())/60):.1f}m")
                print("-" * 80)

                # Monitor all networks
                network_results = {}
                for network in self.verifier.config.networks:
                    try:
                        print(f"\n📡 Checking {network.upper()} Network...")
                        consistency = await self.verifier.verify_cross_node_consistency(network)
                        network_results[network] = consistency

                        # Display results
                        if output_format == "dashboard":
                            self._display_dashboard(consistency, network)
                        else:
                            self.verifier.display_consistency_results(consistency, output_format)

                        # Check and handle alerts
                        alerts = self.verifier.check_alerts(consistency, alert_threshold)
                        if alerts:
                            self._handle_alerts(alerts, network, timestamp)

                        # Collect performance metrics
                        self._collect_performance_metrics(consistency, timestamp)

                    except Exception as e:
                        print(f"❌ Error checking {network}: {e}")
                        logger.error(f"Error checking {network}: {e}")

                # Display summary dashboard
                if output_format == "dashboard":
                    self._display_summary_dashboard(network_results, iteration, elapsed)

                # Export data periodically
                if iteration % (export_interval * 2) == 0:  # Every export_interval minutes
                    await self._export_data(iteration, timestamp)

                # Sleep until next iteration
                if self.running and time.time() < end_time:
                    sleep_time = min(30, end_time - time.time())
                    print(f"\n⏳ Next check in {sleep_time}s... (Ctrl+C to stop)")
                    await asyncio.sleep(sleep_time)

        except KeyboardInterrupt:
            print("\n👋 Monitoring stopped by user")
        finally:
            await self._shutdown_monitoring(iteration)

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        print(f"\n🛑 Received signal {signum}, shutting down gracefully...")
        self.running = False

    def _clear_screen(self):
        """Clear terminal screen"""
        import os
        os.system('clear' if os.name == 'posix' else 'cls')

    def _display_dashboard(self, results: dict, network: str):
        """Display results in dashboard format"""
        if "error" in results:
            print(f"❌ {network}: {results['error']}")
            return

        summary = results.get("summary", {})
        nodes = results.get("nodes", {})

        # Network status
        status_emoji = "✅" if summary.get("consistent", False) else "⚠️"
        print(f"{status_emoji} {network.upper()}: {summary.get('block_difference', 0):,} block spread")

        # Node status bars
        for node_type, node_data in nodes.items():
            health = node_data.get("health_score", 0)
            sync_progress = node_data.get("sync_progress", 0)
            peer_count = node_data.get("peer_count", 0)
            issues = len(node_data.get("issues", []))

            # Health bar
            health_bar = self._create_progress_bar(health, 20, "█", "░")
            sync_bar = self._create_progress_bar(sync_progress, 20, "●", "○")

            status_icon = "🟢" if health > 70 else "🟡" if health > 40 else "🔴"
            issues_icon = "" if issues == 0 else f" [{issues} ⚠️]"

            print(f"   {status_icon} {node_type:<12} H:{health_bar} {health:3d}%")
            print(f"   └─ Sync: {sync_bar} {sync_progress:5.1f}% | Peers: {peer_count:2d} | RPC: {'✅' if node_data.get('rpc_responsive') else '❌'}{issues_icon}")

    def _create_progress_bar(self, value: float, width: int, fill_char: str = "█", empty_char: str = "░") -> str:
        """Create a progress bar"""
        filled = int((value / 100) * width)
        empty = width - filled
        return f"[{fill_char * filled}{empty_char * empty}]"

    def _display_summary_dashboard(self, network_results: dict, iteration: int, elapsed: float):
        """Display comprehensive summary dashboard"""
        print("\n" + "=" * 80)
        print("📊 SUMMARY DASHBOARD")
        print("=" * 80)

        # Overall stats
        total_nodes = sum(len(r.get("nodes", {})) for r in network_results.values() if "error" not in r)
        healthy_nodes = sum(1 for r in network_results.values() if "error" not in r
                           for n in r.get("nodes", {}).values() if n.get("health_score", 0) > 70)

        print(f"Iteration: {iteration} | Time: {elapsed/60:.1f}m | Nodes: {total_nodes} | Healthy: {healthy_nodes}")
        print(f"Alerts: 🚨 {self.alert_counts['CRITICAL']} | ⚠️ {self.alert_counts['WARNING']} | ℹ️ {self.alert_counts['INFO']}")

        # Network status overview
        print(f"\nNetwork Status:")
        for network, results in network_results.items():
            if "error" in results:
                print(f"   ❌ {network}: {results['error']}")
            else:
                summary = results.get("summary", {})
                status = "✅ GOOD" if summary.get("consistent", False) else "⚠️  DIVERGENCE"
                print(f"   {status} {network}: {summary.get('block_difference', 0):,} block spread")

        # Recent alerts (last 5)
        recent_alerts = self.verifier.alert_history[-5:] if self.verifier.alert_history else []
        if recent_alerts:
            print(f"\nRecent Alerts:")
            for alert in recent_alerts:
                icon = "🚨" if alert.get("type") == "CRITICAL" else "⚠️"
                node = f" ({alert.get('node', '')})" if alert.get("node") else ""
                print(f"   {icon} {alert.get('network', 'unknown')}{node}: {alert.get('message', '')}")

        # Performance trends
        if len(self.performance_history) > 1:
            print(f"\nPerformance Trends (last {len(self.performance_history)} checks):")
            avg_health = sum(p.get("avg_health", 0) for p in self.performance_history) / len(self.performance_history)
            avg_sync = sum(p.get("avg_sync", 0) for p in self.performance_history) / len(self.performance_history)
            print(f"   Average Health: {avg_health:.1f}% | Average Sync: {avg_sync:.1f}%")

    def _handle_alerts(self, alerts: list, network: str, timestamp: datetime):
        """Handle alerts with enhanced tracking"""
        for alert in alerts:
            alert_type = alert.get("type", "INFO")
            self.alert_counts[alert_type] += 1

            # Enhanced alert display
            node = alert.get("node", "")
            message = alert.get("message", "")

            if alert_type == "CRITICAL":
                icon = "🚨"
                print(f"\n{icon} CRITICAL ALERT [{network}]{f' - {node}' if node else ''}: {message}")
            elif alert_type == "WARNING":
                icon = "⚠️"
                print(f"{icon} Warning [{network}]{f' - {node}' if node else ''}: {message}")

        # Add to verifier history
        self.verifier.alert_history.extend(alerts)

    def _collect_performance_metrics(self, results: dict, timestamp: datetime):
        """Collect performance metrics for trend analysis"""
        if "error" in results:
            return

        nodes = results.get("nodes", {})
        if not nodes:
            return

        # Calculate averages
        health_scores = [n.get("health_score", 0) for n in nodes.values()]
        sync_progress = [n.get("sync_progress", 0) for n in nodes.values()]
        peer_counts = [n.get("peer_count", 0) for n in nodes.values()]
        response_times = [n.get("response_time", 0) for n in nodes.values()]

        metrics = {
            "timestamp": timestamp.isoformat(),
            "avg_health": sum(health_scores) / len(health_scores) if health_scores else 0,
            "avg_sync": sum(sync_progress) / len(sync_progress) if sync_progress else 0,
            "total_peers": sum(peer_counts),
            "avg_response_time": sum(response_times) / len(response_times) if response_times else 0,
            "node_count": len(nodes),
            "network": results.get("summary", {}).get("network", "unknown")
        }

        self.performance_history.append(metrics)

        # Keep only last 100 entries to avoid memory issues
        if len(self.performance_history) > 100:
            self.performance_history = self.performance_history[-100:]

    async def _export_data(self, iteration: int, timestamp: datetime):
        """Export monitoring data to files"""
        try:
            # Create export directory
            export_dir = Path("/var/log/blockchain_monitoring")
            export_dir.mkdir(parents=True, exist_ok=True)

            # Export performance history
            perf_file = export_dir / f"performance_{timestamp.strftime('%Y%m%d_%H%M%S')}.json"
            with open(perf_file, 'w') as f:
                json.dump(self.performance_history, f, indent=2)

            # Export alert summary
            alert_file = export_dir / f"alerts_{timestamp.strftime('%Y%m%d_%H%M%S')}.json"
            alert_summary = {
                "timestamp": timestamp.isoformat(),
                "iteration": iteration,
                "alert_counts": self.alert_counts,
                "recent_alerts": self.verifier.alert_history[-20:]  # Last 20 alerts
            }
            with open(alert_file, 'w') as f:
                json.dump(alert_summary, f, indent=2)

            self.last_export = timestamp
            print(f"💾 Data exported to {export_dir}")

        except Exception as e:
            print(f"❌ Failed to export data: {e}")

    async def _shutdown_monitoring(self, iteration: int):
        """Clean shutdown and final report"""
        print("\n" + "=" * 80)
        print("🏁 MONITORING SESSION COMPLETED")
        print("=" * 80)

        if self.start_time:
            duration = time.time() - self.start_time
            print(f"Total Duration: {duration/60:.1f} minutes")
            print(f"Total Iterations: {iteration}")

        print(f"\nAlert Summary:")
        print(f"   🚨 Critical: {self.alert_counts['CRITICAL']}")
        print(f"   ⚠️  Warnings: {self.alert_counts['WARNING']}")
        print(f"   ℹ️  Info: {self.alert_counts['INFO']}")

        # Generate final report
        try:
            report = await self.verifier.generate_monitoring_report()
            print(f"\n📄 Final report generated")
        except Exception as e:
            print(f"❌ Failed to generate final report: {e}")

        # Performance summary
        if self.performance_history:
            print(f"\n📈 Performance Summary:")
            avg_health = sum(p.get("avg_health", 0) for p in self.performance_history) / len(self.performance_history)
            avg_sync = sum(p.get("avg_sync", 0) for p in self.performance_history) / len(self.performance_history)
            print(f"   Average Health Score: {avg_health:.1f}%")
            print(f"   Average Sync Progress: {avg_sync:.1f}%")

async def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Real-time Blockchain Sync Monitor")
    parser.add_argument("--duration", type=int, default=60, help="Monitoring duration in minutes")
    parser.add_argument("--alert-threshold", choices=["conservative", "moderate", "aggressive"],
                       default="moderate", help="Alert sensitivity")
    parser.add_argument("--output-format", choices=["dashboard", "table", "json"],
                       default="dashboard", help="Output format")
    parser.add_argument("--export-interval", type=int, default=10, help="Export data every N minutes")
    parser.add_argument("--config", default="/data/blockchain/nodes/sync_verifier.conf",
                       help="Configuration file path")

    args = parser.parse_args()

    # Create and start monitor
    monitor = RealTimeMonitor(args.config)
    await monitor.start_monitoring(
        duration_minutes=args.duration,
        alert_threshold=args.alert_threshold,
        output_format=args.output_format,
        export_interval=args.export_interval
    )

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n👋 Goodbye!")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)