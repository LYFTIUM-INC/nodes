#!/usr/bin/env python3
"""
Comprehensive Node Recovery Runbook System
Automated recovery procedures for common blockchain node failures
"""

import json
import time
import subprocess
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional, Callable
import yaml
import psutil
import asyncio
import aiohttp

class NodeRecoveryRunbook:
    def __init__(self, config_path: str = "/data/blockchain/nodes/maintenance/configs/recovery_config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.recovery_history = []
        
        # Register recovery procedures
        self.recovery_procedures = {
            'rpc_not_responding': self._recover_rpc_failure,
            'sync_stalled': self._recover_sync_stall,
            'high_memory_usage': self._recover_memory_issue,
            'disk_space_low': self._recover_disk_space,
            'peer_connection_issues': self._recover_peer_issues,
            'database_corruption': self._recover_database_corruption,
            'container_crashed': self._recover_container_crash,
            'service_not_running': self._recover_service_failure,
            'mev_boost_failure': self._recover_mev_boost,
            'consensus_client_issues': self._recover_consensus_client
        }
        
    def _load_config(self, config_path: str) -> Dict:
        """Load recovery configuration"""
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
            
    def _setup_logging(self) -> logging.Logger:
        """Setup logging"""
        logger = logging.getLogger('NodeRecovery')
        logger.setLevel(logging.INFO)
        
        handler = logging.FileHandler('/data/blockchain/nodes/maintenance/logs/recovery.log')
        handler.setLevel(logging.INFO)
        
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        
        logger.addHandler(handler)
        
        # Also log to console for immediate feedback
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
        
        return logger
        
    async def diagnose_and_recover(self, chain: str, symptoms: List[str] = None) -> Dict[str, Any]:
        """Main recovery orchestrator - diagnose issues and attempt recovery"""
        recovery_session = {
            'chain': chain,
            'start_time': datetime.now().isoformat(),
            'symptoms': symptoms or [],
            'diagnosis': [],
            'recovery_actions': [],
            'success': False,
            'error_message': None
        }
        
        try:
            self.logger.info(f"Starting recovery session for {chain}")
            
            # If symptoms not provided, perform automatic diagnosis
            if not symptoms:
                diagnosis_result = await self._diagnose_node_issues(chain)
                recovery_session['diagnosis'] = diagnosis_result
                symptoms = [issue['type'] for issue in diagnosis_result if issue['severity'] in ['critical', 'warning']]
                recovery_session['symptoms'] = symptoms
                
            # Execute recovery procedures for each symptom
            for symptom in symptoms:
                if symptom in self.recovery_procedures:
                    self.logger.info(f"Executing recovery procedure for: {symptom}")
                    
                    recovery_result = await self.recovery_procedures[symptom](chain)
                    recovery_session['recovery_actions'].append({
                        'symptom': symptom,
                        'timestamp': datetime.now().isoformat(),
                        'result': recovery_result
                    })
                    
                    if not recovery_result.get('success', False):
                        self.logger.warning(f"Recovery failed for {symptom}: {recovery_result.get('error')}")
                else:
                    self.logger.warning(f"No recovery procedure available for symptom: {symptom}")
                    
            # Verify recovery success
            verification_result = await self._verify_recovery(chain)
            recovery_session['verification'] = verification_result
            recovery_session['success'] = verification_result.get('overall_health', 'unhealthy') == 'healthy'
            
            if recovery_session['success']:
                self.logger.info(f"Recovery successful for {chain}")
            else:
                self.logger.error(f"Recovery failed for {chain}")
                
        except Exception as e:
            recovery_session['error_message'] = str(e)
            self.logger.error(f"Recovery session failed: {str(e)}")
            
        # Store recovery history
        self.recovery_history.append(recovery_session)
        self._save_recovery_history()
        
        return recovery_session
        
    async def _diagnose_node_issues(self, chain: str) -> List[Dict[str, Any]]:
        """Comprehensive node diagnosis"""
        issues = []
        
        try:
            # Check RPC connectivity
            rpc_issue = await self._check_rpc_health(chain)
            if rpc_issue:
                issues.append(rpc_issue)
                
            # Check sync status
            sync_issue = await self._check_sync_health(chain)
            if sync_issue:
                issues.append(sync_issue)
                
            # Check system resources
            resource_issues = self._check_resource_health(chain)
            issues.extend(resource_issues)
            
            # Check process status
            process_issue = self._check_process_health(chain)
            if process_issue:
                issues.append(process_issue)
                
            # Check disk space
            disk_issue = self._check_disk_health(chain)
            if disk_issue:
                issues.append(disk_issue)
                
            # Check peer connectivity
            peer_issue = await self._check_peer_health(chain)
            if peer_issue:
                issues.append(peer_issue)
                
        except Exception as e:
            issues.append({
                'type': 'diagnostic_failure',
                'severity': 'critical',
                'message': f'Diagnosis failed: {str(e)}'
            })
            
        return issues
        
    async def _check_rpc_health(self, chain: str) -> Optional[Dict[str, Any]]:
        """Check RPC endpoint health"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            
            if not rpc_url:
                return None
                
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "web3_clientVersion", "params": [], "id": 1}
                
                try:
                    async with session.post(rpc_url, json=payload, timeout=10) as response:
                        if response.status != 200:
                            return {
                                'type': 'rpc_not_responding',
                                'severity': 'critical',
                                'message': f'RPC returned status {response.status}'
                            }
                        
                        data = await response.json()
                        if 'error' in data:
                            return {
                                'type': 'rpc_not_responding',
                                'severity': 'critical',
                                'message': f'RPC error: {data["error"]}'
                            }
                            
                except asyncio.TimeoutError:
                    return {
                        'type': 'rpc_not_responding',
                        'severity': 'critical',
                        'message': 'RPC request timeout'
                    }
                    
        except Exception as e:
            return {
                'type': 'rpc_not_responding',
                'severity': 'critical',
                'message': f'RPC check failed: {str(e)}'
            }
            
        return None
        
    async def _check_sync_health(self, chain: str) -> Optional[Dict[str, Any]]:
        """Check synchronization health"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            
            if not rpc_url:
                return None
                
            async with aiohttp.ClientSession() as session:
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
                                progress = (current / highest) * 100
                                if progress < 99:
                                    return {
                                        'type': 'sync_stalled',
                                        'severity': 'warning',
                                        'message': f'Sync progress: {progress:.2f}%'
                                    }
                                    
        except Exception as e:
            return {
                'type': 'sync_stalled',
                'severity': 'warning',
                'message': f'Sync check failed: {str(e)}'
            }
            
        return None
        
    def _check_resource_health(self, chain: str) -> List[Dict[str, Any]]:
        """Check system resource health"""
        issues = []
        
        try:
            # Memory usage
            memory = psutil.virtual_memory()
            if memory.percent > 90:
                issues.append({
                    'type': 'high_memory_usage',
                    'severity': 'critical',
                    'message': f'Memory usage: {memory.percent}%'
                })
            elif memory.percent > 85:
                issues.append({
                    'type': 'high_memory_usage',
                    'severity': 'warning',
                    'message': f'Memory usage: {memory.percent}%'
                })
                
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            if cpu_percent > 95:
                issues.append({
                    'type': 'high_cpu_usage',
                    'severity': 'warning',
                    'message': f'CPU usage: {cpu_percent}%'
                })
                
        except Exception as e:
            issues.append({
                'type': 'resource_check_failed',
                'severity': 'warning',
                'message': f'Resource check failed: {str(e)}'
            })
            
        return issues
        
    def _check_process_health(self, chain: str) -> Optional[Dict[str, Any]]:
        """Check node process health"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            container_name = chain_config.get('container_name')
            process_name = chain_config.get('process_name')
            
            if container_name:
                # Check Docker container
                result = subprocess.run(
                    ['docker', 'ps', '--filter', f'name={container_name}', '--format', '{{.Status}}'],
                    capture_output=True, text=True, timeout=30
                )
                
                if result.returncode != 0 or not result.stdout.strip():
                    return {
                        'type': 'container_crashed',
                        'severity': 'critical',
                        'message': f'Container {container_name} not running'
                    }
                    
            elif process_name:
                # Check system process
                for proc in psutil.process_iter(['pid', 'name']):
                    if process_name in proc.info['name']:
                        return None  # Process found, healthy
                        
                return {
                    'type': 'service_not_running',
                    'severity': 'critical',
                    'message': f'Process {process_name} not found'
                }
                
        except Exception as e:
            return {
                'type': 'process_check_failed',
                'severity': 'warning',
                'message': f'Process check failed: {str(e)}'
            }
            
        return None
        
    def _check_disk_health(self, chain: str) -> Optional[Dict[str, Any]]:
        """Check disk space health"""
        try:
            disk_usage = psutil.disk_usage('/data/blockchain/nodes')
            free_gb = disk_usage.free / (1024**3)
            percent_used = (disk_usage.used / disk_usage.total) * 100
            
            if free_gb < 5:
                return {
                    'type': 'disk_space_low',
                    'severity': 'critical',
                    'message': f'Only {free_gb:.2f} GB free space remaining'
                }
            elif percent_used > 90:
                return {
                    'type': 'disk_space_low',
                    'severity': 'warning',
                    'message': f'Disk {percent_used:.1f}% full'
                }
                
        except Exception as e:
            return {
                'type': 'disk_check_failed',
                'severity': 'warning',
                'message': f'Disk check failed: {str(e)}'
            }
            
        return None
        
    async def _check_peer_health(self, chain: str) -> Optional[Dict[str, Any]]:
        """Check peer connectivity health"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            min_peers = chain_config.get('min_peers', 5)
            
            if not rpc_url:
                return None
                
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "net_peerCount", "params": [], "id": 1}
                
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        peer_count = int(data.get('result', '0'), 16)
                        
                        if peer_count == 0:
                            return {
                                'type': 'peer_connection_issues',
                                'severity': 'critical',
                                'message': 'No peers connected'
                            }
                        elif peer_count < min_peers:
                            return {
                                'type': 'peer_connection_issues',
                                'severity': 'warning',
                                'message': f'Only {peer_count} peers connected (minimum: {min_peers})'
                            }
                            
        except Exception as e:
            return {
                'type': 'peer_check_failed',
                'severity': 'warning',
                'message': f'Peer check failed: {str(e)}'
            }
            
        return None
        
    # Recovery Procedures
    
    async def _recover_rpc_failure(self, chain: str) -> Dict[str, Any]:
        """Recover from RPC failure"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            # Step 1: Check if service is running
            chain_config = self.config['chains'].get(chain, {})
            service_name = chain_config.get('service_name')
            
            if service_name:
                # Restart service
                self.logger.info(f"Restarting service: {service_name}")
                result = subprocess.run(['systemctl', 'restart', service_name], 
                                      capture_output=True, text=True, timeout=60)
                
                recovery_result['actions_taken'].append(f"Restarted service {service_name}")
                
                if result.returncode == 0:
                    # Wait for service to start
                    await asyncio.sleep(30)
                    
                    # Test RPC connectivity
                    rpc_health = await self._check_rpc_health(chain)
                    if not rpc_health:
                        recovery_result['success'] = True
                        recovery_result['actions_taken'].append("RPC connectivity restored")
                        return recovery_result
                        
            # Step 2: If service restart didn't work, try container restart
            container_name = chain_config.get('container_name')
            if container_name:
                self.logger.info(f"Restarting container: {container_name}")
                
                result = subprocess.run(['docker', 'restart', container_name], 
                                      capture_output=True, text=True, timeout=120)
                
                recovery_result['actions_taken'].append(f"Restarted container {container_name}")
                
                if result.returncode == 0:
                    await asyncio.sleep(60)  # Wait longer for container
                    
                    rpc_health = await self._check_rpc_health(chain)
                    if not rpc_health:
                        recovery_result['success'] = True
                        recovery_result['actions_taken'].append("RPC connectivity restored after container restart")
                        return recovery_result
                        
            recovery_result['error'] = "RPC still not responding after restart attempts"
            
        except Exception as e:
            recovery_result['error'] = f"Recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_sync_stall(self, chain: str) -> Dict[str, Any]:
        """Recover from sync stall"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            
            # Step 1: Add more peers
            self.logger.info(f"Attempting to add more peers for {chain}")
            
            if chain_config.get('add_peers_command'):
                result = subprocess.run(chain_config['add_peers_command'], 
                                      shell=True, capture_output=True, text=True, timeout=60)
                recovery_result['actions_taken'].append("Added additional peers")
                
            # Step 2: Clear peer cache
            peer_cache_path = chain_config.get('peer_cache_path')
            if peer_cache_path and Path(peer_cache_path).exists():
                self.logger.info(f"Clearing peer cache: {peer_cache_path}")
                Path(peer_cache_path).unlink()
                recovery_result['actions_taken'].append("Cleared peer cache")
                
            # Step 3: Restart with fast sync if available
            if chain_config.get('fast_sync_command'):
                self.logger.info(f"Initiating fast sync for {chain}")
                result = subprocess.run(chain_config['fast_sync_command'], 
                                      shell=True, capture_output=True, text=True, timeout=300)
                recovery_result['actions_taken'].append("Initiated fast sync")
                
            # Step 4: Wait and check sync progress
            await asyncio.sleep(300)  # Wait 5 minutes
            
            sync_health = await self._check_sync_health(chain)
            if not sync_health or sync_health.get('severity') != 'critical':
                recovery_result['success'] = True
                recovery_result['actions_taken'].append("Sync resumed")
            else:
                recovery_result['error'] = "Sync still stalled after recovery attempts"
                
        except Exception as e:
            recovery_result['error'] = f"Sync recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_memory_issue(self, chain: str) -> Dict[str, Any]:
        """Recover from high memory usage"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            # Step 1: Clear system caches
            self.logger.info("Clearing system caches")
            subprocess.run(['sync'], timeout=30)
            subprocess.run(['echo', '3', '>', '/proc/sys/vm/drop_caches'], shell=True, timeout=30)
            recovery_result['actions_taken'].append("Cleared system caches")
            
            # Step 2: Restart node with memory optimization
            chain_config = self.config['chains'].get(chain, {})
            service_name = chain_config.get('service_name')
            
            if service_name:
                # Update service with memory limits
                memory_limit = chain_config.get('memory_limit', '8G')
                self.logger.info(f"Restarting {service_name} with memory limit: {memory_limit}")
                
                # Create temporary systemd override
                override_dir = Path(f"/etc/systemd/system/{service_name}.service.d")
                override_dir.mkdir(parents=True, exist_ok=True)
                
                override_content = f"""[Service]
MemoryLimit={memory_limit}
OOMScoreAdjust=100
"""
                
                with open(override_dir / "memory-limit.conf", 'w') as f:
                    f.write(override_content)
                    
                subprocess.run(['systemctl', 'daemon-reload'], timeout=30)
                subprocess.run(['systemctl', 'restart', service_name], timeout=60)
                
                recovery_result['actions_taken'].append(f"Applied memory limit {memory_limit}")
                
            await asyncio.sleep(60)
            
            # Check if memory usage improved
            memory = psutil.virtual_memory()
            if memory.percent < 85:
                recovery_result['success'] = True
                recovery_result['actions_taken'].append(f"Memory usage reduced to {memory.percent}%")
            else:
                recovery_result['error'] = f"Memory usage still high: {memory.percent}%"
                
        except Exception as e:
            recovery_result['error'] = f"Memory recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_disk_space(self, chain: str) -> Dict[str, Any]:
        """Recover from low disk space"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            # Step 1: Clean up old logs
            self.logger.info("Cleaning up old logs")
            
            log_paths = [
                "/data/blockchain/nodes/logs/*.log.*",
                "/data/blockchain/nodes/logs/*.gz",
                "/tmp/blockchain-*"
            ]
            
            for pattern in log_paths:
                result = subprocess.run(['find', pattern.split('*')[0], '-name', pattern.split('/')[-1], 
                                       '-mtime', '+7', '-delete'], 
                                      capture_output=True, text=True, timeout=120)
                                      
            recovery_result['actions_taken'].append("Cleaned up old log files")
            
            # Step 2: Run log rotation
            from pathlib import Path
            import sys
            sys.path.append('/data/blockchain/nodes/maintenance/scripts')
            
            try:
                from log_rotation_manager import LogRotationManager
                log_manager = LogRotationManager()
                cleanup_result = log_manager.emergency_cleanup(target_free_gb=15)
                recovery_result['actions_taken'].append(f"Emergency cleanup freed {cleanup_result['space_freed_gb']:.2f} GB")
            except ImportError:
                self.logger.warning("Log rotation manager not available")
                
            # Step 3: Clean up temporary files
            temp_dirs = ["/tmp", "/var/tmp", "/data/blockchain/nodes/temp"]
            for temp_dir in temp_dirs:
                if Path(temp_dir).exists():
                    subprocess.run(['find', temp_dir, '-type', 'f', '-mtime', '+1', '-delete'], 
                                 capture_output=True, text=True, timeout=60)
                                 
            recovery_result['actions_taken'].append("Cleaned up temporary files")
            
            # Check disk space
            disk_usage = psutil.disk_usage('/data/blockchain/nodes')
            free_gb = disk_usage.free / (1024**3)
            
            if free_gb > 10:
                recovery_result['success'] = True
                recovery_result['actions_taken'].append(f"Disk space recovered: {free_gb:.2f} GB free")
            else:
                recovery_result['error'] = f"Insufficient disk space recovered: {free_gb:.2f} GB free"
                
        except Exception as e:
            recovery_result['error'] = f"Disk space recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_peer_issues(self, chain: str) -> Dict[str, Any]:
        """Recover from peer connectivity issues"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            
            # Step 1: Add bootstrap nodes
            bootstrap_nodes = chain_config.get('bootstrap_nodes', [])
            if bootstrap_nodes:
                self.logger.info(f"Adding bootstrap nodes for {chain}")
                
                for node in bootstrap_nodes:
                    add_peer_cmd = chain_config.get('add_peer_command', '').format(peer=node)
                    if add_peer_cmd:
                        subprocess.run(add_peer_cmd, shell=True, capture_output=True, timeout=30)
                        
                recovery_result['actions_taken'].append("Added bootstrap nodes")
                
            # Step 2: Reset network configuration
            if chain_config.get('reset_network_command'):
                self.logger.info(f"Resetting network configuration for {chain}")
                result = subprocess.run(chain_config['reset_network_command'], 
                                      shell=True, capture_output=True, text=True, timeout=60)
                recovery_result['actions_taken'].append("Reset network configuration")
                
            # Step 3: Restart networking service
            service_name = chain_config.get('service_name')
            if service_name:
                subprocess.run(['systemctl', 'restart', service_name], timeout=60)
                recovery_result['actions_taken'].append(f"Restarted {service_name}")
                
            await asyncio.sleep(120)  # Wait for peer connections
            
            # Check peer count
            peer_health = await self._check_peer_health(chain)
            if not peer_health or peer_health.get('severity') != 'critical':
                recovery_result['success'] = True
                recovery_result['actions_taken'].append("Peer connectivity restored")
            else:
                recovery_result['error'] = "Still insufficient peer connections"
                
        except Exception as e:
            recovery_result['error'] = f"Peer recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_database_corruption(self, chain: str) -> Dict[str, Any]:
        """Recover from database corruption"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            
            self.logger.warning(f"Attempting database recovery for {chain}")
            
            # Step 1: Stop the node
            service_name = chain_config.get('service_name')
            if service_name:
                subprocess.run(['systemctl', 'stop', service_name], timeout=60)
                recovery_result['actions_taken'].append(f"Stopped {service_name}")
                
            # Step 2: Backup corrupted database
            db_path = chain_config.get('database_path')
            if db_path and Path(db_path).exists():
                backup_path = f"{db_path}.corrupted.{int(time.time())}"
                shutil.move(db_path, backup_path)
                recovery_result['actions_taken'].append(f"Backed up corrupted database to {backup_path}")
                
            # Step 3: Restore from backup or resync
            if chain_config.get('restore_command'):
                self.logger.info(f"Restoring database from backup for {chain}")
                result = subprocess.run(chain_config['restore_command'], 
                                      shell=True, capture_output=True, text=True, timeout=1800)
                recovery_result['actions_taken'].append("Restored database from backup")
            else:
                # Trigger resync
                self.logger.info(f"Triggering resync for {chain}")
                if chain_config.get('resync_command'):
                    subprocess.run(chain_config['resync_command'], shell=True, timeout=300)
                    recovery_result['actions_taken'].append("Triggered database resync")
                    
            # Step 4: Restart node
            if service_name:
                subprocess.run(['systemctl', 'start', service_name], timeout=60)
                recovery_result['actions_taken'].append(f"Restarted {service_name}")
                
            await asyncio.sleep(120)  # Wait for startup
            
            # Check if node is responsive
            rpc_health = await self._check_rpc_health(chain)
            if not rpc_health:
                recovery_result['success'] = True
                recovery_result['actions_taken'].append("Database recovery successful")
            else:
                recovery_result['error'] = "Node still not responsive after database recovery"
                
        except Exception as e:
            recovery_result['error'] = f"Database recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_container_crash(self, chain: str) -> Dict[str, Any]:
        """Recover from container crash"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            container_name = chain_config.get('container_name')
            
            if not container_name:
                recovery_result['error'] = "No container name configured"
                return recovery_result
                
            self.logger.info(f"Recovering crashed container: {container_name}")
            
            # Step 1: Check container status
            result = subprocess.run(['docker', 'ps', '-a', '--filter', f'name={container_name}', 
                                   '--format', '{{.Status}}'], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.stdout.strip():
                recovery_result['actions_taken'].append(f"Container status: {result.stdout.strip()}")
                
            # Step 2: Remove crashed container
            subprocess.run(['docker', 'rm', '-f', container_name], 
                         capture_output=True, text=True, timeout=60)
            recovery_result['actions_taken'].append(f"Removed crashed container {container_name}")
            
            # Step 3: Start new container
            if chain_config.get('docker_run_command'):
                self.logger.info(f"Starting new container for {chain}")
                result = subprocess.run(chain_config['docker_run_command'], 
                                      shell=True, capture_output=True, text=True, timeout=120)
                
                if result.returncode == 0:
                    recovery_result['actions_taken'].append("Started new container")
                    
                    await asyncio.sleep(60)  # Wait for container startup
                    
                    # Check if container is running
                    result = subprocess.run(['docker', 'ps', '--filter', f'name={container_name}', 
                                           '--format', '{{.Status}}'], 
                                          capture_output=True, text=True, timeout=30)
                    
                    if result.stdout.strip():
                        recovery_result['success'] = True
                        recovery_result['actions_taken'].append("Container recovery successful")
                    else:
                        recovery_result['error'] = "New container failed to start"
                else:
                    recovery_result['error'] = f"Failed to start container: {result.stderr}"
            else:
                recovery_result['error'] = "No docker run command configured"
                
        except Exception as e:
            recovery_result['error'] = f"Container recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_service_failure(self, chain: str) -> Dict[str, Any]:
        """Recover from service failure"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            service_name = chain_config.get('service_name')
            
            if not service_name:
                recovery_result['error'] = "No service name configured"
                return recovery_result
                
            self.logger.info(f"Recovering failed service: {service_name}")
            
            # Step 1: Check service status
            result = subprocess.run(['systemctl', 'status', service_name], 
                                  capture_output=True, text=True, timeout=30)
            recovery_result['actions_taken'].append(f"Service status checked")
            
            # Step 2: Reset failed state
            subprocess.run(['systemctl', 'reset-failed', service_name], timeout=30)
            recovery_result['actions_taken'].append("Reset failed state")
            
            # Step 3: Start service
            result = subprocess.run(['systemctl', 'start', service_name], 
                                  capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                recovery_result['actions_taken'].append(f"Started service {service_name}")
                
                await asyncio.sleep(30)
                
                # Verify service is running
                result = subprocess.run(['systemctl', 'is-active', service_name], 
                                      capture_output=True, text=True, timeout=30)
                
                if result.stdout.strip() == 'active':
                    recovery_result['success'] = True
                    recovery_result['actions_taken'].append("Service recovery successful")
                else:
                    recovery_result['error'] = f"Service not active: {result.stdout.strip()}"
            else:
                recovery_result['error'] = f"Failed to start service: {result.stderr}"
                
        except Exception as e:
            recovery_result['error'] = f"Service recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_mev_boost(self, chain: str) -> Dict[str, Any]:
        """Recover MEV-Boost failures"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            self.logger.info("Recovering MEV-Boost")
            
            # Step 1: Restart MEV-Boost service
            result = subprocess.run(['systemctl', 'restart', 'mev-boost'], 
                                  capture_output=True, text=True, timeout=60)
            recovery_result['actions_taken'].append("Restarted MEV-Boost service")
            
            # Step 2: Verify relay connections
            await asyncio.sleep(30)
            
            mev_boost_url = "http://localhost:18550"
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(f"{mev_boost_url}/eth/v1/builder/status", timeout=10) as response:
                        if response.status == 200:
                            recovery_result['success'] = True
                            recovery_result['actions_taken'].append("MEV-Boost connectivity restored")
                        else:
                            recovery_result['error'] = f"MEV-Boost returned status {response.status}"
            except Exception as e:
                recovery_result['error'] = f"MEV-Boost still not responding: {str(e)}"
                
        except Exception as e:
            recovery_result['error'] = f"MEV-Boost recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _recover_consensus_client(self, chain: str) -> Dict[str, Any]:
        """Recover consensus client issues"""
        recovery_result = {
            'success': False,
            'actions_taken': [],
            'error': None
        }
        
        try:
            self.logger.info("Recovering consensus client")
            
            # Step 1: Restart beacon chain client
            beacon_service = "lighthouse-beacon"  # Default, should be configurable
            result = subprocess.run(['systemctl', 'restart', beacon_service], 
                                  capture_output=True, text=True, timeout=60)
            recovery_result['actions_taken'].append(f"Restarted {beacon_service}")
            
            await asyncio.sleep(60)
            
            # Step 2: Check consensus sync
            beacon_url = "http://localhost:5052"  # Default Lighthouse URL
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(f"{beacon_url}/eth/v1/node/syncing", timeout=10) as response:
                        if response.status == 200:
                            data = await response.json()
                            if not data.get('data', {}).get('is_syncing', True):
                                recovery_result['success'] = True
                                recovery_result['actions_taken'].append("Consensus client sync restored")
                            else:
                                recovery_result['error'] = "Consensus client still syncing"
                        else:
                            recovery_result['error'] = f"Consensus client returned status {response.status}"
            except Exception as e:
                recovery_result['error'] = f"Consensus client check failed: {str(e)}"
                
        except Exception as e:
            recovery_result['error'] = f"Consensus client recovery failed: {str(e)}"
            
        return recovery_result
        
    async def _verify_recovery(self, chain: str) -> Dict[str, Any]:
        """Verify that recovery was successful"""
        verification_result = {
            'timestamp': datetime.now().isoformat(),
            'overall_health': 'healthy',
            'checks': {}
        }
        
        try:
            # Run basic health checks
            issues = await self._diagnose_node_issues(chain)
            
            critical_issues = [issue for issue in issues if issue.get('severity') == 'critical']
            warning_issues = [issue for issue in issues if issue.get('severity') == 'warning']
            
            verification_result['checks'] = {
                'critical_issues': len(critical_issues),
                'warning_issues': len(warning_issues),
                'total_issues': len(issues)
            }
            
            if critical_issues:
                verification_result['overall_health'] = 'critical'
            elif warning_issues:
                verification_result['overall_health'] = 'warning'
                
        except Exception as e:
            verification_result['overall_health'] = 'unknown'
            verification_result['error'] = str(e)
            
        return verification_result
        
    def _save_recovery_history(self):
        """Save recovery history to file"""
        try:
            history_file = Path("/data/blockchain/nodes/maintenance/logs/recovery_history.json")
            with open(history_file, 'w') as f:
                json.dump(self.recovery_history, f, indent=2)
        except Exception as e:
            self.logger.error(f"Failed to save recovery history: {str(e)}")

def main():
    """Main function for manual recovery"""
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python node_recovery_runbook.py <chain> [symptoms...]")
        sys.exit(1)
        
    chain = sys.argv[1]
    symptoms = sys.argv[2:] if len(sys.argv) > 2 else None
    
    runbook = NodeRecoveryRunbook()
    
    async def run_recovery():
        result = await runbook.diagnose_and_recover(chain, symptoms)
        
        print(f"\nRecovery Session Results for {chain}:")
        print(f"Success: {result['success']}")
        print(f"Actions taken: {len(result['recovery_actions'])}")
        
        for action in result['recovery_actions']:
            print(f"  - {action['symptom']}: {action['result'].get('actions_taken', [])}")
            
        if result.get('error_message'):
            print(f"Error: {result['error_message']}")
            
    asyncio.run(run_recovery())

if __name__ == "__main__":
    main()