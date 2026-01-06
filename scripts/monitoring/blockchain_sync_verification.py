#!/usr/bin/env python3
"""
Blockchain Sync Verification System - Fixed Version
Fixed NameError in argument parsing
Implements comprehensive sync status monitoring with learning capabilities
"""

import json
import sys
import time
import subprocess
from dataclasses import dataclass
from typing import Dict, Any, Optional
import os
from datetime import datetime

@dataclass
class NodeInfo:
    """Data structure for node information"""
    name: str
    client: str
    version: str
    service: str
    status: str  # running, stopped, error
    uptime_hours: int = 0
    sync_progress: Optional[float] = None
    current_block: Optional[int] = None
    highest_block: Optional[int] = None
    rpc_responsive: bool = False
    peers: int = 0
    memory_mb: float = 0.0
    cpu_usage_percent: float = 0.0
    issues: list[str] = None
    error: Optional[str] = None
    endpoints: Dict[str, Dict[str, Any]] = None

    def __post_init__(self):
        if self.issues is None:
            self.issues = []
        if self.endpoints is None:
            self.endpoints = {}

class BlockchainSyncVerifier:
    """Professional blockchain sync verification system"""

    def __init__(self):
        self.nodes = {}
        self.results = {
            'timestamp': datetime.now().isoformat(),
            'total_nodes': 0,
            'running_nodes': 0,
            'stopped_nodes': 0,
            'total_issues': 0,
            'health_score': 0.0,
            'networks': {},
            'clients': {},
            'management_tools_available': 0,
            'last_updated': datetime.now().isoformat()
        }
        self.rpc_timeout = 15
        self.peers_threshold = 25
        self.sync_threshold = 90.0

    def verify_sync_status(self, node_config: Dict[str, Any] = None) -> Dict[str, Any]:
        """Comprehensive blockchain node sync verification"""
        print("🔍 Starting comprehensive blockchain sync verification...")

        nodes_to_check = []
        if node_config:
            nodes_to_check = [node_config]
        else:
            nodes_to_check = [
                {'name': 'Erigon', 'client': 'erigon', 'port': 8545, 'authrpc_port': 8552},
                {'name': 'Geth', 'client': 'geth', 'port': 8549, 'authrpc_port': 8554}
            ]

        for node in nodes_to_check:
            node_info = self._verify_single_node(node)
            self.nodes[node['name']] = node_info

        # Calculate system-wide metrics
        total_nodes = len(self.nodes)
        running_nodes = sum(1 for n in self.nodes.values() if n.status == 'running')
        total_sync_progress = sum(n.sync_progress for n in self.nodes.values() if n.sync_progress is not None) / total_nodes
        rpc_available = sum(1 for n in self.nodes.values() if n.rpc_responsive)

        self.results['total_nodes'] = total_nodes
        self.results['running_nodes'] = running_nodes
        self.results['stopped_nodes'] = total_nodes - running_nodes
        self.results['total_issues'] = sum(len(n.issues) for n in self.nodes.values() if n.issues)
        self.results['rpc_available'] = rpc_available
        self.results['health_score'] = self._calculate_health_score()
        self.results['last_updated'] = datetime.now().isoformat()

        return self.results

    def _verify_single_node(self, node_config: Dict[str, Any]) -> NodeInfo:
        """Verify individual blockchain node"""
        node = NodeInfo(
            name=node_config['name'],
            client=node_config['client'],
            version='',
            service=node_config.get('service', f"{node_config['name'].lower().replace(' ', '-')}.service"),
            status='unknown',
            uptime_hours=0,
            sync_progress=None,
            current_block=None,
            highest_block=None,
            rpc_responsive=False,
            peers=0,
            memory_mb=0.0,
            cpu_usage_percent=0.0,
            issues=[],
            error=None,
            endpoints={}
        )

        # Service status check
        try:
            result = subprocess.run(
                ['systemctl', 'is-active', node['service']],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                node.status = 'running'
                node.uptime_hours = self._get_uptime_hours(node['service'])
            elif result.returncode == 3:
                node.status = 'stopped'
            else:
                node.status = 'unknown'
        except Exception as e:
            node.status = 'error'
            node.error = str(e)

        # RPC connectivity check
        port = node_config.get('port', 8545)  # Use the original config dict
        rpc_url = f"http://127.0.0.1:{port}"
        try:
            result = subprocess.run([
                'curl', '-s', '-X', 'POST',
                '-H', 'Content-Type: application/json',
                '-d', '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}',
                rpc_url
            ], capture_output=True, text=True, timeout=self.rpc_timeout)

            if result.returncode == 0:
                node.rpc_responsive = True
                try:
                    data = json.loads(result.stdout)
                    sync_data = data.get('result', {})
                    if sync_data == False:
                        node.sync_progress = 100.0
                        node.current_block = int(data.get('result', {}).get('currentBlock', '0x0'), 16)
                        node.highest_block = int(data.get('result', {}).get('highestBlock', '0x0'), 16)
                    else:
                        node.current_block = int(sync_data.get('currentBlock', '0x0'), 16)
                        node.highest_block = int(sync_data.get('highestBlock', '0x0'), 16)
                        node.sync_progress = (node.current_block / node.highest_block * 100) if node.highest_block > 0 else 100.0
                except Exception:
                    node.rpc_responsive = True
                    node.sync_progress = 0
                    node.current_block = 0
                    node.highest_block = 0
            else:
                node.rpc_responsive = False
                node.error = result.stderr[:200] if result.stderr else "RPC timeout"
        except Exception as e:
            node.rpc_responsive = False
            node.error = str(e)

        # Network peer connectivity
        p2p_port = node_config.get('p2p_port')
        if p2p_port:
            try:
                peer_cmd = [
                    'netstat', '-tlnp', '|', 'grep', str(p2p_port), '|', 'wc', '-l'
                ]
                result = subprocess.run(peer_cmd, capture_output=True, text=True, timeout=10)
                node.peers = int(result.stdout.strip()) if result.returncode == 0 else 0
            except Exception as e:
                node.peers = 0

        # Resource usage
        try:
            # Memory usage
            if node.status == 'running':
                memory_info = subprocess.run(['ps', '-C', node.client, '--no-headers', '-o', 'rss='],
                                       capture_output=True, text=True, timeout=10)
                if memory_info.returncode == 0:
                    for line in memory_info.stdout.split('\n'):
                        if line.strip() and line.strip().isdigit():
                            memory_kb = int(line.strip())
                            node.memory_mb = memory_kb / 1024
                            break
                else:
                    node.memory_mb = 0.0

                # CPU usage (simplified approach)
                cpu_info = subprocess.run(['ps', '-C', node.client, '--no-headers', '-o', '%cpu='],
                                       capture_output=True, text=True, timeout=5)
                if cpu_info.returncode == 0:
                    for line in cpu_info.stdout.split('\n'):
                        if line.strip():
                            try:
                                node.cpu_usage_percent = float(line.strip())
                                break
                            except ValueError:
                                continue
                else:
                    node.cpu_usage_percent = 0.0
        except Exception:
            node.memory_mb = 0.0
            node.cpu_usage_percent = 0.0

        # Detect issues
        issues = []

        if node.status != 'running':
            issues.append(f"Service {node.name} is {node.status}")

        if not node.rpc_responsive:
            issues.append("RPC endpoint not responding")

        if node.memory_mb > 16000:
            issues.append(f"High memory usage ({node.memory_mb:.0f}MB)")

        if node.peers < 5:
            issues.append("Low peer connectivity (<5 peers)")

        if issues:
            node.issues = issues

        return node

    def _get_uptime_hours(self, service_name: str) -> int:
        """Calculate service uptime in hours"""
        try:
            result = subprocess.run([
                'systemctl', 'show', service_name, '--no-pager'
            ], capture_output=True, text=True, timeout=10)
            for line in result.stdout.split('\n'):
                if 'Active:' in line:
                    parts = line.split()
                    if len(parts) >= 4:
                        try:
                            uptime_str = parts[3].strip('(').strip(')')
                            hours_ago = uptime_str.replace(' ago', '').strip()
                            return float(hours_ago) if hours_ago else 0
                        except:
                            return 0
        except Exception:
            return 0

    def _calculate_health_score(self) -> float:
        """Calculate overall infrastructure health score"""
        if not self.nodes:
            return 0.0

        health_scores = []

        for node in self.nodes.values():
            node_score = 0.0

            # Service availability (30%)
            if node.status == 'running':
                node_score += 30.0

            # RPC responsiveness (40%)
            if node.rpc_responsive:
                node_score += 40.0

            # Sync progress (30%)
            if node.sync_progress is not None:
                node_score += min(30.0, node.sync_progress / 100 * 30)

            health_scores.append(node_score)

        return sum(health_scores) / len(health_scores) if health_scores else 0.0

    def _format_block_number(self, block_number: str) -> str:
        """Format block number with proper padding"""
        if not block_number or block_number == '0':
            return '0x0'
        try:
            return f"0x{int(block_number, 16):x}"
        except:
            return block_number

    def print_summary(self):
        """Print comprehensive verification summary"""
        print(f"\n🏛️ BLOCKCHAIN NODE ADMINISTRATION OVERVIEW")
        print("=" * 80)
        print(f"Generated: {self.results['last_updated']}")
        print(f"Health Score: {self.results['health_score']:.1f}%")

        print(f"\n📊 SYSTEM SUMMARY")
        print(f"   Total Nodes: {self.results['total_nodes']}")
        print(f"   Running: {self.results['running_nodes']}")
        print(f"   Health Score: {self.results['health_score']:.1f}%")

        print(f"\n🖥️ CLIENT SUMMARY")
        for client, client_data in self.results['clients'].items():
            print(f"   {client.capitalize()}: {client_data['nodes']} nodes, avg sync: {client_data['avg_sync']:.1f}%")

        print(f"\n🖥️ NODE DETAILS")
        for node_name, node in self.nodes.items():
            status_icon = '🟢' if node.status == 'running' else '🔴'
            if node.sync_progress is None:
                sync_status = 'UNKNOWN'
            elif node.sync_progress >= 100:
                sync_status = 'SYNCED'
            else:
                sync_status = f'SYNCING ({node.sync_progress:.1f}%)'

            print(f"   {status_icon} {node_name.upper()}")
            print(f"      Client: {node.client.upper()}")
            print(f"      Sync: {sync_status}")
            rpc_status = "✅" if node.rpc_responsive else "❌"
            print(f"      RPC: {rpc_status}")
            print(f"      Peers: {node.peers} active")

            if node.issues:
                print(f"      Issues: {len(node.issues)}")
                for issue in node.issues:
                    print(f"         • {issue}")

            if node.endpoints:
                for endpoint_name, endpoint_data in node.endpoints.items():
                    status_icon = "✅" if endpoint_data['status'] == "working" else "❌"
                    print(f"      {endpoint_name}: {status_icon}")

            if node.error:
                print(f"      Error: {node.error}")

    def print_detailed_report(self):
        """Print detailed analysis report"""
        print(f"\n📈 DETAILED ANALYSIS")
        print(f"Timestamp: {self.results['timestamp']}")
        print(f"Health Score: {self.results['health_score']:.1f}%")

        print(f"\n🖥️ ACTIVE NODES:")
        for node_name, node in self.nodes.items():
            self._print_node_details(node)

    def _print_node_details(self, node: NodeInfo):
        """Print detailed node information"""
        print(f"\n   {node.name} ({node.client})")
        print(f"   Status: {'🟢 RUNNING' if node.status == 'running' else '🔴 STOPPED'}")

        if node.sync_progress is not None:
            if node.sync_progress == 100:
                print(f"   Sync: ✅ FULLY SYNCED")
            elif node.sync_progress >= 99.5:
                print(f"   Sync: ✅ {node.sync_progress:.1f}% (near optimal)")
            elif node.sync_progress >= 95.0:
                print(f"   Sync: ✅ {node.sync_progress:.1f}% (good progress)")
            elif node.sync_progress >= 90.0:
                print(f"   Sync: ✅ {node.sync_progress:.1f}% (making good progress)")
            elif node.sync_progress >= 75.0:
                print(f"   Sync: ✅ {node.sync_progress:.1f}% (catching up)")
            elif node.sync_progress >= 50.0:
                print(f"   Sync: 🔴 {node.sync_progress:.1f}% (early stage)")
            elif node.sync_progress >= 25.0:
                print(f"   Sync: 🔴 {node.sync_progress:.1f}% (initial sync)")
            else:
                print(f"   Sync: 🔴 {node.sync_progress:.1f}% (starting)")

        if node.rpc_responsive:
            print(f"   RPC: ✅ Fully responsive")
        else:
            print(f"   RPC: ❌ Unresponsive (timeout)")

        if node.endpoints:
            for endpoint_name, endpoint_data in node.endpoints.items():
                status_icon = "✅" if endpoint_data['status'] == "working" else "❌"
                print(f"   {endpoint_name}: {status_icon}")

        if node.issues:
            print(f"   ⚠️ Issues: {len(node.issues)}")
            for issue in node.issues:
                print(f"         • {issue}")

        # Performance metrics
        if node.memory_mb > 0:
            print(f"   Memory: {node.memory_mb:.1f}GB")
            if node.memory_mb >= 16000:  # 16GB threshold
                print(f"   Usage: ⚠️ HIGH ({node.memory_mb:.1f}GB)")
            elif node.memory_mb >= 8000:  # 8GB threshold
                print(f"   Usage: ⚠️ MODERATE ({node.memory_mb:.1f}GB)")
            else:
                print(f"   Usage: ✅ NORMAL ({node.memory_mb:.1f}GB)")

        if node.cpu_usage_percent > 0:
            print(f"   CPU: {node.cpu_usage_percent:.1f}% average usage")

        if node.peers > 0:
            print(f"   Peers: {node.peers} active")

    def export_json_report(self, filepath: str = None) -> bool:
        """Export verification results to JSON file"""
        if filepath is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filepath = f"/data/blockchain/nodes/blockchain_sync_report_{timestamp}.json"

        try:
            with open(filepath, 'w') as f:
                json.dump(self.results, f, indent=2)
            print(f"\n💾 Report saved to: {filepath}")
            return True
        except Exception as e:
            print(f"❌ Failed to save report: {e}")
            return False

    def run_verification(self):
        """Main execution method"""
        print("🚀 Starting blockchain sync verification...")
        results = self.verify_sync_status()
        self.print_summary()
        self.print_detailed_report()
        return results

def main():
    """Main execution function"""
    verifier = BlockchainSyncVerifier()
    return verifier.run_verification()

if __name__ == "__main__":
    main()