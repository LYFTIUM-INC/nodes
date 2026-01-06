#!/usr/bin/env python3
"""
Blockchain Sync Verification Command Interface

Main command interface for the blockchain sync verification system.
Implements the /infrastructure:verify_blockchain_sync command functionality.
"""

import asyncio
import json
import sys
import argparse
from datetime import datetime
from pathlib import Path
from typing import List, Optional

# Add the current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

try:
    from blockchain_sync_verification_comprehensive import BlockchainSyncVerifier
    from monitor_sync_realtime import RealTimeMonitor
    from generate_verification_report import VerificationReportGenerator
    from blockchain_sync_quick_check import quick_check
except ImportError as e:
    print(f"❌ Cannot import required modules: {e}")
    sys.exit(1)

class BlockchainSyncCommand:
    """Main command interface for blockchain sync verification"""

    def __init__(self):
        self.config_file = "/data/blockchain/nodes/sync_verifier.conf"

    async def run_verification(self, node_type: str = "all", network: str = "mainnet",
                             verification_level: str = "standard",
                             alert_threshold: str = "moderate",
                             output_format: str = "table",
                             duration: int = 10,
                             compare_nodes: bool = True,
                             export_file: Optional[str] = None):
        """Run blockchain sync verification with specified parameters"""

        print("🔍 BLOCKCHAIN SYNC VERIFICATION SYSTEM")
        print("=" * 80)
        print(f"Node Type: {node_type}")
        print(f"Network: {network}")
        print(f"Verification Level: {verification_level}")
        print(f"Alert Threshold: {alert_threshold}")
        print(f"Output Format: {output_format}")
        print(f"Timestamp: {datetime.now().isoformat()}")
        print("=" * 80)

        if compare_nodes or node_type == "all":
            # Run real-time monitoring
            monitor = RealTimeMonitor(self.config_file)
            await monitor.start_monitoring(
                duration_minutes=duration,
                alert_threshold=alert_threshold,
                output_format=output_format,
                export_interval=5
            )
        else:
            # Single node quick check
            networks = [network] if network != "all" else ["mainnet", "sepolia", "holesky"]
            for net in networks:
                await quick_check(net, output_format)

    async def generate_report(self, networks: List[str] = None,
                            verification_level: str = "comprehensive",
                            output_format: str = "json",
                            export_file: Optional[str] = None):
        """Generate comprehensive verification report"""
        print("📊 Generating Comprehensive Verification Report...")

        generator = VerificationReportGenerator(self.config_file)
        output_file = await generator.generate_comprehensive_report(
            networks=networks,
            output_file=export_file,
            include_historical=True,
            verification_level=verification_level
        )

        generator.print_summary()
        return output_file

    async def verify_sync_status(self, node_type: str = "all", network: str = "mainnet"):
        """Quick sync status verification"""
        if node_type == "all":
            networks = [network] if network != "all" else ["mainnet", "sepolia", "holesky"]
            async with BlockchainSyncVerifier(self.config_file) as verifier:
                results = {}
                for net in networks:
                    try:
                        result = await verifier.verify_cross_node_consistency(net)
                        results[net] = result
                        verifier.display_consistency_results(result, "table")
                    except Exception as e:
                        print(f"❌ Error checking {net}: {e}")
                        results[net] = {"error": str(e)}
                return results
        else:
            # Single node type check
            async with BlockchainSyncVerifier(self.config_file) as verifier:
                status = await verifier.get_node_sync_status(node_type, network)
                print(json.dumps(status.__dict__, indent=2, default=str))
                return status

    async def monitor_chain_integrity(self, network: str = "mainnet", duration: int = 30):
        """Monitor blockchain integrity and detect reorganizations"""
        print(f"🛡️  Starting Chain Integrity Monitoring for {network}")
        print(f"Duration: {duration} minutes")

        monitor = RealTimeMonitor(self.config_file)
        await monitor.start_monitoring(
            duration_minutes=duration,
            alert_threshold="conservative",
            output_format="dashboard",
            export_interval=5
        )

    async def analyze_performance(self, network: str = "mainnet", duration: int = 60):
        """Analyze performance metrics and generate insights"""
        print(f"📈 Starting Performance Analysis for {network}")
        print(f"Duration: {duration} minutes")

        monitor = RealTimeMonitor(self.config_file)
        await monitor.start_monitoring(
            duration_minutes=duration,
            alert_threshold="moderate",
            output_format="dashboard",
            export_interval=2  # More frequent exports for performance analysis
        )

async def main():
    """Main entry point with command line argument parsing"""
    parser = argparse.ArgumentParser(
        description="Comprehensive Blockchain Node Synchronization Verification System",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --node-type all --network mainnet --verification-level comprehensive
  %(prog)s --node-type all --network mainnet --duration 60 --alert-threshold moderate
  %(prog)s --node-type all --network mainnet --compare-nodes --verification-level forensic
  %(prog)s --node-type geth --network mainnet --verification-level comprehensive
  %(prog)s --monitor-integrity --network mainnet --duration 30
  %(prog)s --generate-report --networks mainnet sepolia --verification-level comprehensive
        """
    )

    parser.add_argument("--node-type", choices=["geth", "erigon", "nethermind", "besu", "all"],
                       default="all", help="Node type to check")
    parser.add_argument("--network", choices=["mainnet", "sepolia", "holesky", "all"],
                       default="mainnet", help="Network to check")
    parser.add_argument("--verification-level", choices=["basic", "standard", "comprehensive", "forensic"],
                       default="standard", help="Depth of verification")
    parser.add_argument("--alert-threshold", choices=["conservative", "moderate", "aggressive"],
                       default="moderate", help="Alert threshold settings")
    parser.add_argument("--output-format", choices=["json", "yaml", "table", "dashboard"],
                       default="table", help="Output format")
    parser.add_argument("--duration", type=int, default=10, help="Monitoring duration in minutes")
    parser.add_argument("--compare-nodes", action="store_true", default=True,
                       help="Compare with other nodes for consistency")
    parser.add_argument("--export", help="Export results to file")
    parser.add_argument("--config", default="/data/blockchain/nodes/sync_verifier.conf",
                       help="Configuration file path")

    # Specialized commands
    parser.add_argument("--quick-check", action="store_true", help="Perform quick sync status check")
    parser.add_argument("--monitor-integrity", action="store_true", help="Monitor blockchain integrity")
    parser.add_argument("--analyze-performance", action="store_true", help="Analyze performance metrics")
    parser.add_argument("--generate-report", action="store_true", help="Generate comprehensive report")

    args = parser.parse_args()

    try:
        command = BlockchainSyncCommand()

        if args.quick_check:
            await command.verify_sync_status(args.node_type, args.network)
        elif args.monitor_integrity:
            await command.monitor_chain_integrity(args.network, args.duration)
        elif args.analyze_performance:
            await command.analyze_performance(args.network, args.duration)
        elif args.generate_report:
            networks = [args.network] if args.network != "all" else ["mainnet", "sepolia", "holesky"]
            await command.generate_report(
                networks=networks,
                verification_level=args.verification_level,
                output_format=args.output_format,
                export_file=args.export
            )
        else:
            # Default comprehensive verification
            await command.run_verification(
                node_type=args.node_type,
                network=args.network,
                verification_level=args.verification_level,
                alert_threshold=args.alert_threshold,
                output_format=args.output_format,
                duration=args.duration,
                compare_nodes=args.compare_nodes,
                export_file=args.export
            )

    except KeyboardInterrupt:
        print("\n👋 Verification stopped by user")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())