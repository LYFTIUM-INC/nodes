#!/usr/bin/env python3
"""
Comprehensive Blockchain Verification Report Generator

Generates detailed reports on blockchain node sync status, performance,
and system health with analytics and recommendations.
"""

import asyncio
import json
import time
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Any
import argparse

# Add the current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

try:
    from blockchain_sync_verification_comprehensive import BlockchainSyncVerifier
except ImportError:
    print("❌ Cannot import verification module")
    sys.exit(1)

class VerificationReportGenerator:
    """Comprehensive report generator with analytics"""

    def __init__(self, config_file: str = "/data/blockchain/nodes/sync_verifier.conf"):
        self.config_file = config_file
        self.report_data = {
            "metadata": {},
            "executive_summary": {},
            "network_analysis": {},
            "node_analysis": {},
            "performance_metrics": {},
            "alerts": {},
            "recommendations": [],
            "historical_data": {},
            "appendix": {}
        }

    async def generate_comprehensive_report(self, networks: List[str] = None,
                                          output_file: str = None,
                                          include_historical: bool = False,
                                          verification_level: str = "standard") -> str:
        """Generate comprehensive verification report"""
        print("📊 Generating Comprehensive Blockchain Verification Report...")
        start_time = time.time()

        if networks is None:
            networks = ["mainnet", "sepolia", "holesky"]

        # Initialize metadata
        self.report_data["metadata"] = {
            "report_type": "comprehensive_verification",
            "generated_at": datetime.now().isoformat(),
            "verification_level": verification_level,
            "networks_analyzed": networks,
            "report_version": "1.0",
            "generator": "blockchain_sync_verification_system"
        }

        async with BlockchainSyncVerifier(self.config_file) as verifier:
            # Analyze each network
            network_results = {}
            for network in networks:
                print(f"🔍 Analyzing {network} network...")
                try:
                    result = await verifier.verify_cross_node_consistency(network)
                    network_results[network] = result
                except Exception as e:
                    print(f"❌ Error analyzing {network}: {e}")
                    network_results[network] = {"error": str(e)}

            # Process results and generate analysis
            await self._process_network_results(network_results, verifier)
            await self._generate_executive_summary()
            await self._generate_performance_metrics()
            await self._generate_recommendations()
            await self._generate_appendix(verifier)

            if include_historical:
                await self._include_historical_data()

        # Calculate generation time
        generation_time = time.time() - start_time
        self.report_data["metadata"]["generation_time_seconds"] = round(generation_time, 2)

        # Save report
        if output_file is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_file = f"/var/log/blockchain_comprehensive_report_{timestamp}.json"

        await self._save_report(output_file)

        print(f"✅ Report generated successfully in {generation_time:.2f}s")
        print(f"📄 Report saved to: {output_file}")

        return output_file

    async def _process_network_results(self, network_results: Dict[str, Any],
                                      verifier: BlockchainSyncVerifier):
        """Process and analyze network results"""
        self.report_data["network_analysis"] = {}

        total_nodes = 0
        total_healthy = 0
        total_alerts = 0

        for network, results in network_results.items():
            if "error" in results:
                self.report_data["network_analysis"][network] = {
                    "status": "error",
                    "error": results["error"],
                    "nodes_analyzed": 0,
                    "health_score": 0
                }
                continue

            summary = results.get("summary", {})
            nodes = results.get("nodes", {})

            # Calculate network metrics
            node_count = len(nodes)
            healthy_nodes = sum(1 for n in nodes.values() if n.get("health_score", 0) > 70)
            avg_health = sum(n.get("health_score", 0) for n in nodes.values()) / node_count if node_count > 0 else 0
            avg_sync = sum(n.get("sync_progress", 0) for n in nodes.values()) / node_count if node_count > 0 else 0

            # Check for alerts
            alerts = verifier.check_alerts(results, "moderate")
            critical_alerts = len([a for a in alerts if a.get("type") == "CRITICAL"])
            warning_alerts = len([a for a in alerts if a.get("type") == "WARNING"])

            network_analysis = {
                "status": "analyzed",
                "nodes_analyzed": node_count,
                "healthy_nodes": healthy_nodes,
                "health_score": round(avg_health, 1),
                "sync_progress": round(avg_sync, 1),
                "block_consistency": summary.get("consistent", False),
                "block_difference": summary.get("block_difference", 0),
                "alerts": {
                    "critical": critical_alerts,
                    "warning": warning_alerts,
                    "total": len(alerts)
                },
                "highest_block": summary.get("highest_block", 0),
                "lowest_block": summary.get("lowest_block", 0)
            }

            # Add reference comparison if available
            if "reference" in results:
                ref = results["reference"]
                network_analysis["external_reference"] = {
                    "reference_block": ref.get("external_block", 0),
                    "local_difference": ref.get("local_max_diff", 0),
                    "consistent": ref.get("reference_consistent", False)
                }

            # Add reorganization check
            if "reorg_check" in results:
                network_analysis["reorganization_check"] = results["reorg_check"]

            self.report_data["network_analysis"][network] = network_analysis

            # Update totals
            total_nodes += node_count
            total_healthy += healthy_nodes
            total_alerts += len(alerts)

        # Store node details
        self.report_data["node_analysis"] = {}
        for network, results in network_results.items():
            if "nodes" in results:
                for node_name, node_data in results["nodes"].items():
                    node_key = f"{network}_{node_name}"
                    self.report_data["node_analysis"][node_key] = {
                        "network": network,
                        "node_type": node_name,
                        "health_score": node_data.get("health_score", 0),
                        "sync_progress": node_data.get("sync_progress", 0),
                        "current_block": node_data.get("current_block", 0),
                        "peer_count": node_data.get("peer_count", 0),
                        "response_time": node_data.get("response_time", 0),
                        "service_status": node_data.get("service_status", "unknown"),
                        "sync_status": node_data.get("sync_status", "unknown"),
                        "issues": node_data.get("issues", []),
                        "lagging": node_data.get("lagging", False),
                        "blocks_behind": node_data.get("blocks_behind", 0),
                        "rpc_responsive": node_data.get("rpc_responsive", False)
                    }

    async def _generate_executive_summary(self):
        """Generate executive summary"""
        network_analysis = self.report_data["network_analysis"]
        node_analysis = self.report_data["node_analysis"]

        total_networks = len(network_analysis)
        healthy_networks = len([n for n in network_analysis.values() if n.get("health_score", 0) > 70])

        total_nodes = len(node_analysis)
        healthy_nodes = len([n for n in node_analysis.values() if n.get("health_score", 0) > 70])
        syncing_nodes = len([n for n in node_analysis.values() if n.get("sync_status") == "syncing"])

        # Calculate overall health
        overall_health = (healthy_nodes / total_nodes * 100) if total_nodes > 0 else 0

        # Identify critical issues
        critical_nodes = [name for name, data in node_analysis.items() if data.get("health_score", 0) < 30]
        lagging_nodes = [name for name, data in node_analysis.items() if data.get("lagging", False)]

        # Generate status
        if overall_health > 90:
            status = "EXCELLENT"
            status_emoji = "🟢"
        elif overall_health > 70:
            status = "GOOD"
            status_emoji = "🟡"
        elif overall_health > 50:
            status = "FAIR"
            status_emoji = "🟠"
        else:
            status = "POOR"
            status_emoji = "🔴"

        self.report_data["executive_summary"] = {
            "overall_status": status,
            "overall_health_score": round(overall_health, 1),
            "total_networks": total_networks,
            "healthy_networks": healthy_networks,
            "total_nodes": total_nodes,
            "healthy_nodes": healthy_nodes,
            "syncing_nodes": syncing_nodes,
            "critical_nodes": len(critical_nodes),
            "lagging_nodes": len(lagging_nodes),
            "critical_issues": critical_nodes[:5],  # Top 5 critical nodes
            "key_metrics": {
                "avg_response_time": self._calculate_avg_response_time(),
                "total_peers": sum(n.get("peer_count", 0) for n in node_analysis.values()),
                "blocks_consistent": len([n for n in network_analysis.values() if n.get("block_consistency", False)])
            }
        }

    def _calculate_avg_response_time(self) -> float:
        """Calculate average response time across all nodes"""
        node_analysis = self.report_data.get("node_analysis", {})
        response_times = [n.get("response_time", 0) for n in node_analysis.values() if n.get("response_time", 0) > 0]
        return sum(response_times) / len(response_times) if response_times else 0.0

    async def _generate_performance_metrics(self):
        """Generate detailed performance metrics"""
        node_analysis = self.report_data.get("node_analysis", {})

        # Health distribution
        health_scores = [n.get("health_score", 0) for n in node_analysis.values()]
        health_distribution = {
            "excellent": len([s for s in health_scores if s > 90]),
            "good": len([s for s in health_scores if 70 < s <= 90]),
            "fair": len([s for s in health_scores if 50 < s <= 70]),
            "poor": len([s for s in health_scores if s <= 50])
        }

        # Sync progress distribution
        sync_scores = [n.get("sync_progress", 0) for n in node_analysis.values()]
        sync_distribution = {
            "fully_synced": len([s for s in sync_scores if s >= 99.5]),
            "nearly_synced": len([s for s in sync_scores if 95 <= s < 99.5]),
            "good_progress": len([s for s in sync_scores if 70 <= s < 95]),
            "early_stage": len([s for s in sync_scores if s < 70])
        }

        # Response time analysis
        response_times = [n.get("response_time", 0) for n in node_analysis.values() if n.get("response_time", 0) > 0]
        response_time_stats = {
            "min": min(response_times) if response_times else 0,
            "max": max(response_times) if response_times else 0,
            "avg": sum(response_times) / len(response_times) if response_times else 0,
            "median": sorted(response_times)[len(response_times)//2] if response_times else 0
        }

        # Network connectivity
        peer_counts = [n.get("peer_count", 0) for n in node_analysis.values()]
        connectivity_stats = {
            "total_peers": sum(peer_counts),
            "avg_peers_per_node": sum(peer_counts) / len(peer_counts) if peer_counts else 0,
            "nodes_with_low_peers": len([p for p in peer_counts if p < 10]),
            "nodes_with_good_peers": len([p for p in peer_counts if p >= 25])
        }

        self.report_data["performance_metrics"] = {
            "health_distribution": health_distribution,
            "sync_distribution": sync_distribution,
            "response_time_stats": {k: round(v, 3) for k, v in response_time_stats.items()},
            "connectivity_stats": connectivity_stats,
            "issue_analysis": self._analyze_issues(node_analysis)
        }

    def _analyze_issues(self, node_analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze common issues across nodes"""
        all_issues = []
        for node_data in node_analysis.values():
            all_issues.extend(node_data.get("issues", []))

        # Categorize issues
        issue_categories = {
            "service_issues": [],
            "rpc_issues": [],
            "connectivity_issues": [],
            "resource_issues": [],
            "sync_issues": [],
            "other_issues": []
        }

        for issue in all_issues:
            issue_lower = issue.lower()
            if "service" in issue_lower or "running" in issue_lower:
                issue_categories["service_issues"].append(issue)
            elif "rpc" in issue_lower or "responding" in issue_lower:
                issue_categories["rpc_issues"].append(issue)
            elif "peer" in issue_lower or "connectivity" in issue_lower:
                issue_categories["connectivity_issues"].append(issue)
            elif "memory" in issue_lower or "cpu" in issue_lower or "resource" in issue_lower:
                issue_categories["resource_issues"].append(issue)
            elif "sync" in issue_lower:
                issue_categories["sync_issues"].append(issue)
            else:
                issue_categories["other_issues"].append(issue)

        return {k: len(v) for k, v in issue_categories.items()}

    async def _generate_recommendations(self):
        """Generate actionable recommendations"""
        recommendations = []
        executive_summary = self.report_data.get("executive_summary", {})
        performance_metrics = self.report_data.get("performance_metrics", {})
        node_analysis = self.report_data.get("node_analysis", {})

        # Health-based recommendations
        overall_health = executive_summary.get("overall_health_score", 0)
        if overall_health < 70:
            recommendations.append({
                "priority": "HIGH",
                "category": "System Health",
                "issue": f"Overall system health is {overall_health:.1f}%",
                "recommendation": "Immediate attention required. Check critical nodes and address service failures.",
                "affected_nodes": executive_summary.get("critical_issues", [])
            })

        # Node-specific recommendations
        critical_nodes = [name for name, data in node_analysis.items() if data.get("health_score", 0) < 30]
        if critical_nodes:
            recommendations.append({
                "priority": "CRITICAL",
                "category": "Node Health",
                "issue": f"{len(critical_nodes)} critical nodes detected",
                "recommendation": "Restart critical services and investigate logs for root cause.",
                "affected_nodes": critical_nodes
            })

        # Sync-based recommendations
        lagging_nodes = [name for name, data in node_analysis.items() if data.get("lagging", False)]
        if lagging_nodes:
            recommendations.append({
                "priority": "HIGH",
                "category": "Synchronization",
                "issue": f"{len(lagging_nodes)} nodes are lagging behind",
                "recommendation": "Check network connectivity and peer configuration for lagging nodes.",
                "affected_nodes": lagging_nodes
            })

        # Performance recommendations
        response_time_avg = performance_metrics.get("response_time_stats", {}).get("avg", 0)
        if response_time_avg > 2.0:
            recommendations.append({
                "priority": "MEDIUM",
                "category": "Performance",
                "issue": f"Average response time is {response_time_avg:.2f}s",
                "recommendation": "Optimize node configuration and check system resources."
            })

        # Connectivity recommendations
        connectivity_stats = performance_metrics.get("connectivity_stats", {})
        low_peer_nodes = connectivity_stats.get("nodes_with_low_peers", 0)
        if low_peer_nodes > 0:
            recommendations.append({
                "priority": "MEDIUM",
                "category": "Network Connectivity",
                "issue": f"{low_peer_nodes} nodes have low peer count",
                "recommendation": "Review network configuration and firewall settings."
            })

        # Resource recommendations
        issue_analysis = performance_metrics.get("issue_analysis", {})
        if issue_analysis.get("resource_issues", 0) > 0:
            recommendations.append({
                "priority": "MEDIUM",
                "category": "Resource Management",
                "issue": f"{issue_analysis.get('resource_issues', 0)} resource-related issues",
                "recommendation": "Monitor CPU and memory usage, consider upgrading hardware if needed."
            })

        # Proactive recommendations
        if overall_health > 90:
            recommendations.append({
                "priority": "LOW",
                "category": "Maintenance",
                "issue": "System is operating optimally",
                "recommendation": "Continue regular monitoring and schedule routine maintenance.",
                "affected_nodes": []
            })

        self.report_data["recommendations"] = recommendations

    async def _generate_appendix(self, verifier: BlockchainSyncVerifier):
        """Generate appendix with technical details"""
        self.report_data["appendix"] = {
            "configuration": {
                "networks_monitored": verifier.config.networks,
                "node_types_monitored": verifier.config.node_types,
                "tolerance_blocks": verifier.config.tolerance_blocks,
                "max_response_time": verifier.config.max_response_time,
                "alert_thresholds": verifier.config.alert_thresholds
            },
            "technical_notes": {
                "verification_method": "Cross-node consistency validation",
                "data_sources": ["Local RPC endpoints", "External reference APIs"],
                "metrics_collected": ["Sync status", "Health score", "Peer count", "Response time", "Resource usage"]
            }
        }

    async def _include_historical_data(self):
        """Include historical data if available"""
        # This would typically load from a database or log files
        # For now, include placeholder
        self.report_data["historical_data"] = {
            "note": "Historical data integration would be implemented here",
            "suggested_sources": ["Prometheus metrics", "Log files", "Previous reports"]
        }

    async def _save_report(self, output_file: str):
        """Save report to file"""
        try:
            Path(output_file).parent.mkdir(parents=True, exist_ok=True)
            with open(output_file, 'w') as f:
                json.dump(self.report_data, f, indent=2)
        except Exception as e:
            print(f"❌ Failed to save report: {e}")
            raise

    def print_summary(self):
        """Print report summary to console"""
        executive_summary = self.report_data.get("executive_summary", {})
        recommendations = self.report_data.get("recommendations", [])

        print("\n" + "=" * 80)
        print("📊 VERIFICATION REPORT SUMMARY")
        print("=" * 80)

        # Overall status
        status = executive_summary.get("overall_status", "UNKNOWN")
        health = executive_summary.get("overall_health_score", 0)
        status_emoji = {"EXCELLENT": "🟢", "GOOD": "🟡", "FAIR": "🟠", "POOR": "🔴"}.get(status, "❓")

        print(f"{status_emoji} Overall Status: {status} (Health: {health:.1f}%)")
        print(f"📡 Networks: {executive_summary.get('healthy_networks', 0)}/{executive_summary.get('total_networks', 0)} healthy")
        print(f"🖥️  Nodes: {executive_summary.get('healthy_nodes', 0)}/{executive_summary.get('total_nodes', 0)} healthy")
        print(f"⚠️  Critical Issues: {executive_summary.get('critical_nodes', 0)}")
        print(f"📈 Key Metrics: Avg Response: {executive_summary.get('key_metrics', {}).get('avg_response_time', 0):.3f}s")

        # Top recommendations
        if recommendations:
            print(f"\n🎯 Top Recommendations:")
            for i, rec in enumerate(recommendations[:3], 1):
                priority_emoji = {"CRITICAL": "🚨", "HIGH": "⚠️", "MEDIUM": "⚡", "LOW": "💡"}.get(rec.get("priority"), "📝")
                print(f"   {i}. {priority_emoji} {rec.get('recommendation', 'No recommendation')}")

async def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Generate comprehensive blockchain verification report")
    parser.add_argument("--networks", nargs="+", choices=["mainnet", "sepolia", "holesky"],
                       default=["mainnet"], help="Networks to analyze")
    parser.add_argument("--output", help="Output file path")
    parser.add_argument("--include-historical", action="store_true", help="Include historical data")
    parser.add_argument("--verification-level", choices=["basic", "standard", "comprehensive", "forensic"],
                       default="standard", help="Verification depth")
    parser.add_argument("--config", default="/data/blockchain/nodes/sync_verifier.conf",
                       help="Configuration file path")

    args = parser.parse_args()

    generator = VerificationReportGenerator(args.config)
    output_file = await generator.generate_comprehensive_report(
        networks=args.networks,
        output_file=args.output,
        include_historical=args.include_historical,
        verification_level=args.verification_level
    )

    # Print summary
    generator.print_summary()
    print(f"\n📄 Full report available at: {output_file}")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n👋 Report generation cancelled")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)