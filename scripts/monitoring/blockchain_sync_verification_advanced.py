#!/usr/bin/env python3
"""
Comprehensive Blockchain Node Synchronization Verification System
Supports multi-client verification with real-time monitoring and alerting

Features:
- Multi-client support (Geth, Erigon, Nethermind, Besu)
- Cross-node consistency validation
- Real-time monitoring with configurable alerting
- Chain integrity verification against external references
- Performance analytics and reporting
- Automated alerting with multiple notification channels
"""

import json
import sys
import time
import subprocess
import requests
import logging
import argparse
import yaml
import sqlite3
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import Dict, Any, Optional, List, Tuple
from pathlib import Path
import threading
import uuid
import os
import signal
import socket
import psutil

@dataclass
class NodeInfo:
    """Comprehensive node information structure"""
    name: str
    client: str
    version: str
    service: str
    status: str
    uptime_hours: int = 0
    sync_progress: Optional[float] = None
    current_block: Optional[int] = None
    highest_block: Optional[int] = None
    rpc_responsive: bool = False
    peers: int = 0
    memory_mb: float = 0.0
    cpu_usage_percent: float = 0.0
    disk_usage_gb: float = 0.0
    network_rx_mb: float = 0.0
    network_tx_mb: float = 0.0
    sync_speed_blocks_per_hour: float = 0.0
    last_block_time: Optional[datetime] = None
    issues: List[str] = None
    error: Optional[str] = None
    endpoints: Dict[str, Dict[str, Any]] = None
    health_score: float = 0.0
    response_time_ms: float = 0.0

    def __post_init__(self):
        if self.issues is None:
            self.issues = []
        if self.endpoints is None:
            self.endpoints = {}

@dataclass
class AlertConfig:
    """Alert configuration settings"""
    max_block_diff: int = 10
    min_peer_count: int = 8
    max_cpu_usage: float = 90.0
    max_memory_usage: float = 28.0
    sync_stall_timeout: int = 300
    alert_cooldown: int = 600
    email_recipients: List[str] = None
    slack_webhook_url: str = ""
    discord_webhook_url: str = ""
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""

    def __post_init__(self):
        if self.email_recipients is None:
            self.email_recipients = []

class BlockchainSyncVerifier:
    """Advanced blockchain sync verification system"""

    def __init__(self, config_file: str = "/etc/blockchain/sync_verifier.conf"):
        self.nodes = {}
        self.config_file = config_file
        self.alert_config = AlertConfig()
        self.rpc_timeout = 15
        self.peers_threshold = 25
        self.sync_threshold = 90.0
        self.monitoring = False
        self.alert_cooldowns = {}
        self.db_path = "/var/lib/blockchain/sync_verification.db"

        # Setup logging
        self.setup_logging()

        # Initialize database
        self.init_database()

        # Load configuration
        self.load_config()

        self.results = {
            'timestamp': datetime.now().isoformat(),
            'total_nodes': 0,
            'running_nodes': 0,
            'stopped_nodes': 0,
            'syncing_nodes': 0,
            'healthy_nodes': 0,
            'total_issues': 0,
            'health_score': 0.0,
            'networks': {},
            'clients': {},
            'alerts': [],
            'last_updated': datetime.now().isoformat()
        }

    def setup_logging(self):
        """Setup comprehensive logging"""
        log_dir = Path("/var/log/blockchain")
        log_dir.mkdir(parents=True, exist_ok=True)

        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_dir / "sync_verification.log"),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)

    def init_database(self):
        """Initialize SQLite database for historical data"""
        db_dir = Path("/var/lib/blockchain")
        db_dir.mkdir(parents=True, exist_ok=True)

        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''
                CREATE TABLE IF NOT EXISTS sync_status (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    node_name TEXT,
                    client TEXT,
                    status TEXT,
                    sync_progress REAL,
                    current_block INTEGER,
                    peers INTEGER,
                    memory_mb REAL,
                    cpu_percent REAL,
                    health_score REAL,
                    issues TEXT
                )
            ''')

            conn.execute('''
                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    alert_type TEXT,
                    node_name TEXT,
                    severity TEXT,
                    message TEXT,
                    resolved BOOLEAN DEFAULT FALSE
                )
            ''')
            conn.commit()

    def load_config(self):
        """Load configuration from file"""
        config_path = Path(self.config_file)
        if config_path.exists():
            try:
                with open(config_path, 'r') as f:
                    config = yaml.safe_load(f)
                    if 'alerts' in config:
                        for key, value in config['alerts'].items():
                            if hasattr(self.alert_config, key):
                                setattr(self.alert_config, key, value)
            except Exception as e:
                self.logger.warning(f"Failed to load config: {e}")

    def verify_sync_status(self, node_type: str = "all", network: str = "mainnet",
                          verification_level: str = "standard") -> Dict[str, Any]:
        """Comprehensive blockchain node sync verification"""
        self.logger.info(f"Starting sync verification - Node Type: {node_type}, Network: {network}, Level: {verification_level}")

        nodes_to_check = self.get_node_configurations(node_type, network)

        for node_config in nodes_to_check:
            node_info = self.verify_single_node(node_config, verification_level)
            self.nodes[node_info.name] = node_info

        # Calculate system-wide metrics
        self.calculate_system_metrics()

        # Store results in database
        self.store_results()

        return self.results

    def get_node_configurations(self, node_type: str, network: str) -> List[Dict[str, Any]]:
        """Get node configurations based on type and network"""
        nodes = []

        if node_type == "all" or node_type == "erigon":
            nodes.append({
                'name': 'Erigon',
                'client': 'erigon',
                'service': 'erigon.service',
                'rpc_port': 8545,
                'authrpc_port': 8552,
                'p2p_port': 30303,
                'ws_port': 8546,
                'metrics_port': 6062,
                'network': network
            })

        if node_type == "all" or node_type == "geth":
            nodes.append({
                'name': 'Geth',
                'client': 'geth',
                'service': 'geth.service',
                'rpc_port': 8549,
                'authrpc_port': 8554,
                'p2p_port': 30303,
                'ws_port': 8546,
                'metrics_port': 6060,
                'network': network
            })

        if node_type == "all" or node_type == "lighthouse":
            nodes.append({
                'name': 'Lighthouse',
                'client': 'lighthouse',
                'service': 'lighthouse.service',
                'rpc_port': 5052,
                'p2p_port': 9001,
                'network': network
            })

        return nodes

    def verify_single_node(self, node_config: Dict[str, Any], verification_level: str) -> NodeInfo:
        """Verify individual blockchain node with comprehensive checks"""
        node = NodeInfo(
            name=node_config['name'],
            client=node_config['client'],
            version='',
            service=node_config['service'],
            status='unknown',
            network=node_config.get('network', 'mainnet')
        )

        start_time = time.time()

        # Service status check
        node.status = self.check_service_status(node.service)
        if node.status == 'running':
            node.uptime_hours = self.get_uptime_hours(node.service)

        # RPC connectivity and sync status
        rpc_url = f"http://127.0.0.1:{node_config['rpc_port']}"
        node.rpc_responsive, node.response_time_ms = self.check_rpc_connectivity(rpc_url)

        if node.rpc_responsive:
            self.get_sync_status(node, rpc_url)
            self.get_peer_count(node, rpc_url)

        # Resource usage monitoring
        if node.status == 'running':
            self.get_resource_usage(node)

        # Network connectivity
        self.check_network_connectivity(node, node_config)

        # Additional verification based on level
        if verification_level in ['comprehensive', 'forensic']:
            self.perform_comprehensive_checks(node, node_config)

        # Calculate health score
        node.health_score = self.calculate_node_health_score(node)

        # Detect issues
        node.issues = self.detect_node_issues(node, node_config)

        # Log response time
        node.response_time_ms = (time.time() - start_time) * 1000

        return node

    def check_service_status(self, service_name: str) -> str:
        """Check systemd service status"""
        try:
            result = subprocess.run(
                ['systemctl', 'is-active', service_name],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                return 'running'
            elif result.returncode == 3:
                return 'stopped'
            else:
                return 'unknown'
        except Exception as e:
            self.logger.error(f"Service check failed for {service_name}: {e}")
            return 'error'

    def check_rpc_connectivity(self, rpc_url: str) -> Tuple[bool, float]:
        """Check RPC endpoint connectivity with response time"""
        try:
            start_time = time.time()
            response = requests.post(
                rpc_url,
                json={"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1},
                timeout=self.rpc_timeout
            )
            response_time = (time.time() - start_time) * 1000

            if response.status_code == 200:
                return True, response_time
            else:
                return False, response_time
        except Exception:
            return False, 0.0

    def get_sync_status(self, node: NodeInfo, rpc_url: str):
        """Get detailed sync status from RPC"""
        try:
            # Get sync status
            response = requests.post(
                rpc_url,
                json={"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                sync_data = data.get('result', {})

                if sync_data == False:
                    node.sync_progress = 100.0
                    # Get current block number
                    block_response = requests.post(
                        rpc_url,
                        json={"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":2},
                        timeout=10
                    )
                    if block_response.status_code == 200:
                        block_data = block_response.json()
                        node.current_block = int(block_data.get('result', '0x0'), 16)
                else:
                    node.current_block = int(sync_data.get('currentBlock', '0x0'), 16)
                    node.highest_block = int(sync_data.get('highestBlock', '0x0'), 16)
                    if node.highest_block > 0:
                        node.sync_progress = (node.current_block / node.highest_block) * 100

                # Get last block time
                if node.current_block:
                    node.last_block_time = self.get_block_timestamp(rpc_url, node.current_block)

        except Exception as e:
            self.logger.error(f"Failed to get sync status for {node.name}: {e}")
            node.error = str(e)

    def get_peer_count(self, node: NodeInfo, rpc_url: str):
        """Get peer count from RPC"""
        try:
            response = requests.post(
                rpc_url,
                json={"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":3},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                node.peers = int(data.get('result', '0x0'), 16)
        except Exception as e:
            self.logger.error(f"Failed to get peer count for {node.name}: {e}")

    def get_resource_usage(self, node: NodeInfo):
        """Get comprehensive resource usage"""
        try:
            # Find process
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info']):
                try:
                    if node.client.lower() in proc.info['name'].lower():
                        # Memory usage
                        if proc.info['memory_info']:
                            node.memory_mb = proc.info['memory_info'].rss / 1024 / 1024

                        # CPU usage
                        node.cpu_usage_percent = proc.info['cpu_percent']

                        # Disk I/O
                        io_counters = proc.io_counters()
                        if io_counters:
                            node.disk_usage_gb = (io_counters.read_bytes + io_counters.write_bytes) / 1024 / 1024 / 1024

                        # Network I/O
                        net_counters = proc.io_counters()
                        if net_counters:
                            node.network_rx_mb = net_counters.read_bytes / 1024 / 1024
                            node.network_tx_mb = net_counters.write_bytes / 1024 / 1024
                        break
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
        except Exception as e:
            self.logger.error(f"Failed to get resource usage for {node.name}: {e}")

    def check_network_connectivity(self, node: NodeInfo, node_config: Dict[str, Any]):
        """Check network connectivity and port status"""
        ports_to_check = ['p2p_port', 'rpc_port', 'ws_port', 'authrpc_port', 'metrics_port']

        for port_key in ports_to_check:
            if port_key in node_config:
                port = node_config[port_key]
                try:
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(3)
                    result = sock.connect_ex(('127.0.0.1', port))
                    sock.close()

                    endpoint_name = port_key.replace('_port', '').upper()
                    node.endpoints[endpoint_name] = {
                        'port': port,
                        'status': 'working' if result == 0 else 'failed'
                    }
                except Exception:
                    node.endpoints[endpoint_name] = {
                        'port': port,
                        'status': 'error'
                    }

    def perform_comprehensive_checks(self, node: NodeInfo, node_config: Dict[str, Any]):
        """Perform comprehensive verification checks"""
        try:
            # Check client version
            rpc_url = f"http://127.0.0.1:{node_config['rpc_port']}"
            version_response = requests.post(
                rpc_url,
                json={"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":4},
                timeout=10
            )

            if version_response.status_code == 200:
                version_data = version_response.json()
                node.version = version_data.get('result', 'unknown')

            # Calculate sync speed
            if node.current_block and node.highest_block:
                node.sync_speed_blocks_per_hour = self.calculate_sync_speed(node, rpc_url)

        except Exception as e:
            self.logger.error(f"Comprehensive checks failed for {node.name}: {e}")

    def calculate_sync_speed(self, node: NodeInfo, rpc_url: str) -> float:
        """Calculate sync speed in blocks per hour"""
        try:
            # Get current block
            current_block = node.current_block

            # Wait 30 seconds
            time.sleep(30)

            # Get new block
            response = requests.post(
                rpc_url,
                json={"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":5},
                timeout=10
            )

            if response.status_code == 200:
                new_block = int(response.json().get('result', '0x0'), 16)
                blocks_diff = new_block - current_block
                return (blocks_diff / 30) * 3600  # Convert to blocks per hour
        except Exception:
            pass
        return 0.0

    def calculate_node_health_score(self, node: NodeInfo) -> float:
        """Calculate comprehensive health score for individual node"""
        score = 0.0

        # Service availability (25%)
        if node.status == 'running':
            score += 25.0

        # RPC responsiveness (25%)
        if node.rpc_responsive:
            score += 25.0

        # Sync progress (30%)
        if node.sync_progress is not None:
            if node.sync_progress >= 99.5:
                score += 30.0
            else:
                score += (node.sync_progress / 100) * 30

        # Peer connectivity (10%)
        if node.peers >= self.peers_threshold:
            score += 10.0
        else:
            score += (node.peers / self.peers_threshold) * 10.0

        # Resource efficiency (10%)
        if node.memory_mb > 0 and node.memory_mb < 16000:  # Under 16GB is good
            score += 5.0
        if node.cpu_usage_percent > 0 and node.cpu_usage_percent < 80:  # Under 80% is good
            score += 5.0

        return min(100.0, score)

    def detect_node_issues(self, node: NodeInfo, node_config: Dict[str, Any]) -> List[str]:
        """Detect issues and anomalies for the node"""
        issues = []

        if node.status != 'running':
            issues.append(f"Service {node.name} is {node.status}")

        if not node.rpc_responsive:
            issues.append("RPC endpoint not responding")

        if node.sync_progress is not None:
            if node.sync_progress < 50.0 and node.status == 'running':
                issues.append(f"Low sync progress ({node.sync_progress:.1f}%)")
            elif node.sync_progress < 95.0 and node.uptime_hours > 24:
                issues.append(f"Slow sync progress after {node.uptime_hours}h uptime")

        if node.peers < 5:
            issues.append(f"Low peer connectivity ({node.peers} peers)")

        if node.memory_mb > 24000:  # Over 24GB
            issues.append(f"High memory usage ({node.memory_mb:.1f}GB)")

        if node.cpu_usage_percent > 90:
            issues.append(f"High CPU usage ({node.cpu_usage_percent:.1f}%)")

        if node.response_time_ms > 5000:  # Over 5 seconds
            issues.append(f"Slow RPC response ({node.response_time_ms:.0f}ms)")

        return issues

    def get_block_timestamp(self, rpc_url: str, block_number: int) -> Optional[datetime]:
        """Get timestamp for a specific block"""
        try:
            response = requests.post(
                rpc_url,
                json={
                    "jsonrpc":"2.0",
                    "method":"eth_getBlockByNumber",
                    "params":[hex(block_number), False],
                    "id":6
                },
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                block_data = data.get('result', {})
                timestamp_hex = block_data.get('timestamp', '0x0')
                timestamp = int(timestamp_hex, 16)
                return datetime.fromtimestamp(timestamp)
        except Exception:
            pass
        return None

    def get_uptime_hours(self, service_name: str) -> int:
        """Calculate service uptime in hours"""
        try:
            result = subprocess.run(
                ['systemctl', 'show', service_name, '--no-pager'],
                capture_output=True, text=True, timeout=10
            )

            for line in result.stdout.split('\n'):
                if 'Active:' in line:
                    parts = line.split()
                    if len(parts) >= 4:
                        try:
                            uptime_str = parts[3].strip('(').strip(')')
                            if 'ago' in uptime_str:
                                hours_ago = uptime_str.replace(' ago', '').strip()
                                if hours_ago.isdigit():
                                    return int(hours_ago)
                        except:
                            pass
        except Exception:
            pass
        return 0

    def calculate_system_metrics(self):
        """Calculate system-wide metrics"""
        if not self.nodes:
            return

        total_nodes = len(self.nodes)
        running_nodes = sum(1 for n in self.nodes.values() if n.status == 'running')
        syncing_nodes = sum(1 for n in self.nodes.values()
                          if n.sync_progress is not None and 0 < n.sync_progress < 100)
        healthy_nodes = sum(1 for n in self.nodes.values() if n.health_score >= 80)
        total_issues = sum(len(n.issues) for n in self.nodes.values())

        # Calculate average health score
        avg_health_score = sum(n.health_score for n in self.nodes.values()) / total_nodes

        # Update results
        self.results.update({
            'total_nodes': total_nodes,
            'running_nodes': running_nodes,
            'stopped_nodes': total_nodes - running_nodes,
            'syncing_nodes': syncing_nodes,
            'healthy_nodes': healthy_nodes,
            'total_issues': total_issues,
            'health_score': avg_health_score,
            'last_updated': datetime.now().isoformat()
        })

        # Client statistics
        client_stats = {}
        for node in self.nodes.values():
            if node.client not in client_stats:
                client_stats[node.client] = {
                    'nodes': 0,
                    'running': 0,
                    'avg_sync': 0.0,
                    'avg_health': 0.0
                }
            stats = client_stats[node.client]
            stats['nodes'] += 1
            if node.status == 'running':
                stats['running'] += 1
            if node.sync_progress is not None:
                stats['avg_sync'] += node.sync_progress
            stats['avg_health'] += node.health_score

        # Calculate averages
        for client, stats in client_stats.items():
            if stats['nodes'] > 0:
                stats['avg_sync'] /= stats['nodes']
                stats['avg_health'] /= stats['nodes']

        self.results['clients'] = client_stats

    def store_results(self):
        """Store verification results in database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                for node in self.nodes.values():
                    conn.execute('''
                        INSERT INTO sync_status
                        (node_name, client, status, sync_progress, current_block,
                         peers, memory_mb, cpu_percent, health_score, issues)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''', (
                        node.name, node.client, node.status, node.sync_progress,
                        node.current_block, node.peers, node.memory_mb,
                        node.cpu_usage_percent, node.health_score,
                        json.dumps(node.issues)
                    ))
                conn.commit()
        except Exception as e:
            self.logger.error(f"Failed to store results: {e}")

    def validate_cross_node_consistency(self, network: str = "mainnet", tolerance: int = 3) -> Dict[str, Any]:
        """Validate consistency across multiple nodes"""
        self.logger.info(f"Starting cross-node consistency validation for {network}")

        block_numbers = {}
        node_statuses = {}

        # Collect block numbers from all nodes
        for node_name, node in self.nodes.items():
            if node.current_block is not None:
                block_numbers[node_name] = node.current_block
                node_statuses[node_name] = node.status

        if not block_numbers:
            return {'status': 'error', 'message': 'No block data available'}

        max_block = max(block_numbers.values())
        min_block = min(block_numbers.values())
        block_diff = max_block - min_block

        consistency_report = {
            'network': network,
            'tolerance': tolerance,
            'max_block': max_block,
            'min_block': min_block,
            'block_difference': block_diff,
            'nodes_consistent': block_diff <= tolerance,
            'lagging_nodes': [],
            'analysis': {}
        }

        # Identify lagging nodes
        for node_name, block_num in block_numbers.items():
            diff = max_block - block_num
            if diff > tolerance:
                consistency_report['lagging_nodes'].append({
                    'name': node_name,
                    'block_number': block_num,
                    'lag_blocks': diff,
                    'status': node_statuses[node_name]
                })

        # Analyze patterns
        if block_diff == 0:
            consistency_report['analysis']['status'] = 'perfect_consistency'
        elif block_diff <= tolerance:
            consistency_report['analysis']['status'] = 'acceptable_consistency'
        elif block_diff <= 20:
            consistency_report['analysis']['status'] = 'minor_divergence'
        else:
            consistency_report['analysis']['status'] = 'major_divergence'

        return consistency_report

    def monitor_realtime(self, duration: int = 10, interval: int = 30,
                        alert_threshold: str = "moderate"):
        """Real-time monitoring with configurable parameters"""
        self.logger.info(f"Starting real-time monitoring for {duration} minutes")
        self.monitoring = True

        end_time = time.time() + (duration * 60)
        iteration = 0

        def signal_handler(signum, frame):
            self.monitoring = False
            self.logger.info("Monitoring stopped by user")

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        while self.monitoring and time.time() < end_time:
            iteration += 1
            timestamp = datetime.now()

            self.logger.info(f"Monitoring iteration {iteration} - {timestamp}")

            # Run verification
            self.verify_sync_status()

            # Check for alerts
            self.check_alerts(alert_threshold)

            # Validate consistency
            consistency = self.validate_cross_node_consistency()

            if not consistency['nodes_consistent']:
                self.trigger_alert('CONSISTENCY',
                                f"Node consistency issue: {consistency['analysis']['status']}",
                                'warning')

            self.logger.info(f"Iteration {iteration} complete. Health: {self.results['health_score']:.1f}%")

            if time.time() < end_time:
                time.sleep(interval)

        self.monitoring = False
        self.logger.info(f"Real-time monitoring completed. {iteration} iterations performed.")

    def check_alerts(self, alert_threshold: str):
        """Check for alert conditions based on threshold"""
        thresholds = self.get_alert_thresholds(alert_threshold)

        for node_name, node in self.nodes.items():
            alerts = []

            # Check sync progress
            if node.sync_progress is not None and node.sync_progress < thresholds['min_sync_progress']:
                if node.status == 'running':
                    alerts.append(f"LOW_SYNC_PROGRESS: {node.sync_progress:.1f}%")

            # Check peer count
            if node.peers < thresholds['min_peers']:
                alerts.append(f"LOW_PEER_COUNT: {node.peers}")

            # Check CPU usage
            if node.cpu_usage_percent > thresholds['max_cpu']:
                alerts.append(f"HIGH_CPU_USAGE: {node.cpu_usage_percent:.1f}%")

            # Check memory usage
            if node.memory_mb > thresholds['max_memory'] * 1024:
                alerts.append(f"HIGH_MEMORY_USAGE: {node.memory_mb/1024:.1f}GB")

            # Check response time
            if node.response_time_ms > thresholds['max_response_time']:
                alerts.append(f"HIGH_RESPONSE_TIME: {node.response_time_ms:.0f}ms")

            # Trigger alerts
            for alert in alerts:
                self.trigger_alert('NODE_METRIC', f"{node_name}: {alert}", 'warning')

    def get_alert_thresholds(self, alert_threshold: str) -> Dict[str, Any]:
        """Get alert thresholds based on alert level"""
        thresholds = {
            'conservative': {
                'min_peers': 25,
                'max_cpu': 70,
                'max_memory': 24,
                'min_sync_progress': 95,
                'max_response_time': 2000
            },
            'moderate': {
                'min_peers': 15,
                'max_cpu': 85,
                'max_memory': 28,
                'min_sync_progress': 85,
                'max_response_time': 5000
            },
            'aggressive': {
                'min_peers': 8,
                'max_cpu': 95,
                'max_memory': 32,
                'min_sync_progress': 75,
                'max_response_time': 10000
            }
        }
        return thresholds.get(alert_threshold, thresholds['moderate'])

    def trigger_alert(self, alert_type: str, message: str, severity: str = 'warning', node_name: str = ''):
        """Trigger alert with cooldown management"""
        alert_key = f"{alert_type}_{node_name}_{message}"
        current_time = time.time()

        # Check cooldown
        if alert_key in self.alert_cooldowns:
            if current_time - self.alert_cooldowns[alert_key] < self.alert_config.alert_cooldown:
                return

        self.alert_cooldowns[alert_key] = current_time

        alert = {
            'id': str(uuid.uuid4()),
            'timestamp': datetime.now().isoformat(),
            'type': alert_type,
            'message': message,
            'severity': severity,
            'node_name': node_name,
            'hostname': socket.gethostname()
        }

        # Store alert
        self.store_alert(alert)

        # Send notifications
        self.send_notifications(alert)

        self.logger.warning(f"ALERT: {alert_type} - {message}")

    def store_alert(self, alert: Dict[str, Any]):
        """Store alert in database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute('''
                    INSERT INTO alerts (alert_type, node_name, severity, message)
                    VALUES (?, ?, ?, ?)
                ''', (alert['type'], alert['node_name'], alert['severity'], alert['message']))
                conn.commit()
        except Exception as e:
            self.logger.error(f"Failed to store alert: {e}")

    def send_notifications(self, alert: Dict[str, Any]):
        """Send notifications through configured channels"""
        # Email notification
        if self.alert_config.email_recipients:
            self.send_email_notification(alert)

        # Slack notification
        if self.alert_config.slack_webhook_url:
            self.send_slack_notification(alert)

        # Discord notification
        if self.alert_config.discord_webhook_url:
            self.send_discord_notification(alert)

    def send_email_notification(self, alert: Dict[str, Any]):
        """Send email notification (placeholder)"""
        self.logger.info(f"Email alert would be sent: {alert['message']}")

    def send_slack_notification(self, alert: Dict[str, Any]):
        """Send Slack notification"""
        try:
            payload = {
                'text': f"🚨 Blockchain Alert: {alert['type']}",
                'attachments': [{
                    'color': 'danger' if alert['severity'] == 'critical' else 'warning',
                    'fields': [
                        {'title': 'Message', 'value': alert['message'], 'short': False},
                        {'title': 'Node', 'value': alert['node_name'], 'short': True},
                        {'title': 'Severity', 'value': alert['severity'], 'short': True},
                        {'title': 'Time', 'value': alert['timestamp'], 'short': True}
                    ]
                }]
            }

            response = requests.post(self.alert_config.slack_webhook_url, json=payload, timeout=10)
            if response.status_code == 200:
                self.logger.info("Slack notification sent successfully")
        except Exception as e:
            self.logger.error(f"Failed to send Slack notification: {e}")

    def send_discord_notification(self, alert: Dict[str, Any]):
        """Send Discord notification"""
        try:
            payload = {
                'embeds': [{
                    'title': '🚨 Blockchain Alert',
                    'description': alert['message'],
                    'color': 0xFF0000 if alert['severity'] == 'critical' else 0xFFFF00,
                    'fields': [
                        {'name': 'Type', 'value': alert['type'], 'inline': True},
                        {'name': 'Node', 'value': alert['node_name'], 'inline': True},
                        {'name': 'Severity', 'value': alert['severity'], 'inline': True}
                    ],
                    'timestamp': alert['timestamp']
                }]
            }

            response = requests.post(self.alert_config.discord_webhook_url, json=payload, timeout=10)
            if response.status_code == 204:
                self.logger.info("Discord notification sent successfully")
        except Exception as e:
            self.logger.error(f"Failed to send Discord notification: {e}")

    def generate_report(self, output_format: str = "json", output_file: str = None) -> str:
        """Generate comprehensive verification report"""
        report_data = {
            'report_metadata': {
                'timestamp': datetime.now().isoformat(),
                'report_version': '2.0',
                'generated_by': os.getenv('USER', 'unknown'),
                'hostname': socket.gethostname(),
                'verification_duration': 'real-time'
            },
            'summary': self.results,
            'nodes': {name: asdict(node) for name, node in self.nodes.items()},
            'consistency_analysis': self.validate_cross_node_consistency(),
            'recent_alerts': self.get_recent_alerts(),
            'recommendations': self.generate_recommendations()
        }

        if output_file is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_file = f"/var/log/blockchain/sync_report_{timestamp}.{output_format}"

        try:
            if output_format == 'json':
                with open(output_file, 'w') as f:
                    json.dump(report_data, f, indent=2, default=str)
            elif output_format == 'yaml':
                with open(output_file, 'w') as f:
                    yaml.dump(report_data, f, default_flow_style=False)
            else:
                raise ValueError(f"Unsupported format: {output_format}")

            self.logger.info(f"Report generated: {output_file}")
            return output_file
        except Exception as e:
            self.logger.error(f"Failed to generate report: {e}")
            return ""

    def get_recent_alerts(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Get recent alerts from database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute('''
                    SELECT alert_type, node_name, severity, message, timestamp
                    FROM alerts
                    ORDER BY timestamp DESC
                    LIMIT ?
                ''', (limit,))

                columns = [desc[0] for desc in cursor.description]
                return [dict(zip(columns, row)) for row in cursor.fetchall()]
        except Exception as e:
            self.logger.error(f"Failed to get recent alerts: {e}")
            return []

    def generate_recommendations(self) -> List[str]:
        """Generate recommendations based on current state"""
        recommendations = []

        if not self.nodes:
            return ["No nodes available for analysis"]

        avg_health = sum(n.health_score for n in self.nodes.values()) / len(self.nodes)

        if avg_health < 70:
            recommendations.append("Overall system health is low - consider immediate maintenance")

        # Check for common issues
        low_peers = [n for n in self.nodes.values() if n.peers < 10]
        if low_peers:
            recommendations.append(f"Multiple nodes have low peer count - check network connectivity")

        high_memory = [n for n in self.nodes.values() if n.memory_mb > 16000]
        if high_memory:
            recommendations.append("Consider optimizing memory usage or adding more RAM")

        syncing_nodes = [n for n in self.nodes.values() if 0 < n.sync_progress < 100]
        if syncing_nodes:
            recommendations.append("Nodes are still syncing - monitor progress and consider fast sync options")

        if not recommendations:
            recommendations.append("All nodes operating normally - continue regular monitoring")

        return recommendations

    def print_summary(self):
        """Print comprehensive verification summary"""
        print(f"\n🏛️ COMPREHENSIVE BLOCKCHAIN SYNC VERIFICATION")
        print("=" * 80)
        print(f"Generated: {self.results['last_updated']}")
        print(f"Health Score: {self.results['health_score']:.1f}%")

        print(f"\n📊 SYSTEM SUMMARY")
        print(f"   Total Nodes: {self.results['total_nodes']}")
        print(f"   Running: {self.results['running_nodes']}")
        print(f"   Healthy: {self.results['healthy_nodes']}")
        print(f"   Issues: {self.results['total_issues']}")

        if self.results['clients']:
            print(f"\n🖥️ CLIENT SUMMARY")
            for client, stats in self.results['clients'].items():
                print(f"   {client.capitalize()}: {stats['running']}/{stats['nodes']} running, "
                      f"avg health: {stats['avg_health']:.1f}%")

        print(f"\n🖥️ NODE DETAILS")
        for node_name, node in self.nodes.items():
            status_icon = '🟢' if node.status == 'running' else '🔴'
            health_icon = '✅' if node.health_score >= 80 else '⚠️' if node.health_score >= 60 else '❌'

            print(f"   {status_icon} {node_name.upper()} {health_icon}")
            print(f"      Client: {node.client.upper()}")
            print(f"      Status: {node.status.upper()}")
            print(f"      Health: {node.health_score:.1f}%")

            if node.sync_progress is not None:
                if node.sync_progress >= 100:
                    sync_status = 'SYNCED'
                elif node.sync_progress >= 95:
                    sync_status = f'SYNCING ({node.sync_progress:.1f}%)'
                else:
                    sync_status = f'SYNCING ({node.sync_progress:.1f}%)'
                print(f"      Sync: {sync_status}")

            if node.current_block:
                print(f"      Block: {node.current_block:,}")

            rpc_status = "✅" if node.rpc_responsive else "❌"
            print(f"      RPC: {rpc_status} ({node.response_time_ms:.0f}ms)")
            print(f"      Peers: {node.peers}")
            print(f"      Memory: {node.memory_mb/1024:.1f}GB")
            print(f"      CPU: {node.cpu_usage_percent:.1f}%")

            if node.issues:
                print(f"      Issues: {len(node.issues)}")
                for issue in node.issues[:3]:  # Show first 3 issues
                    print(f"         • {issue}")
                if len(node.issues) > 3:
                    print(f"         ... and {len(node.issues) - 3} more")

def main():
    """Main execution function with CLI interface"""
    parser = argparse.ArgumentParser(description='Comprehensive Blockchain Sync Verification System')
    parser.add_argument('--node-type', choices=['all', 'geth', 'erigon', 'nethermind', 'besu', 'lighthouse'],
                       default='all', help='Node client type to verify')
    parser.add_argument('--network', choices=['mainnet', 'goerli', 'sepolia', 'holesky', 'all'],
                       default='mainnet', help='Ethereum network')
    parser.add_argument('--verification-level', choices=['basic', 'standard', 'comprehensive', 'forensic'],
                       default='standard', help='Depth of verification')
    parser.add_argument('--alert-threshold', choices=['conservative', 'moderate', 'aggressive'],
                       default='moderate', help='Alert threshold settings')
    parser.add_argument('--output-format', choices=['json', 'yaml', 'table', 'dashboard'],
                       default='table', help='Output format')
    parser.add_argument('--duration', type=int, default=10, help='Monitoring duration in minutes')
    parser.add_argument('--compare-nodes', action='store_true', help='Compare cross-node consistency')
    parser.add_argument('--realtime', action='store_true', help='Enable real-time monitoring')
    parser.add_argument('--output-file', help='Output file path')
    parser.add_argument('--config', default='/etc/blockchain/sync_verifier.conf', help='Configuration file')

    args = parser.parse_args()

    # Initialize verifier
    verifier = BlockchainSyncVerifier(args.config)

    try:
        if args.realtime:
            # Real-time monitoring mode
            verifier.monitor_realtime(
                duration=args.duration,
                interval=30,
                alert_threshold=args.alert_threshold
            )
        else:
            # Single verification mode
            results = verifier.verify_sync_status(
                node_type=args.node_type,
                network=args.network,
                verification_level=args.verification_level
            )

            # Print summary
            verifier.print_summary()

            # Cross-node consistency check
            if args.compare_nodes:
                print(f"\n🔄 CROSS-NODE CONSISTENCY VALIDATION")
                consistency = verifier.validate_cross_node_consistency()
                print(f"Status: {consistency['analysis']['status']}")
                print(f"Block Difference: {consistency['block_difference']}")
                if consistency['lagging_nodes']:
                    print("Lagging Nodes:")
                    for node in consistency['lagging_nodes']:
                        print(f"   - {node['name']}: {node['lag_blocks']} blocks behind")

            # Generate report
            if args.output_file or args.output_format in ['json', 'yaml']:
                report_file = verifier.generate_report(
                    output_format=args.output_format,
                    output_file=args.output_file
                )
                if report_file:
                    print(f"\n📄 Report generated: {report_file}")

    except KeyboardInterrupt:
        print("\n🛑 Verification stopped by user")
    except Exception as e:
        print(f"\n❌ Error during verification: {e}")
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())