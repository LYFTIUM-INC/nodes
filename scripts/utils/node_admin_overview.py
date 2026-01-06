#!/usr/bin/env python3
"""
Blockchain Node Administration Overview
Comprehensive analysis and management interface for all blockchain nodes
"""

import os
import sys
import json
import time
import asyncio
import subprocess
import requests
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict

@dataclass
class NodeInfo:
    """Complete node information structure"""
    name: str
    client_type: str
    network: str
    service_status: str
    process_status: str
    version: str
    is_running: bool
    sync_progress: Optional[float]
    current_block: Optional[int]
    highest_block: Optional[int]
    peer_count: int
    memory_usage: float
    cpu_usage: float
    disk_usage: float
    uptime: Optional[str]
    rpc_port: int
    ws_port: int
    p2p_port: int
    data_dir: str
    config_file: str
    service_file: str
    last_updated: str
    issues: List[str]
    management_available: bool

class BlockchainNodeAdmin:
    """Comprehensive blockchain node administration system"""

    def __init__(self):
        self.nodes = []
        self.management_tools = {}
        self._discover_nodes()

    def _discover_nodes(self):
        """Discover all blockchain nodes in the system"""
        print("🔍 Discovering blockchain nodes...")

        # Check for various Ethereum clients
        self._check_geth_nodes()
        self._check_erigon_nodes()
        self._check_lighthouse_nodes()
        self._check_nethermind_nodes()
        self._check_besu_nodes()

        print(f"✅ Found {len(self.nodes)} blockchain nodes")

    def _check_geth_nodes(self):
        """Check for Geth nodes"""
        try:
            # Check for Geth binary
            geth_path = self._find_binary("geth")
            if not geth_path:
                return

            # Check for running Geth processes
            processes = self._get_processes("geth")

            for i, proc in enumerate(processes):
                # Extract data directory from command line
                cmd = proc.get('cmd', '')
                data_dir = self._extract_flag_value(cmd, '--datadir') or '/var/lib/geth'

                # Check systemd service
                service_name = f"geth" if i == 0 else f"geth-{i}"
                service_status = self._get_service_status(service_name)

                # Get version
                version = self._get_client_version("geth")

                # Get RPC status if running
                rpc_status = self._check_rpc_status(8545 + i, "geth")

                node = NodeInfo(
                    name=f"Geth-{i}" if i > 0 else "Geth",
                    client_type="Geth",
                    network=self._detect_network_from_rpc(rpc_status) if rpc_status else "mainnet",
                    service_status=service_status,
                    process_status="running" if proc else "stopped",
                    version=version,
                    is_running=proc is not None,
                    sync_progress=rpc_status.get('sync_progress') if rpc_status else None,
                    current_block=rpc_status.get('current_block') if rpc_status else None,
                    highest_block=rpc_status.get('highest_block') if rpc_status else None,
                    peer_count=rpc_status.get('peer_count', 0) if rpc_status else 0,
                    memory_usage=proc.get('memory_percent', 0) if proc else 0,
                    cpu_usage=proc.get('cpu_percent', 0) if proc else 0,
                    disk_usage=self._get_disk_usage(data_dir),
                    uptime=proc.get('etime', 'N/A') if proc else 'N/A',
                    rpc_port=8545 + i,
                    ws_port=8546 + i,
                    p2p_port=30303 + i,
                    data_dir=data_dir,
                    config_file=f"/etc/geth{'-'+str(i) if i>0 else ''}/config.yaml",
                    service_file=f"/etc/systemd/system/{service_name}.service",
                    last_updated=datetime.now().isoformat(),
                    issues=self._analyze_node_issues(proc, rpc_status, service_status),
                    management_available=self._check_management_tools("geth")
                )

                self.nodes.append(node)

        except Exception as e:
            print(f"⚠️  Error checking Geth nodes: {e}")

    def _check_erigon_nodes(self):
        """Check for Erigon nodes"""
        try:
            erigon_path = self._find_binary("erigon")
            if not erigon_path:
                return

            processes = self._get_processes("erigon")

            for i, proc in enumerate(processes):
                cmd = proc.get('cmd', '')
                data_dir = self._extract_flag_value(cmd, '--datadir') or '/var/lib/erigon'

                service_name = f"erigon" if i == 0 else f"erigon-{i}"
                service_status = self._get_service_status(service_name)

                version = self._get_client_version("erigon")
                rpc_status = self._check_rpc_status(8547 + i, "erigon")

                node = NodeInfo(
                    name=f"Erigon-{i}" if i > 0 else "Erigon",
                    client_type="Erigon",
                    network="mainnet",
                    service_status=service_status,
                    process_status="running" if proc else "stopped",
                    version=version,
                    is_running=proc is not None,
                    sync_progress=rpc_status.get('sync_progress') if rpc_status else None,
                    current_block=rpc_status.get('current_block') if rpc_status else None,
                    highest_block=rpc_status.get('highest_block') if rpc_status else None,
                    peer_count=rpc_status.get('peer_count', 0) if rpc_status else 0,
                    memory_usage=proc.get('memory_percent', 0) if proc else 0,
                    cpu_usage=proc.get('cpu_percent', 0) if proc else 0,
                    disk_usage=self._get_disk_usage(data_dir),
                    uptime=proc.get('etime', 'N/A') if proc else 'N/A',
                    rpc_port=8547 + i,
                    ws_port=8548 + i,
                    p2p_port=30303 + i,
                    data_dir=data_dir,
                    config_file=f"/etc/erigon/config.toml",
                    service_file=f"/etc/systemd/system/{service_name}.service",
                    last_updated=datetime.now().isoformat(),
                    issues=self._analyze_node_issues(proc, rpc_status, service_status),
                    management_available=self._check_management_tools("erigon")
                )

                self.nodes.append(node)

        except Exception as e:
            print(f"⚠️  Error checking Erigon nodes: {e}")

    def _check_lighthouse_nodes(self):
        """Check for Lighthouse consensus nodes"""
        try:
            lighthouse_path = self._find_binary("lighthouse")
            if not lighthouse_path:
                return

            processes = self._get_processes("lighthouse")

            for i, proc in enumerate(processes):
                cmd = proc.get('cmd', '')
                data_dir = self._extract_flag_value(cmd, '--datadir') or '/var/lib/lighthouse'

                service_name = f"lighthouse-beacon" if "beacon" in cmd else f"lighthouse-validator"
                service_status = self._get_service_status(service_name)

                version = self._get_client_version("lighthouse")

                node = NodeInfo(
                    name=service_name,
                    client_type="Lighthouse",
                    network="mainnet",
                    service_status=service_status,
                    process_status="running" if proc else "stopped",
                    version=version,
                    is_running=proc is not None,
                    sync_progress=None,  # Lighthouse metrics available via different endpoints
                    current_block=None,
                    highest_block=None,
                    peer_count=0,
                    memory_usage=proc.get('memory_percent', 0) if proc else 0,
                    cpu_usage=proc.get('cpu_percent', 0) if proc else 0,
                    disk_usage=self._get_disk_usage(data_dir),
                    uptime=proc.get('etime', 'N/A') if proc else 'N/A',
                    rpc_port=5052 if "beacon" in cmd else 5062,
                    ws_port=0,
                    p2p_port=9000 + i,
                    data_dir=data_dir,
                    config_file=f"/etc/lighthouse/{service_name}.yml",
                    service_file=f"/etc/systemd/system/{service_name}.service",
                    last_updated=datetime.now().isoformat(),
                    issues=self._analyze_node_issues(proc, None, service_status),
                    management_available=self._check_management_tools("lighthouse")
                )

                self.nodes.append(node)

        except Exception as e:
            print(f"⚠️  Error checking Lighthouse nodes: {e}")

    def _check_nethermind_nodes(self):
        """Check for Nethermind nodes"""
        try:
            nethermind_path = self._find_binary("Nethermind.Runner")
            if not nethermind_path:
                return

            processes = self._get_processes("Nethermind")

            for i, proc in enumerate(processes):
                service_name = f"nethermind" if i == 0 else f"nethermind-{i}"
                service_status = self._get_service_status(service_name)

                node = NodeInfo(
                    name=service_name,
                    client_type="Nethermind",
                    network="mainnet",
                    service_status=service_status,
                    process_status="running" if proc else "stopped",
                    version="N/A",
                    is_running=proc is not None,
                    sync_progress=None,
                    current_block=None,
                    highest_block=None,
                    peer_count=0,
                    memory_usage=proc.get('memory_percent', 0) if proc else 0,
                    cpu_usage=proc.get('cpu_percent', 0) if proc else 0,
                    disk_usage=0,
                    uptime=proc.get('etime', 'N/A') if proc else 'N/A',
                    rpc_port=8545 + i,
                    ws_port=8546 + i,
                    p2p_port=30303 + i,
                    data_dir="/var/lib/nethermind",
                    config_file="/etc/nethermind/config.cfg",
                    service_file=f"/etc/systemd/system/{service_name}.service",
                    last_updated=datetime.now().isoformat(),
                    issues=self._analyze_node_issues(proc, None, service_status),
                    management_available=False
                )

                self.nodes.append(node)

        except Exception as e:
            print(f"⚠️  Error checking Nethermind nodes: {e}")

    def _check_besu_nodes(self):
        """Check for Besu nodes"""
        try:
            besu_path = self._find_binary("besu")
            if not besu_path:
                return

            processes = self._get_processes("besu")

            for i, proc in enumerate(processes):
                service_name = f"besu" if i == 0 else f"besu-{i}"
                service_status = self._get_service_status(service_name)

                node = NodeInfo(
                    name=service_name,
                    client_type="Besu",
                    network="mainnet",
                    service_status=service_status,
                    process_status="running" if proc else "stopped",
                    version="N/A",
                    is_running=proc is not None,
                    sync_progress=None,
                    current_block=None,
                    highest_block=None,
                    peer_count=0,
                    memory_usage=proc.get('memory_percent', 0) if proc else 0,
                    cpu_usage=proc.get('cpu_percent', 0) if proc else 0,
                    disk_usage=0,
                    uptime=proc.get('etime', 'N/A') if proc else 'N/A',
                    rpc_port=8545 + i,
                    ws_port=8546 + i,
                    p2p_port=30303 + i,
                    data_dir="/var/lib/besu",
                    config_file="/etc/besu/config.toml",
                    service_file=f"/etc/systemd/system/{service_name}.service",
                    last_updated=datetime.now().isoformat(),
                    issues=self._analyze_node_issues(proc, None, service_status),
                    management_available=False
                )

                self.nodes.append(node)

        except Exception as e:
            print(f"⚠️  Error checking Besu nodes: {e}")

    def _find_binary(self, binary_name: str) -> Optional[str]:
        """Find binary in system PATH"""
        try:
            result = subprocess.run(['which', binary_name],
                                  capture_output=True, text=True)
            return result.stdout.strip() if result.returncode == 0 else None
        except:
            return None

    def _get_processes(self, process_name: str) -> List[Dict[str, Any]]:
        """Get processes with detailed information"""
        try:
            result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
            processes = []

            for line in result.stdout.split('\n'):
                if process_name in line and 'grep' not in line:
                    parts = line.split()
                    if len(parts) >= 11:
                        processes.append({
                            'user': parts[1],
                            'pid': parts[2],
                            'cpu_percent': float(parts[2]) if parts[2].replace('.', '').isdigit() else 0,
                            'memory_percent': float(parts[3]) if parts[3].replace('.', '').isdigit() else 0,
                            'memory': parts[5],
                            'etime': parts[9],
                            'cmd': ' '.join(parts[10:])
                        })

            return processes
        except:
            return []

    def _get_service_status(self, service_name: str) -> str:
        """Get systemd service status"""
        try:
            result = subprocess.run(['systemctl', 'is-active', service_name],
                                  capture_output=True, text=True)
            return result.stdout.strip() if result.returncode == 0 else "inactive"
        except:
            return "unknown"

    def _get_client_version(self, client_name: str) -> str:
        """Get client version"""
        try:
            if client_name == "geth":
                result = subprocess.run(['geth', 'version'],
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    for line in result.stdout.split('\n'):
                        if 'Geth' in line and 'version' in line:
                            return line.strip()
            elif client_name == "erigon":
                result = subprocess.run(['erigon', 'version'],
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    return result.stdout.strip()
            elif client_name == "lighthouse":
                result = subprocess.run(['lighthouse', '--version'],
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    return result.stdout.strip()
        except:
            pass
        return "N/A"

    def _check_rpc_status(self, port: int, client_type: str) -> Optional[Dict[str, Any]]:
        """Check RPC status and get node information"""
        try:
            rpc_url = f"http://127.0.0.1:{port}"

            # Test basic connectivity
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_chainId",
                "params": [],
                "id": 1
            }

            response = requests.post(rpc_url, json=payload, timeout=5)
            if response.status_code != 200:
                return None

            data = response.json()
            if "result" not in data:
                return None

            # Get sync status
            sync_payload = {
                "jsonrpc": "2.0",
                "method": "eth_syncing",
                "params": [],
                "id": 2
            }

            sync_response = requests.post(rpc_url, json=sync_payload, timeout=5)
            sync_data = sync_response.json() if sync_response.status_code == 200 else {}

            # Get peer count
            peer_payload = {
                "jsonrpc": "2.0",
                "method": "net_peerCount",
                "params": [],
                "id": 3
            }

            peer_response = requests.post(rpc_url, json=peer_payload, timeout=5)
            peer_data = peer_response.json() if peer_response.status_code == 200 else {}

            # Get current block
            block_payload = {
                "jsonrpc": "2.0",
                "method": "eth_blockNumber",
                "params": [],
                "id": 4
            }

            block_response = requests.post(rpc_url, json=block_payload, timeout=5)
            block_data = block_response.json() if block_response.status_code == 200 else {}

            # Process sync data
            sync_progress = 100.0
            current_block = None
            highest_block = None

            if "result" in sync_data:
                sync_result = sync_data["result"]
                if sync_result and isinstance(sync_result, dict):
                    current_block = int(sync_result.get("currentBlock", "0x0"), 16)
                    highest_block = int(sync_result.get("highestBlock", "0x0"), 16)
                    if highest_block > 0:
                        sync_progress = (current_block / highest_block) * 100
                elif "result" in block_data:
                    current_block = int(block_data["result"], 16)
                    highest_block = current_block

            return {
                "sync_progress": sync_progress,
                "current_block": current_block,
                "highest_block": highest_block,
                "peer_count": int(peer_data.get("result", "0x0"), 16) if "result" in peer_data else 0
            }

        except:
            return None

    def _detect_network_from_rpc(self, rpc_status: Dict[str, Any]) -> str:
        """Detect network from RPC response"""
        # Could implement network detection based on chain ID
        return "mainnet"

    def _extract_flag_value(self, cmd: str, flag: str) -> Optional[str]:
        """Extract flag value from command line"""
        parts = cmd.split()
        for i, part in enumerate(parts):
            if part == flag and i + 1 < len(parts):
                return parts[i + 1]
            elif part.startswith(flag + "="):
                return part.split("=", 1)[1]
        return None

    def _get_disk_usage(self, path: str) -> float:
        """Get disk usage in GB"""
        try:
            import shutil
            if os.path.exists(path):
                usage = shutil.disk_usage(path)
                return usage.used / (1024 ** 3)
        except:
            pass
        return 0.0

    def _analyze_node_issues(self, process: Dict[str, Any], rpc_status: Optional[Dict[str, Any]], service_status: str) -> List[str]:
        """Analyze potential issues with the node"""
        issues = []

        if not process:
            issues.append("Process not running")

        if service_status not in ["active", "running"]:
            issues.append("Service not active")

        if rpc_status is None:
            issues.append("RPC not responding")

        if process:
            if process.get('cpu_percent', 0) > 90:
                issues.append("High CPU usage")

            if process.get('memory_percent', 0) > 80:
                issues.append("High memory usage")

        if rpc_status:
            if rpc_status.get('peer_count', 0) < 3:
                issues.append("Low peer count")

            if rpc_status.get('sync_progress', 100) < 95:
                issues.append("Not fully synced")

        return issues

    def _check_management_tools(self, client_type: str) -> bool:
        """Check if management tools are available"""
        if client_type == "geth":
            return os.path.exists("/data/blockchain/nodes/geth_manager.py")
        elif client_type == "erigon":
            return os.path.exists("/data/blockchain/nodes/blockchain_sync_verification.py")
        return False

    def get_system_overview(self) -> Dict[str, Any]:
        """Get comprehensive system overview"""
        total_nodes = len(self.nodes)
        running_nodes = sum(1 for node in self.nodes if node.is_running)
        total_issues = sum(len(node.issues) for node in self.nodes)

        network_summary = {}
        for node in self.nodes:
            network = node.network
            if network not in network_summary:
                network_summary[network] = {"count": 0, "running": 0}
            network_summary[network]["count"] += 1
            if node.is_running:
                network_summary[network]["running"] += 1

        client_summary = {}
        for node in self.nodes:
            client = node.client_type
            if client not in client_summary:
                client_summary[client] = {"count": 0, "running": 0}
            client_summary[client]["count"] += 1
            if node.is_running:
                client_summary[client]["running"] += 1

        return {
            "total_nodes": total_nodes,
            "running_nodes": running_nodes,
            "stopped_nodes": total_nodes - running_nodes,
            "total_issues": total_issues,
            "health_score": ((running_nodes / total_nodes) * 100) if total_nodes > 0 else 0,
            "networks": network_summary,
            "clients": client_summary,
            "management_tools_available": len([n for n in self.nodes if n.management_available]),
            "last_updated": datetime.now().isoformat()
        }

    def print_overview(self):
        """Print comprehensive overview"""
        overview = self.get_system_overview()

        print("\n" + "="*80)
        print("🏛️  BLOCKCHAIN NODE ADMINISTRATION OVERVIEW")
        print("="*80)

        # System Summary
        print(f"\n📊 SYSTEM SUMMARY")
        print(f"   Total Nodes: {overview['total_nodes']}")
        print(f"   Running: {overview['running_nodes']} ✅")
        print(f"   Stopped: {overview['stopped_nodes']} ❌")
        print(f"   Total Issues: {overview['total_issues']}")
        print(f"   Health Score: {overview['health_score']:.1f}%")
        print(f"   Management Tools: {overview['management_tools_available']}/{overview['total_nodes']} available")

        # Network Summary
        print(f"\n🌐 NETWORK SUMMARY")
        for network, stats in overview['networks'].items():
            status = "✅" if stats['running'] == stats['count'] else "⚠️"
            print(f"   {network.capitalize()}: {stats['running']}/{stats['count']} running {status}")

        # Client Summary
        print(f"\n🔧 CLIENT SUMMARY")
        for client, stats in overview['clients'].items():
            status = "✅" if stats['running'] == stats['count'] else "⚠️"
            print(f"   {client}: {stats['running']}/{stats['count']} running {status}")

        # Detailed Node Information
        print(f"\n🖥️  NODE DETAILS")
        print("-" * 80)
        print(f"{'Node':<15} {'Client':<10} {'Status':<10} {'Sync':<8} {'Peers':<7} {'CPU':<6} {'Mem':<6} {'Issues':<10}")
        print("-" * 80)

        for node in self.nodes:
            status_emoji = "✅" if node.is_running else "❌"
            sync_display = f"{node.sync_progress:.1f}%" if node.sync_progress else "N/A"
            issues_count = len(node.issues)
            issues_display = f"{issues_count} issues" if issues_count > 0 else "OK"

            print(f"{node.name:<15} {node.client_type:<10} {status_emoji:<10} {sync_display:<8} "
                  f"{node.peer_count:<7} {node.cpu_usage:<6.1f} {node.memory_usage:<6.1f} {issues_display:<10}")

        # Issues Summary
        if overview['total_issues'] > 0:
            print(f"\n⚠️  ISSUES SUMMARY")
            for node in self.nodes:
                if node.issues:
                    print(f"   {node.name}:")
                    for issue in node.issues:
                        print(f"     • {issue}")

        # Management Capabilities
        print(f"\n🛠️  MANAGEMENT CAPABILITIES")
        for node in self.nodes:
            if node.management_available:
                print(f"   ✅ {node.name}: Management tools available")
                if node.client_type == "Geth":
                    print(f"      • manage-geth.sh status")
                    print(f"      • manage-geth.sh optimize")
                    print(f"      • manage-geth.sh backup")
            else:
                print(f"   ❌ {node.name}: No management tools")

        print(f"\n📈 PERFORMANCE METRICS")
        total_cpu = sum(node.cpu_usage for node in self.nodes)
        total_memory = sum(node.memory_usage for node in self.nodes)
        total_disk = sum(node.disk_usage for node in self.nodes)

        print(f"   Total CPU Usage: {total_cpu:.1f}%")
        print(f"   Total Memory Usage: {total_memory:.1f}%")
        print(f"   Total Disk Usage: {total_disk:.1f}GB")

        print(f"\n🔄 QUICK ACTIONS")
        print("   • View node logs: journalctl -u <service-name> -f")
        print("   • Restart node: systemctl restart <service-name>")
        print("   • Check status: systemctl status <service-name>")

        if any(node.client_type == "Geth" and node.management_available for node in self.nodes):
            print("   • Manage Geth: /data/blockchain/nodes/manage_geth.sh <action>")

        print("="*80)
        print(f"Last Updated: {overview['last_updated']}")
        print("="*80)

def main():
    """Main function"""
    print("🚀 Initializing Blockchain Node Administration Overview...")

    admin = BlockchainNodeAdmin()
    admin.print_overview()

    # Save detailed data to file
    detailed_data = {
        "overview": admin.get_system_overview(),
        "nodes": [asdict(node) for node in admin.nodes]
    }

    output_file = "/data/blockchain/nodes/node_admin_report.json"
    with open(output_file, 'w') as f:
        json.dump(detailed_data, f, indent=2, default=str)

    print(f"\n💾 Detailed report saved to: {output_file}")

if __name__ == "__main__":
    main()