#!/usr/bin/env python3
"""
Comprehensive Geth Management System

This module provides complete lifecycle management for Geth (Go Ethereum) client including:
- Installation and setup
- Configuration management
- Service deployment
- Monitoring and optimization
- Backup and recovery

Author: Claude Code MEV Specialist
Version: 1.0.0
"""

import os
import sys
import json
import yaml
import time
import shutil
import logging
import asyncio
import subprocess
import argparse
import hashlib
import tarfile
import requests
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, asdict
from enum import Enum
import psutil
import toml
import jsonschema

# Configure logging with proper error handling
def setup_logging():
    """Setup logging with error handling for permission issues"""
    handlers = [logging.StreamHandler(sys.stdout)]

    # Try to add file handler, fallback if permission denied
    try:
        log_file = Path('/var/log/geth-manager.log')
        log_file.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(log_file)
        handlers.append(file_handler)
    except (PermissionError, OSError):
        # Fallback to logging to /tmp if /var/log is not writable
        try:
            fallback_log = Path('/tmp/geth-manager.log')
            file_handler = logging.FileHandler(fallback_log)
            handlers.append(file_handler)
        except (PermissionError, OSError):
            pass  # Use only console output
    except Exception:
        pass  # Fallback to basic logging

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=handlers,
        force=True
    )

    # Create logger after setting up logging
    logger = logging.getLogger('GethManager')

# Initialize logging
setup_logging()
logger = logging.getLogger('GethManager')

class GethNetwork(Enum):
    """Supported Geth networks"""
    MAINNET = "mainnet"
    GOERLI = "goerli"
    SEPOLIA = "sepolia"
    HOLESKY = "holesky"
    GNOSIS = "gnosis"
    POLYGON = "polygon"

class SyncMode(Enum):
    """Geth sync modes"""
    FAST = "fast"
    FULL = "full"
    SNAP = "snap"
    LIGHT = "light"

@dataclass
class GethConfig:
    """Geth configuration structure"""
    network: GethNetwork
    sync_mode: SyncMode
    data_dir: str
    http_port: int = 8545
    ws_port: int = 8546
    p2p_port: int = 30303
    metrics_port: int = 6060
    http_apis: List[str] = None
    ws_apis: List[str] = None
    http_cors_origins: List[str] = None
    ws_origins: List[str] = None
    max_peers: int = 50
    cache_size: int = 1024
    auth_rpc_port: int = 8551
    jwt_secret_path: str = None
    http_addr: str = "127.0.0.1"
    ws_addr: str = "127.0.0.1"
    metrics_addr: str = "127.0.0.1"
    authrpc_addr: str = "127.0.0.1"
    snapshot: bool = False
    sync_target: Optional[int] = None
    allow_insecure_unlock: bool = False
    verbosity: int = 3
    private_key: Optional[str] = None
    password_file: Optional[str] = None

    def __post_init__(self):
        if self.http_apis is None:
            self.http_apis = ["eth", "net", "web3", "personal", "debug"]
        if self.ws_apis is None:
            self.ws_apis = ["eth", "net", "web3"]
        if self.http_cors_origins is None:
            self.http_cors_origins = ["*"]
        if self.ws_origins is None:
            self.ws_origins = ["*"]

@dataclass
class GethStatus:
    """Geth node status information"""
    is_installed: bool = False
    is_running: bool = False
    version: Optional[str] = None
    sync_progress: Optional[float] = None
    current_block: Optional[int] = None
    highest_block: Optional[int] = None
    peer_count: int = 0
    gas_price: Optional[int] = None
    chain_id: Optional[int] = None
    cpu_usage: float = 0.0
    memory_usage: float = 0.0
    disk_usage: float = 0.0
    uptime: Optional[str] = None
    rpc_available: bool = False
    ws_available: bool = False
    metrics_available: bool = False

class GethManager:
    """Comprehensive Geth management system"""

    def __init__(self, config_file: str = "/data/blockchain/nodes/config/geth_backup.yaml"):
        self.config_file = config_file
        self.config = None
        self.status = GethStatus()
        self.config_schema = self._get_config_schema()

        # Production Directories
        self.base_dir = Path("/data/blockchain/nodes")
        self.config_dir = Path("/data/blockchain/nodes/config")
        self.data_dir = Path("/data/blockchain/storage/geth-backup")
        self.logs_dir = Path("/data/blockchain/nodes/logs")
        self.state_dir = Path("/data/blockchain/nodes/state")
        self.monitoring_dir = Path("/data/blockchain/nodes/monitoring")
        self.backup_dir = Path("/data/blockchain/nodes/backups")

        # Files
        self.systemd_service = "/etc/systemd/system/geth.service"
        self.jwt_secret_file = Path("/data/blockchain/storage/jwt-secret-common.hex")
        self.password_file = self.config_dir / "password.txt"

        # Network configurations
        self.network_configs = {
            GethNetwork.MAINNET: {
                "genesis": None,
                "chain_id": 1,
                "bootnodes": [
                    "enode://d860a01f9722d780f16cf8ecef681c0473a8e332c020f1ac66e2b455823cbed@65.108.3.237:30303",
                    "enode://a979fb57599599b1e3c9057a4a42f0e7354158766e311d6a6b5d5a7f7d3b4e@65.108.128.163:30303"
                ]
            },
            GethNetwork.GOERLI: {
                "genesis": None,
                "chain_id": 5,
                "bootnodes": [
                    "enode://a24ac7c5484ef4ed0c5eb2d36620ba4e4af13b8e8a215b6b61a06378661a2a2@18.138.108.67:30303"
                ]
            },
            GethNetwork.SEPOLIA: {
                "genesis": None,
                "chain_id": 11155111,
                "bootnodes": [
                    "enode://a15a102e1a373d4ad4e465614621b17ab8fc0b1a3d4a8a0a1c8c3c6e8f5b8c3@18.170.0.191:30303"
                ]
            }
        }

        self._ensure_directories()

    def _ensure_directories(self):
        """Create necessary directories - adapted for production paths"""
        for directory in [self.base_dir, self.config_dir, self.data_dir, self.logs_dir, self.state_dir, self.monitoring_dir]:
            directory.mkdir(parents=True, exist_ok=True)
            try:
                os.chown(directory, 0, 0)  # root:root
            except PermissionError:
                pass  # Continue with directory creation

        # Create additional production directories
        try:
            os.makedirs(self.backup_dir, exist_ok=True)
        except PermissionError:
            logger.warning(f"Cannot create {self.backup_dir} directory, using local backup instead")

    def _get_config_schema(self) -> Dict[str, Any]:
        """Get JSON schema for configuration validation"""
        return {
            "type": "object",
            "properties": {
                "network": {"type": "string", "enum": [n.value for n in GethNetwork]},
                "sync_mode": {"type": "string", "enum": [m.value for m in SyncMode]},
                "data_dir": {"type": "string"},
                "http_port": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "ws_port": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "p2p_port": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "metrics_port": {"type": "integer", "minimum": 1024, "maximum": 65535},
                "max_peers": {"type": "integer", "minimum": 1, "maximum": 200},
                "cache_size": {"type": "integer", "minimum": 128, "maximum": 16384},
                "http_apis": {"type": "array", "items": {"type": "string"}},
                "ws_apis": {"type": "array", "items": {"type": "string"}},
                "http_cors_origins": {"type": "array", "items": {"type": "string"}},
                "ws_origins": {"type": "array", "items": {"type": "string"}}
            },
            "required": ["network", "sync_mode", "data_dir"]
        }

    def load_config(self) -> bool:
        """Load configuration from file"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    data = yaml.safe_load(f)
                    
                # Map YAML structure to dataclass
                config_data = {}
                config_data['network'] = data.get('network', 'mainnet')
                config_data['sync_mode'] = data.get('syncmode', 'snap')
                config_data['data_dir'] = data.get('datadir', str(self.data_dir))
                
                # Extract ports from nested structures
                http_addr = data.get('http', {}).get('addr', '0.0.0.0:8545')
                ws_addr = data.get('ws', {}).get('addr', '0.0.0.0:8546')
                p2p_config = data.get('p2p', {})
                metrics_config = data.get('metrics', {})
                
                config_data['http_port'] = int(http_addr.split(':')[-1]) if ':' in http_addr else 8545
                config_data['ws_port'] = int(ws_addr.split(':')[-1]) if ':' in ws_addr else 8546
                config_data['p2p_port'] = p2p_config.get('port', 30303)
                config_data['metrics_port'] = int(metrics_config.get('addr', '0.0.0.0:6069').split(':')[-1])
                config_data['max_peers'] = data.get('maxpeers', 50)
                config_data['http_apis'] = data.get('http_apis', [])
                
                # Create config object
                self.config = GethConfig(**config_data)
                logger.info(f"Configuration loaded from {self.config_file}")
                return True
            else:
                logger.warning(f"Configuration file {self.config_file} not found, creating default")
                return self.create_default_config()
        except Exception as e:
            logger.error(f"Failed to load configuration: {e}")
            return False

    def create_default_config(self, network: GethNetwork = GethNetwork.MAINNET) -> bool:
        """Create default configuration"""
        try:
            # Create YAML configuration that matches our expected structure
            default_config = {
                'network': network.value,
                'syncmode': 'snap',
                'datadir': str(self.data_dir),
                'authrpc.jwtsecret': str(self.jwt_secret_file),
                
                'http': {
                    'addr': '0.0.0.0:8549',
                    'api': 'eth,net,web3,debug,txpool',
                    'cors': ['*'],
                    'vhosts': ['*']
                },
                
                'ws': {
                    'addr': '0.0.0.0:8550',
                    'origins': ['*']
                },
                
                'authrpc': {
                    'addr': '0.0.0.0:8554',
                    'jwtsecret': str(self.jwt_secret_file),
                    'vhosts': ['localhost']
                },
                
                'p2p': {
                    'discovery.v5': True,
                    'maxpeers': 100,
                    'port': 30312,
                    'netrestrict': ['127.0.0.0/8'],
                    'nat': ['extip:80.80.80.80']
                },
                
                'cache': {
                    'database': 4096,
                    'trie': 1024,
                    'trie-incremental': 1024,
                    'trie-journal': 1024,
                    'gc': 64,
                    'copy-on-write': True,
                    'noPrefetch': False
                },
                
                'gasprice': '2000000000',
                'gascap': 0,
                'maxpeers': 50,
                
                'txpool': {
                    'locals': 0,
                    'journal': 1024,
                    'reorg': 200,
                    'pricebump': 10,
                    'pricelimit': 1000000000,
                    'accountslots': 16,
                    'globalslots': 4096
                },
                
                'http_apis': [
                    'eth_blockNumber',
                    'eth_getBlockByNumber', 
                    'eth_getTransactionReceipt',
                    'eth_estimateGas',
                    'net_peerCount',
                    'net_listening',
                    'web3_clientVersion',
                    'debug_traceTransaction',
                    'debug_traceBlockByNumber',
                    'debug_traceCall',
                    'txpool_status',
                    'txpool_content'
                ],
                
                'miner': {
                    'enabled': False,
                    'gaslimit': 9000000,
                    'gasprice': 2000000000,
                    'recommitperiod': 3,
                    'nethermind': 0,
                    'extradata': '0x41'
                },
                
                'metrics': {
                    'enabled': True,
                    'port': 6069,
                    'exp': True,
                    'addr': '0.0.0.0:6069',
                    'pprof': True,
                    'memprof': True
                },
                
                'log': {
                    'file': '/data/blockchain/nodes/logs/geth-backup.log',
                    'level': 'info',
                    'maxsize': 64,
                    'vmodule': False
                },
                
                'syncsnap': {
                    'cache': 4294967296,
                    'keepsyncs': 4,
                    'timeout': '60m'
                },
                
                'pruning': {
                    'receipts': False,
                    'senders': False,
                    'trie': False
                },
                
                'security': {
                    'private.api': ['eth', 'net', 'web3'],
                    'debug': False
                },
                
                'identity': {
                    'version': 'Geth/Production-MEV-Backup'
                }
            }

            # Save configuration
            with open(self.config_file, 'w') as f:
                yaml.dump(default_config, f, default_flow_style=False)

            logger.info(f"Default configuration created at {self.config_file}")
            
            # Create config object for internal use
            config_data = {}
            config_data['network'] = default_config['network']
            config_data['sync_mode'] = default_config['syncmode']
            config_data['data_dir'] = default_config['datadir']
            config_data['http_port'] = 8549
            config_data['ws_port'] = 8550
            config_data['p2p_port'] = 30312
            config_data['metrics_port'] = 6069
            config_data['max_peers'] = default_config['maxpeers']
            config_data['http_apis'] = default_config['http_apis']
            
            self.config = GethConfig(**config_data)
            return True
        except Exception as e:
            logger.error(f"Failed to create default configuration: {e}")
            return False

    def install_geth(self, version: str = "latest") -> bool:
        """Install Geth client"""
        try:
            logger.info(f"Installing Geth version: {version}")

            # Check if already installed
            if shutil.which("geth") is not None:
                installed_version = self._get_installed_version()
                logger.info(f"Geth already installed: {installed_version}")
                self.status.is_installed = True
                self.status.version = installed_version
                return True

            # Install dependencies
            self._install_dependencies()

            # Download and install Geth
            if version == "latest":
                download_url = self._get_latest_download_url()
            else:
                download_url = f"https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-{version}.tar.gz"

            # Download Geth
            tar_file = self.base_dir / "geth.tar.gz"
            logger.info(f"Downloading Geth from {download_url}")

            response = requests.get(download_url, stream=True)
            response.raise_for_status()

            with open(tar_file, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)

            # Extract Geth
            logger.info("Extracting Geth")
            with tarfile.open(tar_file, 'r:gz') as tar:
                tar.extractall(self.base_dir)

            # Install to system
            geth_binary = self.base_dir / "geth"
            if geth_binary.exists():
                shutil.copy(geth_binary, "/usr/local/bin/geth")
                os.chmod("/usr/local/bin/geth", 0o755)
                logger.info("Geth installed to /usr/local/bin/geth")
            else:
                # Look for binary in extracted directory
                for item in self.base_dir.iterdir():
                    if item.is_file() and item.stat().st_mode & 0o111:
                        shutil.copy(item, "/usr/local/bin/geth")
                        os.chmod("/usr/local/bin/geth", 0o755)
                        break

            # Clean up
            tar_file.unlink()

            # Verify installation
            installed_version = self._get_installed_version()
            if installed_version:
                self.status.is_installed = True
                self.status.version = installed_version
                logger.info(f"Geth successfully installed: {installed_version}")
                return True
            else:
                logger.error("Geth installation verification failed")
                return False

        except Exception as e:
            logger.error(f"Failed to install Geth: {e}")
            return False

    def _get_installed_version(self) -> Optional[str]:
        """Get installed Geth version"""
        try:
            result = subprocess.run(
                ["geth", "version"],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                # Extract version from output
                for line in result.stdout.split('\n'):
                    if 'Geth' in line and 'version' in line:
                        return line.strip()
            return None
        except Exception:
            return None

    def _get_latest_download_url(self) -> str:
        """Get latest Geth download URL"""
        try:
            # Get latest release from GitHub API
            response = requests.get("https://api.github.com/repos/ethereum/go-ethereum/releases/latest")
            response.raise_for_status()

            release_data = response.json()

            # Find Linux AMD64 asset
            for asset in release_data['assets']:
                if 'linux-amd64' in asset['name'] and asset['name'].endswith('.tar.gz'):
                    return asset['browser_download_url']

            # Fallback to known stable version
            return "https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-latest.tar.gz"
        except Exception as e:
            logger.warning(f"Failed to get latest version, using fallback: {e}")
            return "https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-latest.tar.gz"

    def _install_dependencies(self):
        """Install system dependencies"""
        dependencies = ["curl", "wget", "tar", "jq", "net-tools"]

        try:
            subprocess.run(
                ["apt-get", "update"],
                check=True,
                capture_output=True
            )

            for dep in dependencies:
                subprocess.run(
                    ["apt-get", "install", "-y", dep],
                    check=True,
                    capture_output=True
                )

            logger.info("Dependencies installed successfully")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to install dependencies: {e}")

    def generate_jwt_secret(self) -> bool:
        """Generate JWT secret for authenticated RPC"""
        try:
            import secrets

            # Generate 32-byte hex string
            secret = secrets.token_hex(32)

            with open(self.jwt_secret_file, 'w') as f:
                f.write(secret)

            # Set secure permissions
            os.chmod(self.jwt_secret_file, 0o600)
            os.chown(self.jwt_secret_file, 0, 0)

            logger.info(f"JWT secret generated at {self.jwt_secret_file}")
            return True
        except Exception as e:
            logger.error(f"Failed to generate JWT secret: {e}")
            return False

    def create_systemd_service(self) -> bool:
        """Create systemd service for Geth"""
        try:
            if not self.config:
                logger.error("Configuration not loaded")
                return False

            # Ensure JWT secret exists
            if not os.path.exists(self.jwt_secret_file):
                self.generate_jwt_secret()

            # Build command arguments
            cmd_args = [
                "--http",
                f"--http.api={','.join(self.config.http_apis)}",
                f"--http.addr={self.config.http_addr}",
                f"--http.port={self.config.http_port}",
                f"--http.corsdomain={','.join(self.config.http_cors_origins)}",
                "--ws",
                f"--ws.api={','.join(self.config.ws_apis)}",
                f"--ws.addr={self.config.ws_addr}",
                f"--ws.port={self.config.ws_port}",
                f"--ws.origins={','.join(self.config.ws_origins)}",
                "--authrpc",
                f"--authrpc.jwtsecret={self.config.jwt_secret_path}",
                f"--authrpc.addr={self.config.authrpc_addr}",
                f"--authrpc.port={self.config.auth_rpc_port}",
                "--metrics",
                f"--metrics.addr={self.config.metrics_addr}",
                f"--metrics.port={self.config.metrics_port}",
                f"--port={self.config.p2p_port}",
                f"--datadir={self.config.data_dir}",
                f"--cache={self.config.cache_size}",
                f"--maxpeers={self.config.max_peers}",
                f"--syncmode={self.config.sync_mode.value}",
                f"--networkid={self.network_configs[self.config.network]['chain_id']}",
                f"--verbosity={self.config.verbosity}",
                "--allow-insecure-unlocked"
            ]

            # Add network-specific options
            if self.config.network == GethNetwork.MAINNET:
                cmd_args.append("--mainnet")

            # Add snapshot option for snap sync
            if self.config.sync_mode == SyncMode.SNAP:
                cmd_args.append("--sync.snap")

            # Create service file
            service_content = f"""[Unit]
Description=Geth Ethereum Client
Documentation=https://geth.ethereum.org/docs/
After=network-online.target
Wants=network-online.target

[Service]
User=root
Group=root
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/geth {' '.join(cmd_args)}
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT
TimeoutStopSec=30
WorkingDirectory={self.config.data_dir}
Environment=HOME={self.config.data_dir}
Environment=USER=root

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths={self.config.data_dir}
ProtectKernelTunables=false
ProtectControlGroups=false
RestrictSUIDSGID=true
RemoveIPC=true

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
"""

            with open(self.systemd_service, 'w') as f:
                f.write(service_content)

            # Reload systemd and enable service
            subprocess.run(["systemctl", "daemon-reload"], check=True)
            subprocess.run(["systemctl", "enable", "geth"], check=True)

            logger.info(f"Systemd service created at {self.systemd_service}")
            return True

        except Exception as e:
            logger.error(f"Failed to create systemd service: {e}")
            return False

    def start_geth(self) -> bool:
        """Start Geth service"""
        try:
            subprocess.run(["systemctl", "start", "geth"], check=True)
            logger.info("Geth service started")

            # Wait a moment and check status
            time.sleep(5)
            return self.is_running()
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to start Geth: {e}")
            return False

    def stop_geth(self) -> bool:
        """Stop Geth service"""
        try:
            subprocess.run(["systemctl", "stop", "geth"], check=True)
            logger.info("Geth service stopped")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to stop Geth: {e}")
            return False

    def restart_geth(self) -> bool:
        """Restart Geth service"""
        try:
            subprocess.run(["systemctl", "restart", "geth"], check=True)
            logger.info("Geth service restarted")

            # Wait and check status
            time.sleep(5)
            return self.is_running()
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to restart Geth: {e}")
            return False

    def is_running(self) -> bool:
        """Check if Geth is running"""
        try:
            result = subprocess.run(
                ["systemctl", "is-active", "geth"],
                capture_output=True,
                text=True
            )
            is_active = result.returncode == 0
            self.status.is_running = is_active
            return is_active
        except Exception:
            return False

    def get_status(self) -> GethStatus:
        """Get comprehensive Geth status"""
        try:
            # Basic status
            self.status.is_installed = self.status.is_installed or shutil.which("geth") is not None
            self.status.is_running = self.is_running()

            if self.status.is_installed and not self.status.version:
                self.status.version = self._get_installed_version()

            if self.status.is_running:
                # Get RPC status
                rpc_url = f"http://{self.config.http_addr}:{self.config.http_port}" if self.config else None
                if rpc_url:
                    self.status.rpc_available = self._test_rpc_connection(rpc_url)
                    if self.status.rpc_available:
                        self._update_sync_status(rpc_url)

                # Get resource usage
                self._update_resource_usage()

            return self.status
        except Exception as e:
            logger.error(f"Failed to get status: {e}")
            return self.status

    def _test_rpc_connection(self, rpc_url: str) -> bool:
        """Test RPC connection"""
        try:
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_chainId",
                "params": [],
                "id": 1
            }

            response = requests.post(rpc_url, json=payload, timeout=5)
            return response.status_code == 200
        except Exception:
            return False

    def _update_sync_status(self, rpc_url: str):
        """Update sync status from RPC"""
        try:
            # Get sync status
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_syncing",
                "params": [],
                "id": 1
            }

            response = requests.post(rpc_url, json=payload, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if "result" in data:
                    sync_data = data["result"]
                    if sync_data is False:
                        # Fully synced
                        self.status.sync_progress = 100.0

                        # Get current block
                        payload = {
                            "jsonrpc": "2.0",
                            "method": "eth_blockNumber",
                            "params": [],
                            "id": 2
                        }
                        response = requests.post(rpc_url, json=payload, timeout=10)
                        if response.status_code == 200:
                            block_data = response.json()
                            if "result" in block_data:
                                self.status.current_block = int(block_data["result"], 16)
                                self.status.highest_block = self.status.current_block
                    else:
                        # Still syncing
                        if "currentBlock" in sync_data:
                            self.status.current_block = int(sync_data["currentBlock"], 16)
                        if "highestBlock" in sync_data:
                            self.status.highest_block = int(sync_data["highestBlock"], 16)

                        if self.status.current_block and self.status.highest_block:
                            self.status.sync_progress = (self.status.current_block / self.status.highest_block) * 100

            # Get peer count
            payload = {
                "jsonrpc": "2.0",
                "method": "net_peerCount",
                "params": [],
                "id": 3
            }

            response = requests.post(rpc_url, json=payload, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if "result" in data:
                    self.status.peer_count = int(data["result"], 16)

            # Get gas price
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_gasPrice",
                "params": [],
                "id": 4
            }

            response = requests.post(rpc_url, json=payload, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if "result" in data:
                    self.status.gas_price = int(data["result"], 16)

        except Exception as e:
            logger.error(f"Failed to update sync status: {e}")

    def _update_resource_usage(self):
        """Update resource usage statistics"""
        try:
            # Find Geth process
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']):
                if proc.info['name'] == 'geth':
                    self.status.cpu_usage = proc.info['cpu_percent']
                    self.status.memory_usage = proc.info['memory_percent']
                    break

            # Get disk usage
            if self.config and os.path.exists(self.config.data_dir):
                disk_usage = shutil.disk_usage(self.config.data_dir)
                self.status.disk_usage = disk_usage.used / (1024 ** 3)  # GB

        except Exception as e:
            logger.error(f"Failed to update resource usage: {e}")

    def optimize_performance(self) -> Dict[str, Any]:
        """Analyze and suggest performance optimizations"""
        try:
            optimizations = []

            if self.status:
                # CPU usage optimization
                if self.status.cpu_usage > 80:
                    optimizations.append({
                        "issue": "High CPU usage",
                        "current": f"{self.status.cpu_usage}%",
                        "suggestion": "Consider reducing cache size or max peers",
                        "action": "cache_size=512, max_peers=25"
                    })

                # Memory usage optimization
                if self.status.memory_usage > 70:
                    optimizations.append({
                        "issue": "High memory usage",
                        "current": f"{self.status.memory_usage}%",
                        "suggestion": "Reduce cache size",
                        "action": "cache_size=512"
                    })

                # Disk usage warning
                if self.status.disk_usage > 100:  # 100GB
                    optimizations.append({
                        "issue": "High disk usage",
                        "current": f"{self.status.disk_usage:.1f}GB",
                        "suggestion": "Consider pruning old data",
                        "action": "geth snapshot prune-state"
                    })

                # Peer count optimization
                if self.status.peer_count > 80:
                    optimizations.append({
                        "issue": "High peer count",
                        "current": str(self.status.peer_count),
                        "suggestion": "Reduce max peers",
                        "action": "max_peers=50"
                    })
                elif self.status.peer_count < 5:
                    optimizations.append({
                        "issue": "Low peer count",
                        "current": str(self.status.peer_count),
                        "suggestion": "Add more bootnodes or check network",
                        "action": "Add static nodes or check firewall"
                    })

            return {
                "optimizations": optimizations,
                "current_config": asdict(self.config) if self.config else None,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }

        except Exception as e:
            logger.error(f"Failed to analyze performance: {e}")
            return {"error": str(e)}

    def backup_data(self, backup_path: Optional[str] = None) -> bool:
        """Create backup of Geth data"""
        try:
            if not backup_path:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                backup_path = f"/opt/backups/geth_backup_{timestamp}.tar.gz"

            backup_path = Path(backup_path)
            backup_path.parent.mkdir(parents=True, exist_ok=True)

            logger.info(f"Creating backup at {backup_path}")

            # Create tarball of data directory
            with tarfile.open(backup_path, 'w:gz') as tar:
                tar.add(self.config.data_dir, arcname="geth_data")

            logger.info(f"Backup completed: {backup_path.stat().st_size / (1024**2):.1f}MB")
            return True

        except Exception as e:
            logger.error(f"Failed to create backup: {e}")
            return False

    def restore_data(self, backup_path: str) -> bool:
        """Restore Geth data from backup"""
        try:
            if self.is_running():
                self.stop_geth()

            # Backup current data
            self.backup_data()

            # Extract backup
            with tarfile.open(backup_path, 'r:gz') as tar:
                tar.extractall(self.data_dir.parent)

            logger.info(f"Data restored from {backup_path}")
            return True

        except Exception as e:
            logger.error(f"Failed to restore data: {e}")
            return False

    def update_configuration(self, new_config: Dict[str, Any]) -> bool:
        """Update Geth configuration"""
        try:
            # Validate new config
            jsonschema.validate(new_config, self.config_schema)

            # Update config object
            for key, value in new_config.items():
                if key == "network":
                    self.config.network = GethNetwork(value)
                elif key == "sync_mode":
                    self.config.sync_mode = SyncMode(value)
                elif hasattr(self.config, key):
                    setattr(self.config, key, value)

            # Save configuration
            with open(self.config_file, 'w') as f:
                yaml.dump(asdict(self.config), f, default_flow_style=False)

            # Restart service if running
            if self.is_running():
                self.restart_geth()

            logger.info("Configuration updated successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to update configuration: {e}")
            return False

    def cleanup(self, keep_data: bool = False) -> bool:
        """Remove Geth installation"""
        try:
            if self.is_running():
                self.stop_geth()

            # Remove systemd service
            if os.path.exists(self.systemd_service):
                subprocess.run(["systemctl", "disable", "geth"], check=False)
                subprocess.run(["systemctl", "daemon-reload"], check=True)
                os.remove(self.systemd_service)

            # Remove binary
            if os.path.exists("/usr/local/bin/geth"):
                os.remove("/usr/local/bin/geth")

            # Remove directories
            if not keep_data:
                import shutil
                if self.base_dir.exists():
                    shutil.rmtree(self.base_dir)
                if self.config_dir.exists():
                    shutil.rmtree(self.config_dir)
            else:
                # Keep data but remove installation
                if os.path.exists(self.bin_dir):
                    shutil.rmtree(self.bin_dir)

            logger.info("Geth cleanup completed")
            return True

        except Exception as e:
            logger.error(f"Failed to cleanup Geth: {e}")
            return False

    def get_logs(self, lines: int = 100, follow: bool = False) -> str:
        """Get Geth logs"""
        try:
            cmd = ["journalctl", "-u", "geth", "-n", str(lines)]
            if follow:
                cmd.append("-f")

            result = subprocess.run(cmd, capture_output=True, text=True)
            return result.stdout if result.returncode == 0 else "No logs available"
        except Exception as e:
            logger.error(f"Failed to get logs: {e}")
            return f"Error: {e}"

def main():
    """Main CLI interface"""
    parser = argparse.ArgumentParser(description="Geth Manager")
    parser.add_argument("action", choices=[
        "install", "uninstall", "start", "stop", "restart", "status",
        "configure", "optimize", "backup", "restore", "logs", "setup"
    ], help="Action to perform")
    parser.add_argument("--version", help="Geth version to install")
    parser.add_argument("--network", choices=[n.value for n in GethNetwork],
                       default="mainnet", help="Network configuration")
    parser.add_argument("--sync-mode", choices=[m.value for m in SyncMode],
                       default="snap", help="Sync mode")
    parser.add_argument("--config", default="/etc/geth/config.yaml",
                       help="Configuration file path")
    parser.add_argument("--backup-path", help="Backup file path")
    parser.add_argument("--lines", type=int, default=100, help="Number of log lines")
    parser.add_argument("--follow", action="store_true", help="Follow logs")

    args = parser.parse_args()

    manager = GethManager(args.config)

    if args.action == "setup":
        print("🚀 Setting up Geth Manager")
        manager.create_default_config(GethNetwork(args.network))
        manager.config.sync_mode = SyncMode(args.sync_mode)

        print(f"📦 Installing Geth...")
        if manager.install_geth(args.version):
            print("✅ Geth installed successfully")
        else:
            print("❌ Geth installation failed")
            sys.exit(1)

        print(f"🔧 Creating systemd service...")
        if manager.create_systemd_service():
            print("✅ Systemd service created")
        else:
            print("❌ Systemd service creation failed")
            sys.exit(1)

        print(f"🚀 Starting Geth...")
        if manager.start_geth():
            print("✅ Geth started successfully")
        else:
            print("❌ Geth start failed")
            sys.exit(1)

        print("🎉 Geth setup completed!")

    elif args.action == "install":
        if manager.install_geth(args.version):
            print("✅ Geth installed successfully")
        else:
            print("❌ Geth installation failed")

    elif args.action == "uninstall":
        if manager.cleanup():
            print("✅ Geth uninstalled successfully")
        else:
            print("❌ Geth uninstallation failed")

    elif args.action == "start":
        if manager.start_geth():
            print("✅ Geth started successfully")
        else:
            print("❌ Geth start failed")

    elif args.action == "stop":
        if manager.stop_geth():
            print("✅ Geth stopped successfully")
        else:
            print("❌ Geth stop failed")

    elif args.action == "restart":
        if manager.restart_geth():
            print("✅ Geth restarted successfully")
        else:
            print("❌ Geth restart failed")

    elif args.action == "status":
        manager.load_config()
        status = manager.get_status()

        print("📊 Geth Status Report")
        print("=" * 50)
        print(f"Installed: {'✅' if status.is_installed else '❌'}")
        print(f"Running: {'✅' if status.is_running else '❌'}")
        print(f"Version: {status.version or 'N/A'}")
        print(f"Sync Progress: {status.sync_progress:.1f}%" if status.sync_progress else "Sync Progress: N/A")
        print(f"Current Block: {status.current_block or 'N/A'}")
        print(f"Highest Block: {status.highest_block or 'N/A'}")
        print(f"Peer Count: {status.peer_count}")
        print(f"CPU Usage: {status.cpu_usage:.1f}%")
        print(f"Memory Usage: {status.memory_usage:.1f}%")
        print(f"Disk Usage: {status.disk_usage:.1f}GB")
        print(f"RPC Available: {'✅' if status.rpc_available else '❌'}")

    elif args.action == "configure":
        # Interactive configuration
        print("🔧 Configuration update not implemented yet")

    elif args.action == "optimize":
        manager.load_config()
        optimizations = manager.optimize_performance()

        print("🔧 Performance Optimization Report")
        print("=" * 50)

        if "optimizations" in optimizations and optimizations["optimizations"]:
            for opt in optimizations["optimizations"]:
                print(f"⚠️  {opt['issue']}")
                print(f"   Current: {opt['current']}")
                print(f"   Suggestion: {opt['suggestion']}")
                print(f"   Action: {opt['action']}")
                print()
        else:
            print("✅ No optimizations needed")

    elif args.action == "backup":
        if manager.backup_data(args.backup_path):
            print("✅ Backup created successfully")
        else:
            print("❌ Backup failed")

    elif args.action == "restore":
        if args.backup_path and manager.restore_data(args.backup_path):
            print("✅ Data restored successfully")
        else:
            print("❌ Restore failed")

    elif args.action == "logs":
        manager.load_config()
        logs = manager.get_logs(args.lines, args.follow)
        print(logs)

if __name__ == "__main__":
    main()