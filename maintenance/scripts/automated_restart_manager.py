#!/usr/bin/env python3
"""
Automated Restart Manager for Blockchain Nodes
Intelligent restart system with failure detection, graceful shutdowns, and recovery procedures
"""

import json
import time
import asyncio
import subprocess
import logging
import psutil
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
import yaml
import aiohttp
import sqlite3
from enum import Enum

class RestartReason(Enum):
    HEALTH_CHECK_FAILURE = "health_check_failure"
    MEMORY_PRESSURE = "memory_pressure"
    HIGH_CPU_USAGE = "high_cpu_usage"
    SYNC_STALLED = "sync_stalled"
    RPC_UNRESPONSIVE = "rpc_unresponsive"
    PEER_DISCONNECTION = "peer_disconnection"
    SCHEDULED_MAINTENANCE = "scheduled_maintenance"
    MANUAL_REQUEST = "manual_request"
    CONFIGURATION_CHANGE = "configuration_change"
    SECURITY_INCIDENT = "security_incident"

class AutomatedRestartManager:
    def __init__(self, config_path: str = "/data/blockchain/nodes/maintenance/configs/restart_config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.restart_history_db = Path("/data/blockchain/nodes/maintenance/logs/restart_history.db")
        self._init_database()
        
        # Monitoring state
        self.monitoring_active = False
        self.restart_in_progress = set()
        self.last_restart_times = {}
        self.failure_counts = {}
        
    def _load_config(self, config_path: str) -> Dict:
        """Load restart configuration"""
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
            
    def _setup_logging(self) -> logging.Logger:
        """Setup logging"""
        logger = logging.getLogger('AutomatedRestartManager')
        logger.setLevel(logging.INFO)
        
        handler = logging.FileHandler('/data/blockchain/nodes/maintenance/logs/automated_restarts.log')
        handler.setLevel(logging.INFO)
        
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        
        logger.addHandler(handler)
        
        # Console handler for immediate feedback
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.WARNING)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
        
        return logger
        
    def _init_database(self):
        """Initialize restart history database"""
        conn = sqlite3.connect(str(self.restart_history_db))
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS restart_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                chain TEXT NOT NULL,
                reason TEXT NOT NULL,
                trigger_condition TEXT,
                restart_duration_seconds REAL,
                success BOOLEAN NOT NULL,
                error_message TEXT,
                recovery_actions TEXT,
                health_before TEXT,
                health_after TEXT
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS restart_statistics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                chain TEXT NOT NULL,
                total_restarts INTEGER,
                successful_restarts INTEGER,
                failed_restarts INTEGER,
                average_restart_time REAL,
                uptime_percentage REAL,
                mtbf_hours REAL
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS maintenance_windows (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                chain TEXT NOT NULL,
                start_time DATETIME NOT NULL,
                end_time DATETIME NOT NULL,
                maintenance_type TEXT NOT NULL,
                description TEXT,
                scheduled_by TEXT,
                status TEXT DEFAULT 'scheduled'
            )
        ''')
        
        conn.commit()
        conn.close()
        
    async def start_monitoring(self):
        """Start the automated restart monitoring"""
        self.monitoring_active = True
        self.logger.info("Starting automated restart monitoring")
        
        while self.monitoring_active:
            try:
                # Check all configured chains
                await self._monitor_all_chains()
                
                # Check for scheduled maintenance
                await self._check_scheduled_maintenance()
                
                # Update statistics
                self._update_statistics()
                
                # Wait before next check
                interval = self.config.get('monitoring', {}).get('check_interval_seconds', 60)
                await asyncio.sleep(interval)
                
            except Exception as e:
                self.logger.error(f"Error in monitoring loop: {str(e)}")
                await asyncio.sleep(10)
                
    async def _monitor_all_chains(self):
        """Monitor all configured chains for restart conditions"""
        chains = self.config.get('chains', {})
        
        for chain_name, chain_config in chains.items():
            if not chain_config.get('enabled', True):
                continue
                
            try:
                # Skip if restart already in progress
                if chain_name in self.restart_in_progress:
                    continue
                    
                # Check if restart is needed
                restart_needed, reason, details = await self._check_restart_conditions(chain_name, chain_config)
                
                if restart_needed:
                    # Check restart throttling
                    if self._should_throttle_restart(chain_name):
                        self.logger.warning(f"Restart throttled for {chain_name}: too many recent restarts")
                        continue
                        
                    # Perform restart
                    await self._perform_restart(chain_name, reason, details)
                    
            except Exception as e:
                self.logger.error(f"Error monitoring {chain_name}: {str(e)}")
                
    async def _check_restart_conditions(self, chain: str, config: Dict) -> Tuple[bool, RestartReason, Dict]:
        """Check if a chain needs to be restarted"""
        conditions = config.get('restart_conditions', {})
        
        # Health check failure
        if conditions.get('health_check_enabled', True):
            health_status = await self._check_chain_health(chain, config)
            if not health_status['healthy']:
                return True, RestartReason.HEALTH_CHECK_FAILURE, health_status
                
        # Memory pressure check
        if conditions.get('memory_check_enabled', True):
            memory_status = self._check_memory_pressure(chain, config)
            if memory_status['restart_needed']:
                return True, RestartReason.MEMORY_PRESSURE, memory_status
                
        # CPU usage check
        if conditions.get('cpu_check_enabled', True):
            cpu_status = self._check_cpu_usage(chain, config)
            if cpu_status['restart_needed']:
                return True, RestartReason.HIGH_CPU_USAGE, cpu_status
                
        # Sync stall check
        if conditions.get('sync_check_enabled', True):
            sync_status = await self._check_sync_status(chain, config)
            if sync_status['restart_needed']:
                return True, RestartReason.SYNC_STALLED, sync_status
                
        # RPC responsiveness check
        if conditions.get('rpc_check_enabled', True):
            rpc_status = await self._check_rpc_responsiveness(chain, config)
            if rpc_status['restart_needed']:
                return True, RestartReason.RPC_UNRESPONSIVE, rpc_status
                
        # Peer connectivity check
        if conditions.get('peer_check_enabled', True):
            peer_status = await self._check_peer_connectivity(chain, config)
            if peer_status['restart_needed']:
                return True, RestartReason.PEER_DISCONNECTION, peer_status
                
        return False, None, {}
        
    async def _check_chain_health(self, chain: str, config: Dict) -> Dict[str, Any]:
        """Check overall chain health"""
        health_status = {
            'healthy': True,
            'checks': {},
            'issues': []
        }
        
        try:
            rpc_url = config.get('rpc_url')
            if not rpc_url:
                health_status['healthy'] = False
                health_status['issues'].append('No RPC URL configured')
                return health_status
                
            # Basic RPC check
            async with aiohttp.ClientSession() as session:
                try:
                    payload = {"jsonrpc": "2.0", "method": "web3_clientVersion", "params": [], "id": 1}
                    async with session.post(rpc_url, json=payload, timeout=10) as response:
                        if response.status != 200:
                            health_status['healthy'] = False
                            health_status['issues'].append(f'RPC returned status {response.status}')
                        else:
                            data = await response.json()
                            if 'error' in data:
                                health_status['healthy'] = False
                                health_status['issues'].append(f'RPC error: {data["error"]}')
                            else:
                                health_status['checks']['rpc_responsive'] = True
                                
                except asyncio.TimeoutError:
                    health_status['healthy'] = False
                    health_status['issues'].append('RPC timeout')
                    
        except Exception as e:
            health_status['healthy'] = False
            health_status['issues'].append(f'Health check failed: {str(e)}')
            
        return health_status
        
    def _check_memory_pressure(self, chain: str, config: Dict) -> Dict[str, Any]:
        """Check for memory pressure conditions"""
        memory_status = {
            'restart_needed': False,
            'current_usage': 0,
            'threshold': 0,
            'details': {}
        }
        
        try:
            conditions = config.get('restart_conditions', {})
            memory_threshold = conditions.get('memory_threshold_percent', 90)
            
            # Check system memory
            memory = psutil.virtual_memory()
            memory_status['current_usage'] = memory.percent
            memory_status['threshold'] = memory_threshold
            
            if memory.percent > memory_threshold:
                memory_status['restart_needed'] = True
                memory_status['details']['reason'] = f'Memory usage {memory.percent}% > {memory_threshold}%'
                
            # Check process-specific memory if configured
            process_name = config.get('process_name')
            if process_name:
                process_memory = self._get_process_memory_usage(process_name)
                if process_memory and process_memory > conditions.get('process_memory_threshold_mb', 8192):
                    memory_status['restart_needed'] = True
                    memory_status['details']['process_memory_mb'] = process_memory
                    
        except Exception as e:
            self.logger.error(f"Memory check failed for {chain}: {str(e)}")
            
        return memory_status
        
    def _check_cpu_usage(self, chain: str, config: Dict) -> Dict[str, Any]:
        """Check for high CPU usage conditions"""
        cpu_status = {
            'restart_needed': False,
            'current_usage': 0,
            'threshold': 0,
            'details': {}
        }
        
        try:
            conditions = config.get('restart_conditions', {})
            cpu_threshold = conditions.get('cpu_threshold_percent', 95)
            sustained_duration = conditions.get('cpu_sustained_minutes', 10)
            
            # Check current CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_status['current_usage'] = cpu_percent
            cpu_status['threshold'] = cpu_threshold
            
            # For sustained high CPU, we'd need to track history
            # For now, just check current usage
            if cpu_percent > cpu_threshold:
                cpu_status['restart_needed'] = True
                cpu_status['details']['reason'] = f'CPU usage {cpu_percent}% > {cpu_threshold}%'
                
        except Exception as e:
            self.logger.error(f"CPU check failed for {chain}: {str(e)}")
            
        return cpu_status
        
    async def _check_sync_status(self, chain: str, config: Dict) -> Dict[str, Any]:
        """Check for sync stall conditions"""
        sync_status = {
            'restart_needed': False,
            'sync_progress': 100,
            'blocks_behind': 0,
            'details': {}
        }
        
        try:
            rpc_url = config.get('rpc_url')
            if not rpc_url:
                return sync_status
                
            conditions = config.get('restart_conditions', {})
            max_blocks_behind = conditions.get('max_blocks_behind', 100)
            
            async with aiohttp.ClientSession() as session:
                # Check sync status
                payload = {"jsonrpc": "2.0", "method": "eth_syncing", "params": [], "id": 1}
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        result = data.get('result')
                        
                        if result and result != False:
                            # Node is syncing
                            current = int(result.get('currentBlock', '0'), 16)
                            highest = int(result.get('highestBlock', '0'), 16)
                            
                            if highest > 0:
                                blocks_behind = highest - current
                                sync_progress = (current / highest) * 100
                                
                                sync_status['sync_progress'] = sync_progress
                                sync_status['blocks_behind'] = blocks_behind
                                
                                if blocks_behind > max_blocks_behind:
                                    sync_status['restart_needed'] = True
                                    sync_status['details']['reason'] = f'{blocks_behind} blocks behind > {max_blocks_behind}'
                                    
        except Exception as e:
            self.logger.error(f"Sync check failed for {chain}: {str(e)}")
            
        return sync_status
        
    async def _check_rpc_responsiveness(self, chain: str, config: Dict) -> Dict[str, Any]:
        """Check RPC responsiveness"""
        rpc_status = {
            'restart_needed': False,
            'latency_ms': 0,
            'max_latency': 0,
            'details': {}
        }
        
        try:
            rpc_url = config.get('rpc_url')
            if not rpc_url:
                return rpc_status
                
            conditions = config.get('restart_conditions', {})
            max_latency = conditions.get('max_rpc_latency_ms', 5000)
            
            start_time = time.time()
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1}
                
                try:
                    async with session.post(rpc_url, json=payload, timeout=max_latency/1000) as response:
                        latency = (time.time() - start_time) * 1000
                        rpc_status['latency_ms'] = latency
                        rpc_status['max_latency'] = max_latency
                        
                        if latency > max_latency:
                            rpc_status['restart_needed'] = True
                            rpc_status['details']['reason'] = f'RPC latency {latency:.1f}ms > {max_latency}ms'
                            
                except asyncio.TimeoutError:
                    rpc_status['restart_needed'] = True
                    rpc_status['details']['reason'] = f'RPC timeout > {max_latency}ms'
                    
        except Exception as e:
            self.logger.error(f"RPC check failed for {chain}: {str(e)}")
            
        return rpc_status
        
    async def _check_peer_connectivity(self, chain: str, config: Dict) -> Dict[str, Any]:
        """Check peer connectivity"""
        peer_status = {
            'restart_needed': False,
            'peer_count': 0,
            'min_peers': 0,
            'details': {}
        }
        
        try:
            rpc_url = config.get('rpc_url')
            if not rpc_url:
                return peer_status
                
            conditions = config.get('restart_conditions', {})
            min_peers = conditions.get('min_peers', 3)
            
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "net_peerCount", "params": [], "id": 1}
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        peer_count = int(data.get('result', '0'), 16)
                        
                        peer_status['peer_count'] = peer_count
                        peer_status['min_peers'] = min_peers
                        
                        if peer_count < min_peers:
                            peer_status['restart_needed'] = True
                            peer_status['details']['reason'] = f'Peer count {peer_count} < {min_peers}'
                            
        except Exception as e:
            self.logger.error(f"Peer check failed for {chain}: {str(e)}")
            
        return peer_status
        
    def _get_process_memory_usage(self, process_name: str) -> Optional[float]:
        """Get memory usage for a specific process"""
        try:
            for proc in psutil.process_iter(['pid', 'name', 'memory_info']):
                if process_name in proc.info['name']:
                    return proc.info['memory_info'].rss / (1024 * 1024)  # MB
        except:
            pass
        return None
        
    def _should_throttle_restart(self, chain: str) -> bool:
        """Check if restart should be throttled"""
        now = datetime.now()
        
        # Check recent restart count
        recent_restarts = self._get_recent_restart_count(chain, hours=1)
        max_restarts_per_hour = self.config.get('throttling', {}).get('max_restarts_per_hour', 3)
        
        if recent_restarts >= max_restarts_per_hour:
            return True
            
        # Check minimum time between restarts
        last_restart = self.last_restart_times.get(chain)
        if last_restart:
            min_interval = self.config.get('throttling', {}).get('min_restart_interval_minutes', 15)
            if (now - last_restart).total_seconds() < (min_interval * 60):
                return True
                
        return False
        
    def _get_recent_restart_count(self, chain: str, hours: int = 1) -> int:
        """Get number of recent restarts for a chain"""
        try:
            conn = sqlite3.connect(str(self.restart_history_db))
            cursor = conn.cursor()
            
            start_time = (datetime.now() - timedelta(hours=hours)).isoformat()
            cursor.execute('''
                SELECT COUNT(*) FROM restart_events
                WHERE chain = ? AND timestamp > ?
            ''', (chain, start_time))
            
            count = cursor.fetchone()[0]
            conn.close()
            
            return count
        except:
            return 0
            
    async def _perform_restart(self, chain: str, reason: RestartReason, details: Dict):
        """Perform the actual restart of a chain"""
        self.restart_in_progress.add(chain)
        start_time = datetime.now()
        
        restart_result = {
            'chain': chain,
            'reason': reason.value,
            'trigger_condition': json.dumps(details),
            'success': False,
            'error_message': None,
            'recovery_actions': [],
            'health_before': None,
            'health_after': None
        }
        
        try:
            self.logger.info(f"Starting restart for {chain} due to {reason.value}")
            
            # Get health status before restart
            chain_config = self.config['chains'].get(chain, {})
            restart_result['health_before'] = json.dumps(await self._check_chain_health(chain, chain_config))
            
            # Perform pre-restart actions
            await self._pre_restart_actions(chain, reason)
            
            # Execute restart
            success = await self._execute_restart(chain, chain_config)
            
            if success:
                # Wait for startup
                await asyncio.sleep(30)
                
                # Verify restart success
                post_restart_health = await self._check_chain_health(chain, chain_config)
                restart_result['health_after'] = json.dumps(post_restart_health)
                
                if post_restart_health['healthy']:
                    restart_result['success'] = True
                    self.logger.info(f"Restart successful for {chain}")
                    
                    # Reset failure count
                    self.failure_counts[chain] = 0
                else:
                    restart_result['error_message'] = f"Health check failed after restart: {post_restart_health['issues']}"
                    self.logger.error(f"Restart failed health check for {chain}: {post_restart_health['issues']}")
                    
            else:
                restart_result['error_message'] = "Restart command failed"
                self.logger.error(f"Restart command failed for {chain}")
                
        except Exception as e:
            restart_result['error_message'] = str(e)
            self.logger.error(f"Restart failed for {chain}: {str(e)}")
            
        finally:
            # Calculate duration
            duration = (datetime.now() - start_time).total_seconds()
            restart_result['restart_duration_seconds'] = duration
            
            # Update tracking
            self.last_restart_times[chain] = datetime.now()
            self.failure_counts[chain] = self.failure_counts.get(chain, 0) + (0 if restart_result['success'] else 1)
            
            # Store restart event
            self._store_restart_event(restart_result)
            
            # Send notifications
            await self._send_restart_notification(restart_result)
            
            # Remove from in-progress set
            self.restart_in_progress.discard(chain)
            
    async def _pre_restart_actions(self, chain: str, reason: RestartReason):
        """Perform actions before restart"""
        try:
            # Create backup if configured
            if self.config.get('pre_restart', {}).get('create_backup', False):
                self.logger.info(f"Creating backup before restart for {chain}")
                # Would call backup manager here
                
            # Graceful shutdown preparation
            if self.config.get('pre_restart', {}).get('graceful_shutdown', True):
                self.logger.info(f"Preparing graceful shutdown for {chain}")
                await self._prepare_graceful_shutdown(chain)
                
        except Exception as e:
            self.logger.error(f"Pre-restart actions failed for {chain}: {str(e)}")
            
    async def _prepare_graceful_shutdown(self, chain: str):
        """Prepare for graceful shutdown"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            
            if rpc_url:
                # Send any final transactions if needed
                # Stop accepting new transactions
                # Wait for pending operations to complete
                await asyncio.sleep(5)  # Brief pause for cleanup
                
        except Exception as e:
            self.logger.error(f"Graceful shutdown preparation failed for {chain}: {str(e)}")
            
    async def _execute_restart(self, chain: str, config: Dict) -> bool:
        """Execute the actual restart command"""
        try:
            restart_method = config.get('restart_method', 'systemd')
            
            if restart_method == 'systemd':
                return await self._restart_systemd_service(chain, config)
            elif restart_method == 'docker':
                return await self._restart_docker_container(chain, config)
            elif restart_method == 'script':
                return await self._restart_with_script(chain, config)
            else:
                self.logger.error(f"Unknown restart method: {restart_method}")
                return False
                
        except Exception as e:
            self.logger.error(f"Restart execution failed for {chain}: {str(e)}")
            return False
            
    async def _restart_systemd_service(self, chain: str, config: Dict) -> bool:
        """Restart using systemd"""
        try:
            service_name = config.get('service_name')
            if not service_name:
                self.logger.error(f"No service name configured for {chain}")
                return False
                
            # Graceful stop
            result = subprocess.run(['systemctl', 'stop', service_name], 
                                  capture_output=True, text=True, timeout=60)
            
            # Wait a moment
            await asyncio.sleep(5)
            
            # Start service
            result = subprocess.run(['systemctl', 'start', service_name], 
                                  capture_output=True, text=True, timeout=60)
            
            return result.returncode == 0
            
        except Exception as e:
            self.logger.error(f"Systemd restart failed for {chain}: {str(e)}")
            return False
            
    async def _restart_docker_container(self, chain: str, config: Dict) -> bool:
        """Restart using Docker"""
        try:
            container_name = config.get('container_name')
            if not container_name:
                self.logger.error(f"No container name configured for {chain}")
                return False
                
            # Graceful stop
            result = subprocess.run(['docker', 'stop', '-t', '30', container_name], 
                                  capture_output=True, text=True, timeout=60)
            
            # Start container
            result = subprocess.run(['docker', 'start', container_name], 
                                  capture_output=True, text=True, timeout=60)
            
            return result.returncode == 0
            
        except Exception as e:
            self.logger.error(f"Docker restart failed for {chain}: {str(e)}")
            return False
            
    async def _restart_with_script(self, chain: str, config: Dict) -> bool:
        """Restart using custom script"""
        try:
            script_path = config.get('restart_script')
            if not script_path:
                self.logger.error(f"No restart script configured for {chain}")
                return False
                
            result = subprocess.run([script_path, chain], 
                                  capture_output=True, text=True, timeout=300)
            
            return result.returncode == 0
            
        except Exception as e:
            self.logger.error(f"Script restart failed for {chain}: {str(e)}")
            return False
            
    def _store_restart_event(self, restart_result: Dict):
        """Store restart event in database"""
        try:
            conn = sqlite3.connect(str(self.restart_history_db))
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO restart_events 
                (chain, reason, trigger_condition, restart_duration_seconds, success, 
                 error_message, recovery_actions, health_before, health_after)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                restart_result['chain'],
                restart_result['reason'],
                restart_result['trigger_condition'],
                restart_result['restart_duration_seconds'],
                restart_result['success'],
                restart_result['error_message'],
                json.dumps(restart_result['recovery_actions']),
                restart_result['health_before'],
                restart_result['health_after']
            ))
            
            conn.commit()
            conn.close()
            
        except Exception as e:
            self.logger.error(f"Failed to store restart event: {str(e)}")
            
    async def _send_restart_notification(self, restart_result: Dict):
        """Send restart notifications"""
        try:
            notifications = self.config.get('notifications', {})
            
            if notifications.get('enabled', False):
                message = self._format_restart_notification(restart_result)
                
                # Email notification
                if notifications.get('email', {}).get('enabled', False):
                    await self._send_email_notification(message, restart_result)
                    
                # Webhook notification
                if notifications.get('webhook', {}).get('enabled', False):
                    await self._send_webhook_notification(message, restart_result)
                    
        except Exception as e:
            self.logger.error(f"Failed to send restart notification: {str(e)}")
            
    def _format_restart_notification(self, restart_result: Dict) -> str:
        """Format restart notification message"""
        chain = restart_result['chain']
        reason = restart_result['reason']
        success = restart_result['success']
        duration = restart_result['restart_duration_seconds']
        
        status = "SUCCESS" if success else "FAILED"
        
        message = f"""
Blockchain Node Restart Notification

Chain: {chain.upper()}
Status: {status}
Reason: {reason.replace('_', ' ').title()}
Duration: {duration:.1f} seconds
Timestamp: {datetime.now().isoformat()}
"""
        
        if not success:
            message += f"\nError: {restart_result.get('error_message', 'Unknown error')}"
            
        return message
        
    async def _send_email_notification(self, message: str, restart_result: Dict):
        """Send email notification"""
        # Implementation would depend on email configuration
        pass
        
    async def _send_webhook_notification(self, message: str, restart_result: Dict):
        """Send webhook notification"""
        try:
            webhook_config = self.config.get('notifications', {}).get('webhook', {})
            webhook_url = webhook_config.get('url')
            
            if webhook_url:
                payload = {
                    'text': message,
                    'restart_data': restart_result
                }
                
                async with aiohttp.ClientSession() as session:
                    async with session.post(webhook_url, json=payload, timeout=10):
                        pass
                        
        except Exception as e:
            self.logger.error(f"Webhook notification failed: {str(e)}")
            
    async def _check_scheduled_maintenance(self):
        """Check for scheduled maintenance windows"""
        try:
            conn = sqlite3.connect(str(self.restart_history_db))
            cursor = conn.cursor()
            
            now = datetime.now()
            cursor.execute('''
                SELECT chain, maintenance_type, description FROM maintenance_windows
                WHERE start_time <= ? AND end_time >= ? AND status = 'scheduled'
            ''', (now.isoformat(), now.isoformat()))
            
            scheduled_maintenance = cursor.fetchall()
            
            for chain, maintenance_type, description in scheduled_maintenance:
                if chain not in self.restart_in_progress:
                    self.logger.info(f"Performing scheduled maintenance for {chain}: {description}")
                    await self._perform_restart(chain, RestartReason.SCHEDULED_MAINTENANCE, 
                                               {'maintenance_type': maintenance_type, 'description': description})
                    
                    # Mark as completed
                    cursor.execute('''
                        UPDATE maintenance_windows 
                        SET status = 'completed' 
                        WHERE chain = ? AND start_time <= ? AND end_time >= ?
                    ''', (chain, now.isoformat(), now.isoformat()))
                    
            conn.commit()
            conn.close()
            
        except Exception as e:
            self.logger.error(f"Scheduled maintenance check failed: {str(e)}")
            
    def _update_statistics(self):
        """Update restart statistics"""
        try:
            conn = sqlite3.connect(str(self.restart_history_db))
            cursor = conn.cursor()
            
            # Get statistics for each chain
            for chain in self.config.get('chains', {}):
                # Get restart counts
                cursor.execute('''
                    SELECT 
                        COUNT(*) as total,
                        SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successful,
                        SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failed,
                        AVG(restart_duration_seconds) as avg_duration
                    FROM restart_events
                    WHERE chain = ? AND timestamp > datetime('now', '-24 hours')
                ''', (chain,))
                
                stats = cursor.fetchone()
                total, successful, failed, avg_duration = stats
                
                if total > 0:
                    uptime_percentage = (successful / total) * 100
                    
                    # Calculate MTBF (Mean Time Between Failures)
                    cursor.execute('''
                        SELECT MIN(timestamp), MAX(timestamp) FROM restart_events
                        WHERE chain = ? AND timestamp > datetime('now', '-7 days')
                    ''', (chain,))
                    
                    time_range = cursor.fetchone()
                    if time_range[0] and time_range[1]:
                        start_time = datetime.fromisoformat(time_range[0])
                        end_time = datetime.fromisoformat(time_range[1])
                        hours_span = (end_time - start_time).total_seconds() / 3600
                        mtbf = hours_span / failed if failed > 0 else hours_span
                    else:
                        mtbf = 168  # Default to 1 week
                        
                    # Store statistics
                    cursor.execute('''
                        INSERT INTO restart_statistics 
                        (chain, total_restarts, successful_restarts, failed_restarts, 
                         average_restart_time, uptime_percentage, mtbf_hours)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    ''', (chain, total, successful, failed, avg_duration or 0, uptime_percentage, mtbf))
                    
            conn.commit()
            conn.close()
            
        except Exception as e:
            self.logger.error(f"Statistics update failed: {str(e)}")
            
    def schedule_maintenance(self, chain: str, start_time: datetime, end_time: datetime, 
                           maintenance_type: str, description: str, scheduled_by: str = "system"):
        """Schedule maintenance restart"""
        try:
            conn = sqlite3.connect(str(self.restart_history_db))
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO maintenance_windows 
                (chain, start_time, end_time, maintenance_type, description, scheduled_by)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (chain, start_time.isoformat(), end_time.isoformat(), 
                  maintenance_type, description, scheduled_by))
            
            conn.commit()
            conn.close()
            
            self.logger.info(f"Scheduled maintenance for {chain}: {description}")
            
        except Exception as e:
            self.logger.error(f"Failed to schedule maintenance: {str(e)}")
            
    async def manual_restart(self, chain: str, reason: str = "Manual request") -> Dict[str, Any]:
        """Manually trigger restart for a specific chain"""
        if chain not in self.config.get('chains', {}):
            return {'success': False, 'error': f'Chain {chain} not configured'}
            
        if chain in self.restart_in_progress:
            return {'success': False, 'error': f'Restart already in progress for {chain}'}
            
        await self._perform_restart(chain, RestartReason.MANUAL_REQUEST, {'reason': reason})
        
        return {'success': True, 'message': f'Manual restart initiated for {chain}'}
        
    def get_restart_statistics(self, chain: Optional[str] = None, hours: int = 24) -> Dict[str, Any]:
        """Get restart statistics"""
        try:
            conn = sqlite3.connect(str(self.restart_history_db))
            cursor = conn.cursor()
            
            start_time = (datetime.now() - timedelta(hours=hours)).isoformat()
            
            if chain:
                cursor.execute('''
                    SELECT * FROM restart_statistics
                    WHERE chain = ? AND timestamp > ?
                    ORDER BY timestamp DESC LIMIT 1
                ''', (chain, start_time))
                
                result = cursor.fetchone()
                if result:
                    return {
                        'chain': result[1],
                        'total_restarts': result[2],
                        'successful_restarts': result[3],
                        'failed_restarts': result[4],
                        'average_restart_time': result[5],
                        'uptime_percentage': result[6],
                        'mtbf_hours': result[7]
                    }
            else:
                cursor.execute('''
                    SELECT chain, COUNT(*) as total, 
                           SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successful,
                           AVG(restart_duration_seconds) as avg_duration
                    FROM restart_events
                    WHERE timestamp > ?
                    GROUP BY chain
                ''', (start_time,))
                
                results = {}
                for row in cursor.fetchall():
                    chain_name, total, successful, avg_duration = row
                    results[chain_name] = {
                        'total_restarts': total,
                        'successful_restarts': successful,
                        'success_rate': (successful / total * 100) if total > 0 else 0,
                        'average_restart_time': avg_duration or 0
                    }
                    
                return results
                
            conn.close()
            
        except Exception as e:
            self.logger.error(f"Failed to get statistics: {str(e)}")
            return {}
            
    def stop_monitoring(self):
        """Stop the monitoring loop"""
        self.monitoring_active = False
        self.logger.info("Stopping automated restart monitoring")

def main():
    """Main function for manual testing"""
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python automated_restart_manager.py <command> [args...]")
        print("Commands:")
        print("  monitor - Start monitoring mode")
        print("  restart <chain> [reason] - Manual restart")
        print("  stats [chain] - Show restart statistics")
        print("  schedule <chain> <start_time> <end_time> <type> <description> - Schedule maintenance")
        sys.exit(1)
        
    command = sys.argv[1]
    manager = AutomatedRestartManager()
    
    if command == "monitor":
        asyncio.run(manager.start_monitoring())
    elif command == "restart" and len(sys.argv) >= 3:
        chain = sys.argv[2]
        reason = sys.argv[3] if len(sys.argv) > 3 else "Manual restart"
        result = asyncio.run(manager.manual_restart(chain, reason))
        print(json.dumps(result, indent=2))
    elif command == "stats":
        chain = sys.argv[2] if len(sys.argv) > 2 else None
        stats = manager.get_restart_statistics(chain)
        print(json.dumps(stats, indent=2))
    else:
        print(f"Unknown command: {command}")

if __name__ == "__main__":
    main()