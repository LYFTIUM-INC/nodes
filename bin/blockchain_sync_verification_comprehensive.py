#!/usr/bin/env python3
"""
Comprehensive Blockchain Node Synchronization Verification System

Monitors sync status across multiple node types (Geth, Erigon, Nethermind, Besu),
validates chain consistency, detects sync issues, and provides detailed analytics.
"""

import json
import time
import logging
import asyncio
import aiohttp
import subprocess
import psutil
import sys
import socket
import struct
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, asdict
from pathlib import Path
import argparse
import yaml
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    import websockets
except ImportError:
    print("Warning: websockets not available, real-time features limited")
    websockets = None

try:
    from web3 import Web3
    from web3.exceptions import TransactionNotFound, BlockNotFound
except ImportError:
    print("Warning: web3 not available, some features will be limited")
    Web3 = None

# Configure logging
log_file = '/tmp/blockchain_logs/blockchain_sync_verification.log'
try:
    # Ensure log directory exists
    Path('/tmp/blockchain_logs').mkdir(exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ]
    )
except Exception as e:
    # Fallback to current directory log file
    log_file = './blockchain_sync_verification.log'
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ]
    )
logger = logging.getLogger(__name__)

@dataclass
class SyncStatus:
    """Data class representing node sync status"""
    node_type: str
    network: str
    service_status: str
    sync_status: str  # "syncing", "fully_synced", "error", "unknown"
    sync_progress: float  # 0-100
    current_block: int
    highest_block: int
    peer_count: int
    cpu_usage: float
    memory_usage: float
    disk_usage: float
    health_score: int  # 0-100
    issues: List[str]
    last_updated: datetime
    rpc_url: str
    ws_url: str
    response_time: float
    block_hash: Optional[str] = None
    chain_id: Optional[int] = None
    ws_connected: bool = False
    subscription_active: bool = False
    last_block_time: Optional[float] = None

@dataclass
class VerificationConfig:
    """Configuration for sync verification"""
    networks: List[str]
    node_types: List[str]
    check_interval: int  # seconds
    alert_thresholds: Dict[str, Any]
    rpc_endpoints: Dict[str, str]
    tolerance_blocks: int
    reference_apis: Dict[str, str]
    max_response_time: float

class BlockchainSyncVerifier:
    """Main blockchain sync verification system"""

    def __init__(self, config_file: str = "/etc/blockchain/sync_verifier.conf"):
        self.config = self.load_config(config_file)
        self.session = None
        self.alert_history = []
        self.verification_history = []

    def load_config(self, config_file: str) -> VerificationConfig:
        """Load configuration from file"""
        default_config = VerificationConfig(
            networks=["mainnet", "sepolia", "holesky"],
            node_types=["geth", "erigon", "nethermind", "besu"],
            check_interval=30,
            alert_thresholds={
                "min_peers": {"conservative": 25, "moderate": 15, "aggressive": 8},
                "max_cpu": {"conservative": 70, "moderate": 85, "aggressive": 95},
                "max_memory": {"conservative": 24, "moderate": 28, "aggressive": 30},
                "min_sync_progress": {"conservative": 90, "moderate": 80, "aggressive": 70},
                "max_response_time": {"conservative": 1.0, "moderate": 2.0, "aggressive": 5.0}
            },
            rpc_endpoints={
                "geth": "http://127.0.0.1:8545",
                "erigon": "http://127.0.0.1:8545",
                "nethermind": "http://127.0.0.1:8545",
                "besu": "http://127.0.0.1:8545"
            },
            tolerance_blocks=5,
            reference_apis={
                "mainnet": "https://api.etherscan.io/api",
                "sepolia": "https://api-sepolia.etherscan.io/api",
                "holesky": "https://api-holesky.etherscan.io/api"
            },
            max_response_time=5.0
        )

        try:
            if Path(config_file).exists():
                with open(config_file, 'r') as f:
                    config_data = yaml.safe_load(f)
                # Update default config with loaded values
                for key, value in config_data.items():
                    if hasattr(default_config, key):
                        setattr(default_config, key, value)
        except Exception as e:
            logger.warning(f"Could not load config file {config_file}: {e}")

        return default_config

    async def __aenter__(self):
        """Async context manager entry"""
        self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=10))
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        if self.session:
            await self.session.close()

    async def get_node_sync_status(self, node_type: str, network: str) -> SyncStatus:
        """Get sync status for a specific node"""
        start_time = time.time()

        # Initialize with default values
        status = SyncStatus(
            node_type=node_type,
            network=network,
            service_status="unknown",
            sync_status="unknown",
            sync_progress=0.0,
            current_block=0,
            highest_block=0,
            peer_count=0,
            cpu_usage=0.0,
            memory_usage=0.0,
            disk_usage=0.0,
            health_score=0,
            issues=[],
            last_updated=datetime.now(),
            rpc_url=self.config.rpc_endpoints.get(node_type, ""),
            ws_url="",
            response_time=0.0
        )

        try:
            # Check service status
            status.service_status = await self.check_service_status(node_type)

            if status.service_status != "active":
                status.issues.append(f"Service not running: {status.service_status}")
                return status

            # Get RPC status
            rpc_url = self.config.rpc_endpoints.get(node_type)
            if not rpc_url:
                status.issues.append("No RPC endpoint configured")
                return status

            status.rpc_url = rpc_url

            # Get sync data via RPC
            sync_data = await self.get_rpc_sync_data(rpc_url)
            if sync_data:
                status.sync_status = sync_data.get("sync_status", "unknown")
                status.current_block = sync_data.get("current_block", 0)
                status.highest_block = sync_data.get("highest_block", 0)
                status.peer_count = sync_data.get("peer_count", 0)
                status.block_hash = sync_data.get("block_hash")
                status.chain_id = sync_data.get("chain_id")

                # Calculate sync progress
                if status.highest_block > 0:
                    status.sync_progress = min(100.0, (status.current_block / status.highest_block) * 100)

            # Get system metrics
            await self.update_system_metrics(node_type, status)

            # Calculate health score
            status.health_score = self.calculate_health_score(status)

            status.response_time = time.time() - start_time

        except Exception as e:
            status.issues.append(f"Error getting status: {str(e)}")
            logger.error(f"Error getting sync status for {node_type}: {e}")

        return status

    async def check_service_status(self, node_type: str) -> str:
        """Check systemd service status"""
        try:
            result = await asyncio.create_subprocess_exec(
                'systemctl', 'is-active', node_type,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            return stdout.decode().strip() if stdout else "inactive"
        except Exception:
            return "unknown"

    async def get_rpc_sync_data(self, rpc_url: str) -> Optional[Dict[str, Any]]:
        """Get sync data via JSON-RPC"""
        if not self.session:
            return None

        try:
            # Get sync status
            sync_payload = {
                "jsonrpc": "2.0",
                "method": "eth_syncing",
                "params": [],
                "id": 1
            }

            async with self.session.post(rpc_url, json=sync_payload) as response:
                if response.status != 200:
                    return None

                data = await response.json()
                sync_result = data.get("result", False)

                sync_data = {
                    "sync_status": "fully_synced" if sync_result is False else "syncing",
                    "current_block": 0,
                    "highest_block": 0
                }

                if sync_result and sync_result is not False:
                    sync_data["current_block"] = int(sync_result.get("currentBlock", "0x0"), 16)
                    sync_data["highest_block"] = int(sync_result.get("highestBlock", "0x0"), 16)
                else:
                    # Get current block if fully synced
                    block_payload = {
                        "jsonrpc": "2.0",
                        "method": "eth_blockNumber",
                        "params": [],
                        "id": 2
                    }

                    async with self.session.post(rpc_url, json=block_payload) as block_response:
                        if block_response.status == 200:
                            block_data = await block_response.json()
                            sync_data["current_block"] = int(block_data.get("result", "0x0"), 16)
                            sync_data["highest_block"] = sync_data["current_block"]

                # Get peer count
                peer_payload = {
                    "jsonrpc": "2.0",
                    "method": "net_peerCount",
                    "params": [],
                    "id": 3
                }

                async with self.session.post(rpc_url, json=peer_payload) as peer_response:
                    if peer_response.status == 200:
                        peer_data = await peer_response.json()
                        sync_data["peer_count"] = int(peer_data.get("result", "0x0"), 16)
                    else:
                        sync_data["peer_count"] = 0

                # Get chain ID
                chain_payload = {
                    "jsonrpc": "2.0",
                    "method": "eth_chainId",
                    "params": [],
                    "id": 4
                }

                async with self.session.post(rpc_url, json=chain_payload) as chain_response:
                    if chain_response.status == 200:
                        chain_data = await chain_response.json()
                        sync_data["chain_id"] = int(chain_data.get("result", "0x0"), 16)

                # Get latest block hash if fully synced
                if sync_data["sync_status"] == "fully_synced":
                    hash_payload = {
                        "jsonrpc": "2.0",
                        "method": "eth_getBlockByNumber",
                        "params": ["latest", False],
                        "id": 5
                    }

                    async with self.session.post(rpc_url, json=hash_payload) as hash_response:
                        if hash_response.status == 200:
                            hash_data = await hash_response.json()
                            result = hash_data.get("result", {})
                            sync_data["block_hash"] = result.get("hash")

                return sync_data

        except Exception as e:
            logger.error(f"Error getting RPC data from {rpc_url}: {e}")
            return None

    async def update_system_metrics(self, node_type: str, status: SyncStatus):
        """Update system metrics for a node"""
        try:
            # Find process
            pid = None
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                try:
                    cmdline = ' '.join(proc.info['cmdline'] or [])
                    if node_type in cmdline.lower() and ('datadir' in cmdline or 'http' in cmdline):
                        pid = proc.info['pid']
                        break
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

            if pid:
                try:
                    process = psutil.Process(pid)
                    status.cpu_usage = process.cpu_percent()
                    status.memory_usage = process.memory_info().rss / 1024 / 1024 / 1024  # GB
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass

            # Get disk usage for data directory
            data_dirs = {
                "geth": "/var/lib/geth",
                "erigon": "/data/blockchain/storage/erigon",
                "nethermind": "/var/lib/nethermind",
                "besu": "/var/lib/besu"
            }

            data_dir = data_dirs.get(node_type)
            if data_dir and Path(data_dir).exists():
                usage = psutil.disk_usage(data_dir)
                status.disk_usage = usage.used / 1024 / 1024 / 1024  # GB

            # Check WebSocket connection
            ws_url = self.config.ws_endpoints.get(node_type)
            if ws_url and websockets:
                status.ws_connected = await self.check_websocket_connection(ws_url)
                if status.ws_connected:
                    try:
                        # Get latest block via WebSocket subscription
                        latest_block = await self.get_latest_block_via_websocket(ws_url)
                        if latest_block:
                            status.last_block_time = latest_block
                            status.current_block = latest_block
                    except Exception as e:
                        logger.warning(f"WebSocket error for {node_type}: {e}")

        except Exception as e:
            logger.error(f"Error updating system metrics for {node_type}: {e}")

    async def check_websocket_connection(self, ws_url: str) -> bool:
        """Check WebSocket connection status"""
        if not websockets or not ws_url:
            return False

        try:
            async with websockets.connect(ws_url) as ws:
                # Send a ping to test connection
                await ws.send(json.dumps({"jsonrpc": "2.0", "method": "net_peerCount", "params": [], "id": 999}))
                response = await ws.recv()
                data = json.loads(response)
                return data.get("result", 0) > 0
        except Exception as e:
            return False

    async def get_latest_block_via_websocket(self, ws_url: str) -> Optional[int]:
        """Get latest block number via WebSocket subscription"""
        if not websockets or not ws_url:
            return None

        try:
            async with websockets.connect(ws_url) as ws:
                # Subscribe to newHeads
                await ws.send(json.dumps({
                    "jsonrpc": "2.0", "method": "eth_subscribe",
                    "params": ["newHeads"], "id": 998
                }))
                response = await ws.recv()
                data = json.loads(response)

                if data.get("method") == "eth_subscription" and data.get("params"):
                    subscription_id = data.get("params", [None])[0]
                    if subscription_id == "newHeads":
                        # Wait for first new block
                        response = await ws.recv()
                        data = json.loads(response)
                        if data.get("method") == "eth_subscription" and data.get("params"):
                            block_data = data.get("params", [None])[0]
                            if isinstance(block_data, dict) and "number" in block_data:
                                return int(block_data.get("number", 0))
                elif isinstance(block_data, str):
                                    return int(block_data, 16) if block_data.startswith("0x") else int(block_data)

        except Exception as e:
            logger.error(f"WebSocket subscription error: {e}")
            return None

    async def monitor_websocket_streams(self, duration_seconds: int = 300):
        """Monitor WebSocket streams for real-time block updates"""
        if not websockets:
            return

        connections = {}

        try:
            # Connect to all WebSocket endpoints
            for node_type in self.config.node_types:
                ws_url = self.config.ws_endpoints.get(node_type)
                if ws_url:
                    try:
                        async with websockets.connect(ws_url) as ws:
                            # Subscribe to newHeads
                            await ws.send(json.dumps({
                                "jsonrpc": "2.0", "method": "eth_subscribe",
                                "params": ["newHeads"], "id": "998"
                            }))
                            connections[node_type] = ws
                    except Exception as e:
                        logger.error(f"Failed to connect to {node_type} WebSocket: {e}")
        except Exception as e:
            logger.error(f"WebSocket connection setup failed: {e}")

        if not connections:
            logger.warning("No WebSocket connections established")
            return

        logger.info(f"Monitoring {len(connections)} WebSocket streams for {duration_seconds}s")

        end_time = time.time() + duration_seconds
        block_updates = {}

        while time.time() < end_time:
            for node_type, ws in connections.items():
                try:
                    response = await ws.recv()
                    data = json.loads(response)

                    if data.get("method") == "eth_subscription":
                        params = data.get("params", [])
                        if params and params[0] == "newHeads":
                            block_data = data.get("params", [None])[0]
                            if isinstance(block_data, dict) and "number" in block_data:
                                block_num = int(block_data.get("number", 0))
                                block_updates[node_type].append({
                                    "timestamp": time.time(),
                                    "block_number": block_num,
                                    "hash": block_data.get("hash", ""),
                                    "parent_hash": block_data.get("parentHash", ""),
                                    "transactions": block_data.get("transactions", [])
                                })
                except Exception as e:
                    logger.error(f"Error processing {node_type} WebSocket data: {e}")
                        except Exception as e:
                        logger.error(f"WebSocket error for {node_type}: {e}")

            # Small delay to prevent overwhelming
            await asyncio.sleep(0.1)

        # Consolidate block updates
        for node_type, updates in block_updates.items():
            if updates:
                latest_block = max(u["block_number"] for u in updates)
                latest_update = max(u["timestamp"] for u in updates)
                print(f"🔄 {node_type} WebSocket received {len(updates)} block updates (Latest: #{latest_block})")

        return block_updates

    def calculate_health_score(self, status: SyncStatus) -> int:
        """Calculate health score (0-100) for a node"""
        score = 100

        # Service status
        if status.service_status != "active":
            score -= 50

        # Sync progress
        if status.sync_status == "syncing":
            score -= min(30, 30 - status.sync_progress * 0.3)
        elif status.sync_status == "error" or status.sync_status == "unknown":
            score -= 40

        # Peer count
        if status.peer_count < 5:
            score -= 20
        elif status.peer_count < 15:
            score -= 10

        # Resource usage
        if status.cpu_usage > 90:
            score -= 15
        elif status.cpu_usage > 80:
            score -= 10

        if status.memory_usage > 30:  # GB
            score -= 15
        elif status.memory_usage > 20:
            score -= 10

        # Response time
        if status.response_time > 5.0:
            score -= 20
        elif status.response_time > 2.0:
            score -= 10

        # Issues
        score -= len(status.issues) * 5

        return max(0, score)

    async def get_reference_block_number(self, network: str) -> int:
        """Get reference block number from external API"""
        if network not in self.config.reference_apis:
            return 0

        try:
            # Use multiple sources for better reliability
            sources = []

            if network == "mainnet":
                sources = [
                    "https://api.etherscan.io/api",
                    "https://ethereum.blockpi.network/v1/rpc/public",
                    "https://rpc.ankr.com/eth"
                ]
            elif network == "sepolia":
                sources = [
                    "https://api-sepolia.etherscan.io/api",
                    "https://ethereum-sepolia.blockpi.network/v1/rpc/public",
                    "https://rpc.sepolia.org"
                ]

            for url in sources:
                try:
                    if "etherscan" in url:
                        params = {
                            "module": "proxy",
                            "action": "eth_blockNumber",
                            "apikey": "YourApiKey"
                        }
                        async with self.session.get(url, params=params) as response:
                            if response.status == 200:
                                data = await response.json()
                                result = data.get("result", "0x0")
                                return int(result, 16) if result.startswith("0x") else int(result)
                    else:
                        # Use RPC endpoint
                        payload = {
                            "jsonrpc": "2.0",
                            "method": "eth_blockNumber",
                            "params": [],
                            "id": 1
                        }
                        async with self.session.post(url, json=payload) as response:
                            if response.status == 200:
                                data = await response.json()
                                result = data.get("result", "0x0")
                                return int(result, 16) if result.startswith("0x") else int(result)
                except:
                    continue

        except Exception as e:
            logger.error(f"Error getting reference block for {network}: {e}")

        return 0

    async def verify_cross_node_consistency(self, network: str) -> Dict[str, Any]:
        """Verify consistency across all nodes"""
        results = {}

        # Get status from all node types
        node_statuses = {}
        tasks = []

        for node_type in self.config.node_types:
            task = asyncio.create_task(self.get_node_sync_status(node_type, network))
            tasks.append((node_type, task))

        # Wait for all tasks to complete
        for node_type, task in tasks:
            try:
                status = await task
                node_statuses[node_type] = status
            except Exception as e:
                logger.error(f"Error getting status for {node_type}: {e}")
                # Create a default error status
                error_status = SyncStatus(
                    node_type=node_type,
                    network=network,
                    service_status="error",
                    sync_status="error",
                    sync_progress=0.0,
                    current_block=0,
                    highest_block=0,
                    peer_count=0,
                    cpu_usage=0.0,
                    memory_usage=0.0,
                    disk_usage=0.0,
                    health_score=0,
                    issues=[f"Failed to get status: {str(e)}"],
                    last_updated=datetime.now(),
                    rpc_url=self.config.rpc_endpoints.get(node_type, ""),
                    ws_url="",
                    response_time=0.0
                )
                node_statuses[node_type] = error_status

        if not node_statuses:
            return {"error": "No node status available"}

        # Find block range
        blocks = [s.current_block for s in node_statuses.values() if s.current_block > 0]
        if not blocks:
            return {"error": "No valid block numbers found"}

        max_block = max(blocks)
        min_block = min(blocks)
        block_diff = max_block - min_block

        results["summary"] = {
            "network": network,
            "total_nodes": len(node_statuses),
            "highest_block": max_block,
            "lowest_block": min_block,
            "block_difference": block_diff,
            "tolerance_blocks": self.config.tolerance_blocks,
            "consistent": block_diff <= self.config.tolerance_blocks,
            "timestamp": datetime.now().isoformat()
        }

        # Analyze each node
        results["nodes"] = {}
        for node_type, status in node_statuses.items():
            block_diff_from_max = max_block - status.current_block
            is_lagging = block_diff_from_max > self.config.tolerance_blocks

            results["nodes"][node_type] = {
                "current_block": status.current_block,
                "health_score": status.health_score,
                "sync_status": status.sync_status,
                "sync_progress": status.sync_progress,
                "peer_count": status.peer_count,
                "rpc_responsive": status.response_time > 0,
                "response_time": status.response_time,
                "lagging": is_lagging,
                "blocks_behind": block_diff_from_max,
                "issues": status.issues,
                "service_status": status.service_status,
                "block_hash": status.block_hash,
                "chain_id": status.chain_id
            }

            if is_lagging:
                results["nodes"][node_type]["recommendation"] = self.get_lagging_node_recommendation(status)

        # Reference comparison
        reference_block = await self.get_reference_block_number(network)
        if reference_block > 0:
            results["reference"] = {
                "external_block": reference_block,
                "local_max_diff": reference_block - max_block,
                "reference_consistent": (reference_block - max_block) <= 10
            }

        # Check for reorganizations by comparing block hashes
        if len([s for s in node_statuses.values() if s.block_hash]) > 1:
            results["reorg_check"] = self.check_reorganizations(node_statuses)

        return results

    def get_lagging_node_recommendation(self, status: SyncStatus) -> str:
        """Get recommendation for lagging node"""
        if status.service_status != "active":
            return "Service not running - check systemctl status"

        if status.peer_count < 5:
            return "Low peer count - check network connectivity"

        if status.cpu_usage > 90:
            return "High CPU usage - check system resources"

        if status.memory_usage > 30:
            return "High memory usage - consider increasing RAM"

        if status.sync_status == "syncing":
            return f"Node is syncing ({status.sync_progress:.1f}%) - monitor progress"

        if "Error getting status" in str(status.issues):
            return "Node is unresponsive - restart service"

        return "Investigate logs for sync issues"

    def check_reorganizations(self, node_statuses: Dict[str, SyncStatus]) -> Dict[str, Any]:
        """Check for blockchain reorganizations by comparing block hashes"""
        hash_comparison = {}
        for node_type, status in node_statuses.items():
            if status.block_hash and status.current_block > 0:
                hash_comparison[node_type] = {
                    "block": status.current_block,
                    "hash": status.block_hash
                }

        if len(hash_comparison) < 2:
            return {"status": "insufficient_data"}

        # Check if hashes match at similar block heights
        hashes = list(set(s["hash"] for s in hash_comparison.values()))
        consistent = len(hashes) == 1

        return {
            "status": "consistent" if consistent else "inconsistent",
            "unique_hashes": len(hashes),
            "node_hashes": hash_comparison
        }

    async def run_real_time_monitoring(self, duration_minutes: int = 10,
                                     alert_threshold: str = "moderate",
                                     output_format: str = "table"):
        """Run real-time monitoring with alerts and WebSocket streams"""
        logger.info(f"Starting enhanced real-time monitoring for {duration_minutes} minutes")
        logger.info(f"Alert threshold: {alert_threshold}")
        logger.info(f"Output format: {output_format}")
        logger.info(f"WebSocket monitoring: {'enabled': websockets is not None}")

        end_time = time.time() + (duration_minutes * 60)
        iteration = 0

        # Start WebSocket monitoring in background
        if websockets:
            ws_task = asyncio.create_task(self.monitor_websocket_streams, duration_minutes * 60)

        while time.time() < end_time:
            iteration += 1
            timestamp = datetime.now()

            print(f"\n{'='*80}")
            print(f"Iteration {iteration} - {timestamp}")
            print(f"{'='*80}")

            # Check all networks
            for network in self.config.networks:
                print(f"\n--- {network.upper()} NETWORK ---")

                try:
                    consistency = await self.verify_cross_node_consistency(network)
                    self.display_consistency_results(consistency, output_format)

                    # Check for alerts
                    alerts = self.check_alerts(consistency, alert_threshold)
                    if alerts:
                        self.handle_alerts(alerts, network, timestamp)

                except Exception as e:
                    logger.error(f"Error checking {network}: {e}")
                    print(f"Error checking {network}: {e}")

            # Sleep until next iteration
            if time.time() < end_time:
                sleep_time = min(30, end_time - time.time())
                time.sleep(sleep_time)

        # Wait for WebSocket monitoring to complete
        if websockets:
            try:
                block_updates = await ws_task
                print(f"\n📡 WebSocket Monitoring Summary:")
                print(f"  Total Updates: {sum(len(updates) for updates in block_updates.values())}")

                # Analyze WebSocket activity
                all_updates = []
                for node_type, updates in block_updates.items():
                    for update in updates:
                        all_updates.append({
                            "node": node_type,
                            "blocks": len(updates),
                            "first_update": update["timestamp"],
                            "last_update": max(u["timestamp"] for u in updates)
                        })

                if all_updates:
                    total_updates = sum(u["blocks"] for u in all_updates)
                    print(f"  Average updates/sec: {total_updates / (duration_minutes * 60):.1f}")

                    # Display node-specific WebSocket activity
                    for node_type, updates in block_updates.items():
                        if updates:
                            print(f"  {node_type}: {len(updates)} updates (Latest: #{updates[-1]['block_number']})")

            except Exception as e:
                logger.error(f"WebSocket monitoring error: {e}")

        print(f"\n{'='*80}")
        print("MONITORING SUMMARY")
        print(f"{'='*80}")
        print(f"Total Iterations: {iteration}")
        print(f"Duration: {duration_minutes} minutes")
        print(f"Total Alerts: {len(self.alert_history)}")

        # Generate network health summary
        for network in self.config.networks:
            try:
                consistency = await self.verify_cross_node_consistency(network)
                network_health = self.calculate_network_health(consistency)
                print(f"\n📊 {network.upper()} NETWORK HEALTH:")
                print(f"  Overall Health: {network_health['overall_health_score']}%")
                print(f"  Sync Efficiency: {network_health['sync_efficiency']}%")
                print(f"  Network Stability: {network_health['network_stability']}%")
                print(f"  Performance Score: {network_health['performance_score']}%")
                print(f"  Reliability: {network_health['reliability_score']}%}")

                if network_health["recommendations"]:
                    print(f"\n💡 RECOMMENDATIONS:")
                    for rec in network_health["recommendations"]:
                        print(f"  {rec}")

            except Exception as e:
                logger.error(f"Error analyzing {network}: {e}")
                print(f"Error analyzing {network}: {e}")

        # Generate summary report
        await self.generate_monitoring_report()

            print(f"\n{'='*80}")
        print("MONITORING SUMMARY")
        print(f"{'='*80}")
        print(f"Total Iterations: {iteration}")
        print(f"Duration: {duration_minutes} minutes")
        print(f"Total Alerts: {len(self.alert_history)}")

        # Generate network health summary
        for network in self.config.networks:
            try:
                consistency = await self.verify_cross_node_consistency(network)
                network_health = self.calculate_network_health(consistency)
                print(f"\n📊 {network.upper()} NETWORK HEALTH:")
                print(f"  Overall Health: {network_health['overall_health_score']}%")
                print(f"  Sync Efficiency: {network_health['sync_efficiency']}%")
                print(f"  Network Stability: {network_health['network_stability']}%")
                print(f"  Performance Score: {network_health['performance_score']}%")
                print(f"  Reliability: {network_health['reliability_score']}%")

                if network_health["recommendations"]:
                    print(f"\n💡 RECOMMENDATIONS:")
                    for rec in network_health["recommendations"]:
                        print(f"  {rec}")
            except Exception as e:
                logger.error(f"Error analyzing {network}: {e}")
                print(f"Error analyzing {network}: {e}")

        # Generate summary report
        await self.generate_monitoring_report()

    def display_consistency_results(self, results: Dict[str, Any], output_format: str):
        """Display consistency results in specified format"""
        if "error" in results:
            print(f"❌ Error: {results['error']}")
            return

        summary = results.get("summary", {})
        nodes = results.get("nodes", {})

        if output_format == "json":
            print(json.dumps(results, indent=2, default=str))
            return

        # Table format
        print(f"Network: {summary.get('network', 'Unknown')}")
        print(f"Total Nodes: {summary.get('total_nodes', 0)}")
        print(f"Block Range: {summary.get('lowest_block', 0):,} - {summary.get('highest_block', 0):,}")
        print(f"Block Difference: {summary.get('block_difference', 0):,}")

        if summary.get('consistent', False):
            print("✅ Nodes are consistent within tolerance")
        else:
            print("⚠️  Nodes show significant divergence")

        if "reference" in results:
            ref = results["reference"]
            print(f"External Reference: {ref.get('external_block', 0):,}")
            print(f"Reference Difference: {ref.get('local_max_diff', 0):,}")

        if "reorg_check" in results:
            reorg = results["reorg_check"]
            if reorg.get("status") == "consistent":
                print("✅ No reorganization detected")
            else:
                print(f"⚠️  Potential reorg: {reorg.get('unique_hashes', 0)} different hashes")

        print(f"\n{'Node':<15} {'Block':<12} {'Health':<8} {'Status':<12} {'Peers':<8} {'Behind':<10} {'Issues'}")
        print("-" * 90)

        for node_type, node_data in nodes.items():
            behind = node_data.get('blocks_behind', 0)
            behind_str = f"{behind:,}" if behind > 0 else "OK"

            issues_str = f"{len(node_data.get('issues', []))}"
            if node_data.get('lagging', False):
                issues_str += " ⚠️"

            sync_status = node_data.get('sync_status', 'unknown')[:12]
            rpc_status = "✅" if node_data.get('rpc_responsive', False) else "❌"

            print(f"{node_type:<15} {node_data.get('current_block', 0):<12,} "
                  f"{node_data.get('health_score', 0):<8} "
                  f"{sync_status:<12} "
                  f"{node_data.get('peer_count', 0):<8} "
                  f"{behind_str:<10} {issues_str}")

    def check_alerts(self, consistency_results: Dict[str, Any], threshold: str) -> List[Dict[str, Any]]:
        """Check for alerts based on consistency results"""
        alerts = []
        if isinstance(threshold, str):
            thresholds = self.config.alert_thresholds.get(threshold, self.config.alert_thresholds["moderate"])
        else:
            thresholds = threshold  # Use the passed threshold directly if it's already a dict

        if "error" in consistency_results:
            return [{"type": "CRITICAL", "message": f"Verification error: {consistency_results['error']}"}]

        summary = consistency_results.get("summary", {})
        nodes = consistency_results.get("nodes", {})

        # Block divergence alert
        if not summary.get("consistent", True):
            block_diff = summary.get("block_difference", 0)
            if block_diff > 50:
                alerts.append({
                    "type": "CRITICAL",
                    "message": f"Critical block divergence: {block_diff:,} blocks"
                })
            elif block_diff > 20:
                alerts.append({
                    "type": "WARNING",
                    "message": f"Significant block divergence: {block_diff:,} blocks"
                })

        # Reference divergence alert
        if "reference" in consistency_results:
            ref = consistency_results["reference"]
            if not ref.get("reference_consistent", True):
                local_diff = ref.get("local_max_diff", 0)
                if local_diff > 50:
                    alerts.append({
                        "type": "CRITICAL",
                        "message": f"Critical divergence from reference: {local_diff:,} blocks"
                    })
                elif local_diff > 20:
                    alerts.append({
                        "type": "WARNING",
                        "message": f"Significant divergence from reference: {local_diff:,} blocks"
                    })

        # Reorganization alert
        if "reorg_check" in consistency_results:
            reorg = consistency_results["reorg_check"]
            if reorg.get("status") == "inconsistent":
                alerts.append({
                    "type": "WARNING",
                    "message": f"Potential reorganization detected: {reorg.get('unique_hashes', 0)} different block hashes"
                })

        # Node-specific alerts
        for node_type, node_data in nodes.items():
            health = node_data.get("health_score", 100)
            sync_status = node_data.get("sync_status", "unknown")
            issues = node_data.get("issues", [])
            peer_count = node_data.get("peer_count", 0)
            response_time = node_data.get("response_time", 0)

            if health < 30:
                alerts.append({
                    "type": "CRITICAL",
                    "node": node_type,
                    "message": f"Critical health score: {health}%"
                })
            elif health < 50:
                alerts.append({
                    "type": "WARNING",
                    "node": node_type,
                    "message": f"Low health score: {health}%"
                })

            if sync_status == "error":
                alerts.append({
                    "type": "CRITICAL",
                    "node": node_type,
                    "message": "Sync error detected"
                })

            if peer_count < thresholds.get("min_peers", 8):
                alerts.append({
                    "type": "WARNING",
                    "node": node_type,
                    "message": f"Low peer count: {peer_count}"
                })

            if response_time > thresholds.get("max_response_time", 2.0):
                alerts.append({
                    "type": "WARNING",
                    "node": node_type,
                    "message": f"High response time: {response_time:.2f}s"
                })

            if len(issues) > 5:
                alerts.append({
                    "type": "CRITICAL",
                    "node": node_type,
                    "message": f"Multiple issues detected: {len(issues)} problems"
                })

        return alerts

    def handle_alerts(self, alerts: List[Dict[str, Any]], network: str, timestamp: datetime):
        """Handle alerts by logging and potentially sending notifications"""
        for alert in alerts:
            alert["network"] = network
            alert["timestamp"] = timestamp.isoformat()

            self.alert_history.append(alert)

            # Log alert
            level = alert.get("type", "INFO")
            node = alert.get("node", "")
            message = alert.get("message", "")

            if node:
                log_message = f"[{level}] {network} - {node}: {message}"
            else:
                log_message = f"[{level}] {network}: {message}"

            if level == "CRITICAL":
                logger.error(log_message)
            elif level == "WARNING":
                logger.warning(log_message)
            else:
                logger.info(log_message)

            # Display alert
            icon = "🚨" if level == "CRITICAL" else "⚠️"
            print(f"{icon} {log_message}")

    async def generate_monitoring_report(self):
        """Generate comprehensive monitoring report"""
        report = {
            "generated_at": datetime.now().isoformat(),
            "summary": {
                "total_alerts": len(self.alert_history),
                "critical_alerts": len([a for a in self.alert_history if a.get("type") == "CRITICAL"]),
                "warning_alerts": len([a for a in self.alert_history if a.get("type") == "WARNING"]),
                "networks_monitored": len(self.config.networks),
                "node_types_monitored": len(self.config.node_types)
            },
            "alerts": self.alert_history,
            "configuration": asdict(self.config)
        }

        # Save report
        report_file = f"/var/log/blockchain_sync_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        try:
            Path(report_file).parent.mkdir(parents=True, exist_ok=True)
            with open(report_file, 'w') as f:
                json.dump(report, f, indent=2, default=str)
            logger.info(f"Report saved: {report_file}")
            print(f"\n📄 Detailed report saved: {report_file}")
        except Exception as e:
            logger.error(f"Error saving report: {e}")

        return report

    def export_results(self, results: Dict[str, Any], output_format: str = "json",
                      output_file: str = None) -> str:
        """Export verification results to file"""
        if output_file is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            extension = output_format.lower()
            output_file = f"/var/log/blockchain_sync_verification_{timestamp}.{extension}"

        try:
            Path(output_file).parent.mkdir(parents=True, exist_ok=True)

            if output_format.lower() == "json":
                with open(output_file, 'w') as f:
                    json.dump(results, f, indent=2, default=str)
            elif output_format.lower() == "yaml":
                with open(output_file, 'w') as f:
                    yaml.dump(results, f, default_flow_style=False)
            else:
                # Default to JSON
                with open(output_file, 'w') as f:
                    json.dump(results, f, indent=2, default=str)

            print(f"✅ Results exported to: {output_file}")
            return output_file

        except Exception as e:
            print(f"❌ Failed to export results: {e}")
            return None

    def calculate_network_health(self, consistency_results: Dict[str, Any]) -> Dict[str, Any]:
        """Calculate comprehensive network health metrics"""
        if "error" in consistency_results:
            return {"status": "error", "message": consistency_results["error"]}

        summary = consistency_results.get("summary", {})
        nodes = consistency_results.get("nodes", {})

        # Calculate overall health metrics
        total_health = sum(node.get("health_score", 0) for node in nodes.values())
        avg_health = total_health / len(nodes) if nodes else 0

        # Calculate sync efficiency
        fully_synced = len([n for n in nodes.values() if n.get("sync_status") == "fully_synced"])
        sync_efficiency = (fully_synced / len(nodes)) * 100 if nodes else 0

        # Calculate network stability
        block_variance = summary.get("block_difference", 0)
        stability_score = max(0, 100 - block_variance * 2)

        # Calculate performance score
        avg_response = sum(n.get("response_time", 0) for n in nodes.values() if n.get("response_time", 0) > 0)
        avg_response = avg_response / len(nodes) if nodes else 0
        performance_score = max(0, 100 - avg_response * 20)

        # Calculate reliability score
        active_nodes = len([n for n in nodes.values() if n.get("service_status") == "active"])
        reliability_score = (active_nodes / len(nodes)) * 100 if nodes else 0

        return {
            "network": summary.get("network", "Unknown"),
            "overall_health_score": int(avg_health),
            "sync_efficiency": sync_efficiency,
            "network_stability": stability_score,
            "performance_score": performance_score,
            "reliability_score": reliability_score,
            "node_count": len(nodes),
            "active_nodes": active_nodes,
            "lagging_nodes": len([n for n in nodes.values() if n.get("lagging", False)]),
            "critical_issues": len([n for n in nodes.values() if n.get("health_score", 0) < 30]),
            "recommendations": self.generate_network_recommendations(consistency_results)
        }

    def generate_network_recommendations(self, consistency_results: Dict[str, Any]) -> List[str]:
        """Generate network-level recommendations"""
        recommendations = []

        if "error" in consistency_results:
            recommendations.append("❌ Network verification failed - check all node configurations")
            return recommendations

        summary = consistency_results.get("summary", {})
        nodes = consistency_results.get("nodes", {})

        # Node health recommendations
        for node_type, node_data in nodes.items():
            health = node_data.get("health_score", 0)
            issues = node_data.get("issues", [])
            sync_status = node_data.get("sync_status", "unknown")

            if health < 30:
                recommendations.append(f"🚨 {node_type} has critical health score ({health}%) - immediate intervention required")
            elif health < 50:
                recommendations.append(f"⚠️ {node_type} has low health score ({health}%) - investigate issues")

            if sync_status == "error":
                recommendations.append(f"🔧 {node_type} sync errors detected - check logs and restart service")
            elif sync_status == "syncing" and node_data.get("sync_progress", 0) < 50:
                recommendations.append(f"🔄 {node_type} sync progress low ({node_data.get('sync_progress', 0):.1f}%) - monitor closely")

            if node_data.get("lagging", False):
                recommendations.append(f"⚠️ {node_type} lagging behind - check connectivity and resources")

            if len(issues) > 5:
                recommendations.append(f"🔍 {node_type} has multiple issues - investigate systematically")

        # Network-level recommendations
        block_diff = summary.get("block_difference", 0)
        if block_diff > 100:
            recommendations.append(f"🌐 Critical network divergence detected - block gap of {block_diff} blocks")
        elif block_diff > 50:
            recommendations.append(f"⚠️ Significant network divergence - block gap of {block_diff} blocks")

        # Reference comparison
        if "reference" in consistency_results:
            ref = consistency_results["reference"]
            if not ref.get("reference_consistent", True):
                local_diff = ref.get("local_max_diff", 0)
                if local_diff > 20:
                    recommendations.append(f"⚠️ Network diverged from reference by {local_diff} blocks")

        # Check for reorganizations
        if "reorg_check" in consistency_results:
            reorg = consistency_results["reorg_check"]
            if reorg.get("status") == "inconsistent":
                recommendations.append(f"🔄 Potential reorganization detected - {reorg.get('unique_hashes', 0)} different block hashes")

        return recommendations

    async def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Comprehensive Blockchain Sync Verification System")
    parser.add_argument("--node-type", choices=["geth", "erigon", "nethermind", "besu", "all"],
                       default="all", help="Node type to check")
    parser.add_argument("--network", choices=["mainnet", "sepolia", "holesky", "all"],
                       default="mainnet", help="Network to check")
    parser.add_argument("--verification-level", choices=["basic", "standard", "comprehensive", "forensic"],
                       default="standard", help="Verification depth")
    parser.add_argument("--alert-threshold", choices=["conservative", "moderate", "aggressive"],
                       default="moderate", help="Alert sensitivity")
    parser.add_argument("--output-format", choices=["json", "yaml", "table", "dashboard"],
                       default="table", help="Output format")
    parser.add_argument("--duration", type=int, default=10, help="Monitoring duration in minutes")
    parser.add_argument("--compare-nodes", action="store_true", help="Compare nodes for consistency")
    parser.add_argument("--export", help="Export results to file")
    parser.add_argument("--config", default="/etc/blockchain/sync_verifier.conf",
                       help="Configuration file path")

    args = parser.parse_args()

    # Create configuration directory if needed
    Path(args.config).parent.mkdir(parents=True, exist_ok=True)

    async with BlockchainSyncVerifier(args.config) as verifier:
        if args.compare_nodes or args.node_type == "all":
            # Run real-time monitoring
            await verifier.run_real_time_monitoring(
                duration_minutes=args.duration,
                alert_threshold=args.alert_threshold,
                output_format=args.output_format
            )
        else:
            # Single node check
            status = await verifier.get_node_sync_status(args.node_type, args.network)
            results = asdict(status)

            if args.export:
                verifier.export_results(results, args.output_format, args.export)
            else:
                print(json.dumps(results, indent=2, default=str))

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n👋 Monitoring stopped by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        print(f"❌ Fatal error: {e}")
        sys.exit(1)