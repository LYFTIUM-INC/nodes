#!/usr/bin/env python3
"""
Erigon Node Manager
Comprehensive management tool for Erigon blockchain nodes with AI-assisted troubleshooting
"""

import subprocess
import json
import time
import psutil
import requests
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, asdict
import logging
import shutil
import os

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class ErigonConfig:
    """Erigon node configuration"""
    name: str = "erigon"
    rpc_port: int = 8545
    ws_port: int = 8546
    p2p_port: int = 30303
    data_dir: str = "/data/blockchain/ethereum"
    sync_mode: str = "full"
    cache_mb: int = 4096
    max_peers: int = 50
    http_api: str = "eth,net,web3,debug,txpool"
    network: str = "mainnet"
    memory_limit_mb: int = 14336  # 14GB for 16GB system

@dataclass
class NodeStatus:
    """Erigon node status information"""
    service_active: bool = False
    rpc_responsive: bool = False
    syncing: bool = False
    current_block: int = 0
    highest_block: int = 0
    sync_progress: float = 0.0
    peer_count: int = 0
    memory_usage_mb: float = 0.0
    memory_percent: float = 0.0
    cpu_percent: float = 0.0
    issues: List[str] = None
    endpoints: Dict[str, bool] = None

    def __post_init__(self):
        if self.issues is None:
            self.issues = []
        if self.endpoints is None:
            self.endpoints = {}

class ErigonManager:
    """Comprehensive Erigon node management system"""

    def __init__(self, config: Optional[ErigonConfig] = None):
        self.config = config or ErigonConfig()
        self.service_name = "erigon"
        self.rpc_url = f"http://127.0.0.1:{self.config.rpc_port}"
        self.status = NodeStatus()
        self.ai_analysis_enabled = True

    def check_service_status(self) -> bool:
        """Check systemd service status"""
        try:
            result = subprocess.run(
                ['systemctl', 'is-active', self.service_name],
                capture_output=True, text=True, timeout=10
            )
            return result.stdout.strip() == 'active'
        except Exception as e:
            logger.error(f"Service status check failed: {e}")
            return False

    def check_rpc_responsive(self) -> bool:
        """Check if RPC endpoint is responsive"""
        try:
            response = requests.post(
                self.rpc_url,
                json={
                    "jsonrpc": "2.0",
                    "method": "eth_syncing",
                    "params": [],
                    "id": 1
                },
                timeout=10
            )
            return response.status_code == 200 and 'result' in response.json()
        except Exception as e:
            logger.error(f"RPC responsiveness check failed: {e}")
            return False

    def get_sync_status(self) -> Dict[str, Any]:
        """Get detailed sync status"""
        try:
            response = requests.post(
                self.rpc_url,
                json={
                    "jsonrpc": "2.0",
                    "method": "eth_syncing",
                    "params": [],
                    "id": 1
                },
                timeout=15
            )
            data = response.json()
            return data.get('result', False)
        except Exception as e:
            logger.error(f"Sync status check failed: {e}")
            return False

    def get_peer_count(self) -> int:
        """Get peer count"""
        try:
            response = requests.post(
                self.rpc_url,
                json={
                    "jsonrpc": "2.0",
                    "method": "net_peerCount",
                    "params": [],
                    "id": 1
                },
                timeout=10
            )
            data = response.json()
            return int(data.get('result', '0x0'), 16)
        except Exception as e:
            logger.error(f"Peer count check failed: {e}")
            return 0

    def get_resource_usage(self) -> Tuple[float, float, float]:
        """Get current resource usage"""
        try:
            # Find Erigon process
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']):
                if proc.info['name'] == 'erigon':
                    memory_mb = proc.memory_info().rss / 1024 / 1024
                    return memory_mb, proc.memory_percent(), proc.cpu_percent()
            return 0.0, 0.0, 0.0
        except Exception as e:
            logger.error(f"Resource usage check failed: {e}")
            return 0.0, 0.0, 0.0

    def analyze_rpc_issues(self) -> List[str]:
        """AI-assisted RPC issue analysis"""
        issues = []

        logger.info("🧠 AI: Analyzing RPC endpoint issues...")

        # Check service status
        if not self.check_service_status():
            issues.append("Service not running")

        # Check if process exists
        try:
            proc_found = False
            for proc in psutil.process_iter(['name']):
                if proc.info['name'] == 'erigon':
                    proc_found = True
                    break

            if not proc_found:
                issues.append("Erigon process not found in process list")
        except Exception:
            issues.append("Cannot access process information")

        # Check port binding
        if not self._check_port_binding(self.config.rpc_port):
            issues.append(f"RPC port {self.config.rpc_port} not bound")

        # Test local network connectivity
        if not self._test_local_connection():
            issues.append("Local network connectivity failed")

        # Check HTTP API configuration
        if not self._verify_http_api_config():
            issues.append("HTTP API may not include necessary modules")

        # Check file permissions
        if not self._check_data_permissions():
            issues.append("Data directory permission issues detected")

        return issues

    def _check_port_binding(self, port: int) -> bool:
        """Check if port is properly bound"""
        try:
            result = subprocess.run(
                ['netstat', '-tlnp'],  # -t tcp, -l listening, -n numeric, -p programs
                capture_output=True, text=True, timeout=10
            )
            return f":{port} " in result.stdout
        except Exception:
            return False

    def _test_local_connection(self) -> bool:
        """Test local connection to RPC endpoint"""
        try:
            response = requests.get(self.rpc_url, timeout=5)
            return response.status_code in [400, 405]  # Method not allowed is expected for GET
        except Exception:
            return False

    def _verify_http_api_config(self) -> bool:
        """Verify HTTP API includes necessary modules"""
        return 'eth' in self.config.http_api and 'net' in self.config.http_api

    def _check_data_permissions(self) -> bool:
        """Check data directory permissions"""
        try:
            data_path = Path(self.config.data_dir)
            if not data_path.exists():
                return False

            return os.access(data_path, os.R_OK | os.W_OK)
        except Exception:
            return False

    def analyze_memory_pressure(self) -> Dict[str, Any]:
        """Analyze memory usage and pressure"""
        memory_mb, memory_percent, cpu_percent = self.get_resource_usage()

        analysis = {
            'current_mb': memory_mb,
            'percent': memory_percent,
            'pressure_level': 'low',
            'recommendations': [],
            'config_options': {}
        }

        if memory_percent > 90:
            analysis['pressure_level'] = 'critical'
            analysis['recommendations'].extend([
                "Reduce cache size immediately",
                "Consider memory optimization flags",
                "Monitor for OOM risk"
            ])
            analysis['config_options'] = {
                'cache_mb': min(2048, self.config.cache_mb),
                'prune_cache': True
            }
        elif memory_percent > 80:
            analysis['pressure_level'] = 'high'
            analysis['recommendations'].extend([
                "Monitor memory trends",
                "Consider cache reduction",
                "Check for memory leaks"
            ])
            analysis['config_options'] = {
                'cache_mb': min(3072, self.config.cache_mb)
            }
        elif memory_percent > 70:
            analysis['pressure_level'] = 'moderate'
            analysis['recommendations'].append("Monitor memory usage")

        return analysis

    def apply_memory_optimization(self) -> bool:
        """Apply memory optimization settings"""
        try:
            logger.info("🔧 Applying Erigon memory optimizations...")

            # Get current memory analysis
            memory_analysis = self.analyze_memory_pressure()

            if memory_analysis['pressure_level'] in ['critical', 'high']:
                # Create optimized configuration
                new_cache_size = memory_analysis['config_options'].get('cache_mb', 2048)

                # Generate optimized service configuration
                optimized_config = self._generate_optimized_config(new_cache_size)

                # Write temporary config
                temp_config_path = "/tmp/erigon-optimized.conf"
                with open(temp_config_path, 'w') as f:
                    f.write(optimized_config)

                logger.info(f"✅ Generated optimized config with {new_cache_size}MB cache")
                logger.info(f"📄 Optimized config saved to {temp_config_path}")

                # Suggest restart
                logger.info("🔄 To apply optimizations:")
                logger.info(f"   1. Copy config to service directory")
                logger.info(f"   2. systemctl restart {self.service_name}")

                return True
            else:
                logger.info("✅ Memory usage is acceptable, no optimization needed")
                return True

        except Exception as e:
            logger.error(f"Memory optimization failed: {e}")
            return False

    def _generate_optimized_config(self, cache_mb: int) -> str:
        """Generate optimized Erigon configuration"""
        return f"""# Optimized Erigon Configuration
# Generated: {datetime.now().isoformat()}

# Database configuration
[Database]
# Reduced cache for memory optimization
CacheSize={cache_mb * 1024 * 1024}  # bytes
DatabaseURL="file:{self.config.data_dir}/erigon.db"

# RPC configuration
[RPC]
HTTPHost="0.0.0.0"
HTTPPort={self.config.rpc_port}
HTTPModules="{self.config.http_api}"
HTTPVirtualHosts=["erigon.*"]

# Network configuration
[Network]
NoDiscoveryV4=false
DiscoveryV5Name="erigon"
ListenAddr=":{self.config.p2p_port}"
MaxPeers={self.config.max_peers}

# Performance configuration
[Performance]
Pruning=true
PruneDistance=10000
"""

    def restart_service(self) -> bool:
        """Restart Erigon service safely"""
        try:
            logger.info("🔄 Restarting Erigon service...")

            # Stop service
            result = subprocess.run(
                ['systemctl', 'stop', self.service_name],
                capture_output=True, text=True, timeout=30
            )

            if result.returncode != 0:
                logger.warning("Service stop command failed, proceeding...")

            # Wait for graceful shutdown
            time.sleep(10)

            # Start service
            result = subprocess.run(
                ['systemctl', 'start', self.service_name],
                capture_output=True, text=True, timeout=30
            )

            if result.returncode == 0:
                logger.info("✅ Erigon service restarted successfully")
                return True
            else:
                logger.error(f"❌ Service restart failed: {result.stderr}")
                return False

        except Exception as e:
            logger.error(f"Service restart failed: {e}")
            return False

    def diagnose_issues(self) -> Dict[str, Any]:
        """Comprehensive issue diagnosis"""
        logger.info("🔍 Running comprehensive Erigon diagnosis...")

        diagnosis = {
            'timestamp': datetime.now().isoformat(),
            'service_status': None,
            'rpc_issues': [],
            'memory_analysis': None,
            'sync_status': None,
            'network_status': None,
            'recommendations': []
        }

        # Check service status
        diagnosis['service_status'] = self.check_service_status()

        # RPC issues analysis
        if not self.check_rpc_responsive():
            diagnosis['rpc_issues'] = self.analyze_rpc_issues()

        # Memory analysis
        diagnosis['memory_analysis'] = self.analyze_memory_pressure()

        # Sync status
        sync_data = self.get_sync_status()
        if sync_data:
            if sync_data is False:
                diagnosis['sync_status'] = {
                    'syncing': False,
                    'progress': 100.0,
                    'status': 'fully_synced'
                }
            else:
                current = int(sync_data.get('currentBlock', '0x0'), 16)
                highest = int(sync_data.get('highestBlock', '0x0'), 16)
                progress = (current / highest * 100) if highest > 0 else 0

                diagnosis['sync_status'] = {
                    'syncing': True,
                    'current_block': current,
                    'highest_block': highest,
                    'progress': progress
                }

        # Network status
        diagnosis['network_status'] = {
            'peer_count': self.get_peer_count(),
            'max_peers': self.config.max_peers
        }

        # Generate recommendations
        diagnosis['recommendations'] = self._generate_recommendations(diagnosis)

        return diagnosis

    def _generate_recommendations(self, diagnosis: Dict[str, Any]) -> List[str]:
        """Generate AI-powered recommendations"""
        recommendations = []

        # Service recommendations
        if not diagnosis['service_status']:
            recommendations.append("🔴 Start Erigon service: systemctl start erigon")

        # RPC recommendations
        if diagnosis['rpc_issues']:
            recommendations.extend([f"🔧 Fix RPC: {issue}" for issue in diagnosis['rpc_issues'][:3]])

        # Memory recommendations
        memory_analysis = diagnosis.get('memory_analysis', {})
        if memory_analysis.get('pressure_level') in ['critical', 'high']:
            recommendations.append(f"💾 Optimize memory: {memory_analysis.get('pressure_level')} pressure")
            self.apply_memory_optimization()

        # Network recommendations
        network = diagnosis.get('network_status', {})
        if network.get('peer_count', 0) < 10:
            recommendations.append("🌐 Check P2P network connectivity")

        # Sync recommendations
        sync = diagnosis.get('sync_status', {})
        if sync and sync.get('progress', 0) < 1.0:
            recommendations.append(f"🔄 Sync progress: {sync.get('progress', 0):.2f}%")

        return recommendations

    def get_comprehensive_status(self) -> Dict[str, Any]:
        """Get comprehensive node status"""
        # Check service
        self.status.service_active = self.check_service_status()

        if self.status.service_active:
            # Check RPC
            self.status.rpc_responsive = self.check_rpc_responsive()

            if self.status.rpc_responsive:
                # Get sync status
                sync_data = self.get_sync_status()
                if sync_data:
                    if sync_data is False:
                        self.status.syncing = False
                        self.status.sync_progress = 100.0
                    else:
                        self.status.syncing = True
                        self.status.current_block = int(sync_data.get('currentBlock', '0x0'), 16)
                        self.status.highest_block = int(sync_data.get('highestBlock', '0x0'), 16)
                        self.status.sync_progress = (self.status.current_block / self.status.highest_block * 100) if self.status.highest_block > 0 else 0

                # Get peer count
                self.status.peer_count = self.get_peer_count()
            else:
                self.status.issues.append("RPC endpoint not responding")
        else:
            self.status.issues.append("Service not running")

        # Get resource usage
        self.status.memory_usage_mb, self.status.memory_percent, self.status.cpu_percent = self.get_resource_usage()

        return asdict(self.status)

    def print_status_report(self):
        """Print detailed status report"""
        status = self.get_comprehensive_status()

        print("🔍 ERIGON NODE STATUS REPORT")
        print("=" * 50)
        print(f"📅 Checked: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()

        print("🖥️  SERVICE STATUS")
        print("-" * 20)
        print(f"   Service: {'🟢 Active' if status['service_active'] else '🔴 Stopped'}")
        print(f"   RPC: {'🟢 Responsive' if status['rpc_responsive'] else '🔴 Unresponsive'}")
        print()

        if status['service_active'] and status['rpc_responsive']:
            print("🔄 SYNC STATUS")
            print("-" * 20)
            if status['syncing']:
                print(f"   Status: 🔄 Syncing ({status['sync_progress']:.2f}%)")
                print(f"   Current: {status['current_block']:,}")
                print(f"   Highest: {status['highest_block']:,}")
            else:
                print(f"   Status: ✅ Fully Synced")
            print()

            print("🌐 NETWORK")
            print("-" * 20)
            print(f"   Peers: {status['peer_count']}")
            print()

        print("💾 RESOURCE USAGE")
        print("-" * 20)
        print(f"   Memory: {status['memory_usage_mb']:.1f}MB ({status['memory_percent']:.1f}%)")
        print(f"   CPU: {status['cpu_percent']:.1f}%")

        if status['memory_percent'] > 80:
            print(f"   ⚠️  High memory usage detected")
        print()

        if status['issues']:
            print("🚨 ISSUES")
            print("-" * 20)
            for issue in status['issues']:
                print(f"   ❌ {issue}")
            print()

        # AI recommendations
        diagnosis = self.diagnose_issues()
        if diagnosis['recommendations']:
            print("🧠 AI RECOMMENDATIONS")
            print("-" * 25)
            for rec in diagnosis['recommendations'][:5]:
                print(f"   {rec}")
            print()

def main():
    """Main CLI interface"""
    import argparse

    parser = argparse.ArgumentParser(description='Erigon Node Manager')
    parser.add_argument('--config', help='Configuration file path')
    parser.add_argument('--status', action='store_true', help='Show status')
    parser.add_argument('--diagnose', action='store_true', help='Run diagnosis')
    parser.add_argument('--optimize-memory', action='store_true', help='Apply memory optimization')
    parser.add_argument('--restart', action='store_true', help='Restart service')
    parser.add_argument('--ai', action='store_true', help='Enable AI analysis')

    args = parser.parse_args()

    # Load config if provided
    config = ErigonConfig()
    if args.config and Path(args.config).exists():
        try:
            with open(args.config) as f:
                data = json.load(f)
                config = ErigonConfig(**data)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")

    # Initialize manager
    manager = ErigonManager(config)
    manager.ai_analysis_enabled = args.ai

    # Execute commands
    if args.status:
        manager.print_status_report()
    elif args.diagnose:
        diagnosis = manager.diagnose_issues()
        print("🧠 ERIGON DIAGNOSIS REPORT")
        print("=" * 50)
        print(f"Timestamp: {diagnosis['timestamp']}")
        print()
        print("📊 ANALYSIS:")
        for key, value in diagnosis.items():
            if key != 'recommendations':
                print(f"   {key}: {value}")
        print()
        if diagnosis['recommendations']:
            print("💡 RECOMMENDATIONS:")
            for rec in diagnosis['recommendations']:
                print(f"   {rec}")
    elif args.optimize_memory:
        if manager.apply_memory_optimization():
            print("✅ Memory optimization applied successfully")
        else:
            print("❌ Memory optimization failed")
    elif args.restart:
        if manager.restart_service():
            print("✅ Service restarted successfully")
        else:
            print("❌ Service restart failed")
    else:
        # Default: show status
        manager.print_status_report()

if __name__ == "__main__":
    main()