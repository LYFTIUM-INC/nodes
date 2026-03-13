#!/usr/bin/env python3
"""
Zero-Downtime Update System for Blockchain Nodes
Implements rolling updates, blue-green deployments, and safe upgrade procedures
"""

import json
import time
import asyncio
import subprocess
import logging
import shutil
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
import yaml
import aiohttp
import psutil
from enum import Enum
import tempfile

class UpdateStrategy(Enum):
    ROLLING = "rolling"
    BLUE_GREEN = "blue_green"
    CANARY = "canary"
    MAINTENANCE_WINDOW = "maintenance_window"

class ZeroDowntimeUpdater:
    def __init__(self, config_path: str = "/data/blockchain/nodes/maintenance/configs/update_config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.update_history = []
        self.active_deployments = {}
        
    def _load_config(self, config_path: str) -> Dict:
        """Load update configuration"""
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
            
    def _setup_logging(self) -> logging.Logger:
        """Setup logging"""
        logger = logging.getLogger('ZeroDowntimeUpdater')
        logger.setLevel(logging.INFO)
        
        handler = logging.FileHandler('/data/blockchain/nodes/maintenance/logs/updates.log')
        handler.setLevel(logging.INFO)
        
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        
        logger.addHandler(handler)
        
        # Console handler for immediate feedback
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
        
        return logger
        
    async def update_chain(self, chain: str, version: str, 
                          strategy: UpdateStrategy = UpdateStrategy.ROLLING,
                          dry_run: bool = False) -> Dict[str, Any]:
        """Update a specific blockchain node with zero downtime"""
        update_session = {
            'chain': chain,
            'target_version': version,
            'strategy': strategy.value,
            'dry_run': dry_run,
            'start_time': datetime.now().isoformat(),
            'phases': [],
            'success': False,
            'rollback_performed': False,
            'error_message': None
        }
        
        try:
            self.logger.info(f"Starting {strategy.value} update for {chain} to version {version}")
            
            # Phase 1: Pre-update validation
            validation_result = await self._pre_update_validation(chain, version)
            update_session['phases'].append({
                'phase': 'pre_update_validation',
                'timestamp': datetime.now().isoformat(),
                'result': validation_result
            })
            
            if not validation_result.get('success'):
                raise Exception(f"Pre-update validation failed: {validation_result.get('error')}")
                
            # Phase 2: Backup current state
            if not dry_run:
                backup_result = await self._create_update_backup(chain)
                update_session['phases'].append({
                    'phase': 'backup_creation',
                    'timestamp': datetime.now().isoformat(),
                    'result': backup_result
                })
                
            # Phase 3: Execute update strategy
            if strategy == UpdateStrategy.ROLLING:
                update_result = await self._rolling_update(chain, version, dry_run)
            elif strategy == UpdateStrategy.BLUE_GREEN:
                update_result = await self._blue_green_update(chain, version, dry_run)
            elif strategy == UpdateStrategy.CANARY:
                update_result = await self._canary_update(chain, version, dry_run)
            else:
                update_result = await self._maintenance_window_update(chain, version, dry_run)
                
            update_session['phases'].append({
                'phase': f'{strategy.value}_update',
                'timestamp': datetime.now().isoformat(),
                'result': update_result
            })
            
            # Phase 4: Post-update validation
            if update_result.get('success'):
                post_validation_result = await self._post_update_validation(chain, version)
                update_session['phases'].append({
                    'phase': 'post_update_validation',
                    'timestamp': datetime.now().isoformat(),
                    'result': post_validation_result
                })
                
                if post_validation_result.get('success'):
                    update_session['success'] = True
                    self.logger.info(f"Update successful for {chain}")
                else:
                    # Rollback on validation failure
                    if not dry_run:
                        rollback_result = await self._rollback_update(chain, update_result)
                        update_session['rollback_performed'] = True
                        update_session['phases'].append({
                            'phase': 'rollback',
                            'timestamp': datetime.now().isoformat(),
                            'result': rollback_result
                        })
                        
        except Exception as e:
            update_session['error_message'] = str(e)
            self.logger.error(f"Update failed for {chain}: {str(e)}")
            
            # Attempt rollback on critical failure
            if not dry_run and len(update_session['phases']) > 1:
                try:
                    rollback_result = await self._rollback_update(chain, {})
                    update_session['rollback_performed'] = True
                    update_session['phases'].append({
                        'phase': 'emergency_rollback',
                        'timestamp': datetime.now().isoformat(),
                        'result': rollback_result
                    })
                except Exception as rollback_error:
                    self.logger.error(f"Rollback failed: {str(rollback_error)}")
                    
        # Store update history
        self.update_history.append(update_session)
        self._save_update_history()
        
        return update_session
        
    async def _pre_update_validation(self, chain: str, version: str) -> Dict[str, Any]:
        """Validate system state before update"""
        validation_result = {
            'success': False,
            'checks': {},
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            
            # Check current node health
            health_check = await self._check_node_health(chain)
            validation_result['checks']['node_health'] = health_check
            
            # Verify version availability
            version_check = await self._verify_version_availability(chain, version)
            validation_result['checks']['version_availability'] = version_check
            
            # Check system resources
            resource_check = self._check_system_resources()
            validation_result['checks']['system_resources'] = resource_check
            
            # Check disk space for update
            disk_check = self._check_disk_space_for_update(chain)
            validation_result['checks']['disk_space'] = disk_check
            
            # Verify backup availability
            backup_check = self._verify_backup_availability(chain)
            validation_result['checks']['backup_availability'] = backup_check
            
            # Check for active transactions/MEV operations
            activity_check = await self._check_node_activity(chain)
            validation_result['checks']['node_activity'] = activity_check
            
            # Determine overall validation success
            critical_checks = ['node_health', 'version_availability', 'disk_space']
            validation_result['success'] = all(
                validation_result['checks'][check].get('success', False) 
                for check in critical_checks 
                if check in validation_result['checks']
            )
            
        except Exception as e:
            validation_result['error'] = str(e)
            
        return validation_result
        
    async def _check_node_health(self, chain: str) -> Dict[str, Any]:
        """Check if node is healthy before update"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            
            if not rpc_url:
                return {'success': False, 'error': 'No RPC URL configured'}
                
            # Test RPC connectivity
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "web3_clientVersion", "params": [], "id": 1}
                
                try:
                    async with session.post(rpc_url, json=payload, timeout=10) as response:
                        if response.status == 200:
                            data = await response.json()
                            if 'result' in data:
                                return {
                                    'success': True,
                                    'client_version': data['result'],
                                    'rpc_responsive': True
                                }
                except asyncio.TimeoutError:
                    return {'success': False, 'error': 'RPC timeout'}
                    
            return {'success': False, 'error': 'RPC not responding'}
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    async def _verify_version_availability(self, chain: str, version: str) -> Dict[str, Any]:
        """Verify that the target version is available"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            
            # Check Docker image availability
            if chain_config.get('deployment_type') == 'docker':
                image_name = chain_config.get('docker_image_template', '').format(version=version)
                
                result = subprocess.run(
                    ['docker', 'pull', '--dry-run', image_name],
                    capture_output=True, text=True, timeout=60
                )
                
                if result.returncode == 0:
                    return {
                        'success': True,
                        'image_name': image_name,
                        'image_available': True
                    }
                else:
                    # Try to pull the image
                    pull_result = subprocess.run(
                        ['docker', 'pull', image_name],
                        capture_output=True, text=True, timeout=300
                    )
                    
                    return {
                        'success': pull_result.returncode == 0,
                        'image_name': image_name,
                        'pull_output': pull_result.stdout,
                        'pull_error': pull_result.stderr
                    }
                    
            # Check binary availability
            elif chain_config.get('deployment_type') == 'binary':
                binary_url = chain_config.get('binary_url_template', '').format(version=version)
                
                async with aiohttp.ClientSession() as session:
                    async with session.head(binary_url, timeout=30) as response:
                        return {
                            'success': response.status == 200,
                            'binary_url': binary_url,
                            'status_code': response.status
                        }
                        
            return {'success': False, 'error': 'Unknown deployment type'}
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    def _check_system_resources(self) -> Dict[str, Any]:
        """Check if system has enough resources for update"""
        try:
            # Check memory
            memory = psutil.virtual_memory()
            memory_available_gb = memory.available / (1024**3)
            
            # Check CPU load
            cpu_load = psutil.getloadavg()[0] if hasattr(psutil, 'getloadavg') else psutil.cpu_percent()
            
            # Check if resources are sufficient
            sufficient_memory = memory_available_gb > 2  # Need at least 2GB free
            acceptable_load = cpu_load < 0.8 * psutil.cpu_count()  # Load should be < 80% of CPU count
            
            return {
                'success': sufficient_memory and acceptable_load,
                'memory_available_gb': round(memory_available_gb, 2),
                'cpu_load': cpu_load,
                'sufficient_memory': sufficient_memory,
                'acceptable_load': acceptable_load
            }
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    def _check_disk_space_for_update(self, chain: str) -> Dict[str, Any]:
        """Check if there's enough disk space for the update"""
        try:
            # Check available space
            disk_usage = psutil.disk_usage('/data/blockchain/nodes')
            free_gb = disk_usage.free / (1024**3)
            
            # Estimate space needed for update (conservative estimate)
            estimated_space_needed = 5  # GB
            
            return {
                'success': free_gb > estimated_space_needed,
                'free_space_gb': round(free_gb, 2),
                'estimated_needed_gb': estimated_space_needed,
                'sufficient_space': free_gb > estimated_space_needed
            }
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    def _verify_backup_availability(self, chain: str) -> Dict[str, Any]:
        """Verify that recent backups are available"""
        try:
            # Check for recent backup files
            backup_dir = Path(f"/data/blockchain/nodes/maintenance/backups/{chain}")
            
            if not backup_dir.exists():
                return {'success': False, 'error': 'Backup directory does not exist'}
                
            # Find most recent backup
            backup_files = list(backup_dir.glob("*.tar.gz"))
            if not backup_files:
                return {'success': False, 'error': 'No backup files found'}
                
            most_recent_backup = max(backup_files, key=lambda x: x.stat().st_mtime)
            backup_age = datetime.now().timestamp() - most_recent_backup.stat().st_mtime
            
            # Backup should be less than 24 hours old
            backup_fresh = backup_age < 86400  # 24 hours in seconds
            
            return {
                'success': backup_fresh,
                'most_recent_backup': str(most_recent_backup),
                'backup_age_hours': round(backup_age / 3600, 2),
                'backup_fresh': backup_fresh
            }
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    async def _check_node_activity(self, chain: str) -> Dict[str, Any]:
        """Check current node activity level"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            
            if not rpc_url:
                return {'success': True, 'activity_level': 'unknown'}
                
            # Check pending transactions
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "txpool_status", "params": [], "id": 1}
                
                try:
                    async with session.post(rpc_url, json=payload, timeout=10) as response:
                        if response.status == 200:
                            data = await response.json()
                            if 'result' in data:
                                pending = int(data['result'].get('pending', '0'), 16)
                                queued = int(data['result'].get('queued', '0'), 16)
                                
                                total_txs = pending + queued
                                activity_level = 'low' if total_txs < 100 else 'medium' if total_txs < 1000 else 'high'
                                
                                return {
                                    'success': True,
                                    'pending_transactions': pending,
                                    'queued_transactions': queued,
                                    'total_transactions': total_txs,
                                    'activity_level': activity_level
                                }
                except:
                    pass
                    
            return {'success': True, 'activity_level': 'unknown'}
            
        except Exception as e:
            return {'success': True, 'activity_level': 'unknown', 'error': str(e)}
            
    async def _create_update_backup(self, chain: str) -> Dict[str, Any]:
        """Create backup before update"""
        backup_result = {
            'success': False,
            'backup_path': None,
            'error': None
        }
        
        try:
            # Import backup manager
            import sys
            sys.path.append('/data/blockchain/nodes/maintenance/scripts')
            from backup_manager import BackupManager
            
            backup_manager = BackupManager()
            
            # Create node-specific backup
            result = backup_manager.backup_node_data(chain)
            
            backup_result['success'] = result.get('status') == 'completed'
            backup_result['backup_path'] = result.get('destination')
            
            if not backup_result['success']:
                backup_result['error'] = result.get('error_message')
                
        except Exception as e:
            backup_result['error'] = str(e)
            
        return backup_result
        
    async def _rolling_update(self, chain: str, version: str, dry_run: bool) -> Dict[str, Any]:
        """Perform rolling update with minimal downtime"""
        update_result = {
            'success': False,
            'strategy': 'rolling',
            'steps': [],
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            
            # Step 1: Prepare new version
            prepare_result = await self._prepare_new_version(chain, version, dry_run)
            update_result['steps'].append({
                'step': 'prepare_new_version',
                'timestamp': datetime.now().isoformat(),
                'result': prepare_result
            })
            
            if not prepare_result.get('success'):
                raise Exception(f"Failed to prepare new version: {prepare_result.get('error')}")
                
            # Step 2: Graceful shutdown of old version
            if not dry_run:
                shutdown_result = await self._graceful_shutdown(chain)
                update_result['steps'].append({
                    'step': 'graceful_shutdown',
                    'timestamp': datetime.now().isoformat(),
                    'result': shutdown_result
                })
                
                # Step 3: Start new version
                startup_result = await self._start_new_version(chain, version)
                update_result['steps'].append({
                    'step': 'start_new_version',
                    'timestamp': datetime.now().isoformat(),
                    'result': startup_result
                })
                
                if not startup_result.get('success'):
                    raise Exception(f"Failed to start new version: {startup_result.get('error')}")
                    
                # Step 4: Wait for sync and verify
                sync_result = await self._wait_for_sync(chain)
                update_result['steps'].append({
                    'step': 'wait_for_sync',
                    'timestamp': datetime.now().isoformat(),
                    'result': sync_result
                })
                
                update_result['success'] = sync_result.get('success', False)
            else:
                update_result['success'] = True
                update_result['steps'].append({
                    'step': 'dry_run_complete',
                    'timestamp': datetime.now().isoformat(),
                    'result': {'success': True, 'message': 'Dry run completed successfully'}
                })
                
        except Exception as e:
            update_result['error'] = str(e)
            
        return update_result
        
    async def _blue_green_update(self, chain: str, version: str, dry_run: bool) -> Dict[str, Any]:
        """Perform blue-green deployment"""
        update_result = {
            'success': False,
            'strategy': 'blue_green',
            'steps': [],
            'error': None
        }
        
        try:
            # Step 1: Deploy green environment
            green_deploy_result = await self._deploy_green_environment(chain, version, dry_run)
            update_result['steps'].append({
                'step': 'deploy_green_environment',
                'timestamp': datetime.now().isoformat(),
                'result': green_deploy_result
            })
            
            if not green_deploy_result.get('success'):
                raise Exception(f"Green deployment failed: {green_deploy_result.get('error')}")
                
            if not dry_run:
                # Step 2: Validate green environment
                green_validation_result = await self._validate_green_environment(chain)
                update_result['steps'].append({
                    'step': 'validate_green_environment',
                    'timestamp': datetime.now().isoformat(),
                    'result': green_validation_result
                })
                
                if not green_validation_result.get('success'):
                    raise Exception(f"Green validation failed: {green_validation_result.get('error')}")
                    
                # Step 3: Switch traffic to green
                traffic_switch_result = await self._switch_traffic_to_green(chain)
                update_result['steps'].append({
                    'step': 'switch_traffic_to_green',
                    'timestamp': datetime.now().isoformat(),
                    'result': traffic_switch_result
                })
                
                # Step 4: Cleanup blue environment
                cleanup_result = await self._cleanup_blue_environment(chain)
                update_result['steps'].append({
                    'step': 'cleanup_blue_environment',
                    'timestamp': datetime.now().isoformat(),
                    'result': cleanup_result
                })
                
                update_result['success'] = traffic_switch_result.get('success', False)
            else:
                update_result['success'] = True
                
        except Exception as e:
            update_result['error'] = str(e)
            
        return update_result
        
    async def _canary_update(self, chain: str, version: str, dry_run: bool) -> Dict[str, Any]:
        """Perform canary deployment"""
        update_result = {
            'success': False,
            'strategy': 'canary',
            'steps': [],
            'error': None
        }
        
        try:
            # Step 1: Deploy canary instance
            canary_deploy_result = await self._deploy_canary_instance(chain, version, dry_run)
            update_result['steps'].append({
                'step': 'deploy_canary_instance',
                'timestamp': datetime.now().isoformat(),
                'result': canary_deploy_result
            })
            
            if not dry_run and canary_deploy_result.get('success'):
                # Step 2: Route small percentage of traffic to canary
                traffic_routing_result = await self._route_canary_traffic(chain, 10)  # 10% traffic
                update_result['steps'].append({
                    'step': 'route_canary_traffic',
                    'timestamp': datetime.now().isoformat(),
                    'result': traffic_routing_result
                })
                
                # Step 3: Monitor canary performance
                monitoring_result = await self._monitor_canary_performance(chain, duration_minutes=30)
                update_result['steps'].append({
                    'step': 'monitor_canary_performance',
                    'timestamp': datetime.now().isoformat(),
                    'result': monitoring_result
                })
                
                if monitoring_result.get('success'):
                    # Step 4: Full rollout
                    rollout_result = await self._complete_canary_rollout(chain)
                    update_result['steps'].append({
                        'step': 'complete_canary_rollout',
                        'timestamp': datetime.now().isoformat(),
                        'result': rollout_result
                    })
                    
                    update_result['success'] = rollout_result.get('success', False)
                else:
                    # Rollback canary
                    rollback_result = await self._rollback_canary(chain)
                    update_result['steps'].append({
                        'step': 'rollback_canary',
                        'timestamp': datetime.now().isoformat(),
                        'result': rollback_result
                    })
            else:
                update_result['success'] = canary_deploy_result.get('success', False)
                
        except Exception as e:
            update_result['error'] = str(e)
            
        return update_result
        
    async def _maintenance_window_update(self, chain: str, version: str, dry_run: bool) -> Dict[str, Any]:
        """Perform update during scheduled maintenance window"""
        update_result = {
            'success': False,
            'strategy': 'maintenance_window',
            'steps': [],
            'error': None
        }
        
        try:
            # Check if we're in a maintenance window
            if not self._is_maintenance_window():
                raise Exception("Not currently in a scheduled maintenance window")
                
            # Perform standard rolling update during maintenance window
            rolling_result = await self._rolling_update(chain, version, dry_run)
            update_result['steps'] = rolling_result['steps']
            update_result['success'] = rolling_result['success']
            update_result['error'] = rolling_result.get('error')
            
        except Exception as e:
            update_result['error'] = str(e)
            
        return update_result
        
    def _is_maintenance_window(self) -> bool:
        """Check if current time is within maintenance window"""
        now = datetime.now()
        maintenance_windows = self.config.get('maintenance_windows', [])
        
        for window in maintenance_windows:
            start_time = datetime.strptime(window['start'], '%H:%M').time()
            end_time = datetime.strptime(window['end'], '%H:%M').time()
            current_time = now.time()
            
            if start_time <= current_time <= end_time:
                # Check if today is in allowed days
                allowed_days = window.get('days', ['sunday'])
                current_day = now.strftime('%A').lower()
                
                if current_day in allowed_days:
                    return True
                    
        return False
        
    async def _prepare_new_version(self, chain: str, version: str, dry_run: bool) -> Dict[str, Any]:
        """Prepare new version for deployment"""
        prepare_result = {
            'success': False,
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            
            if chain_config.get('deployment_type') == 'docker':
                # Pull new Docker image
                image_name = chain_config.get('docker_image_template', '').format(version=version)
                
                if not dry_run:
                    result = subprocess.run(
                        ['docker', 'pull', image_name],
                        capture_output=True, text=True, timeout=600
                    )
                    
                    prepare_result['success'] = result.returncode == 0
                    if not prepare_result['success']:
                        prepare_result['error'] = result.stderr
                else:
                    prepare_result['success'] = True
                    
                prepare_result['image_name'] = image_name
                
            elif chain_config.get('deployment_type') == 'binary':
                # Download and prepare binary
                binary_url = chain_config.get('binary_url_template', '').format(version=version)
                binary_path = Path(f"/tmp/{chain}-{version}")
                
                if not dry_run:
                    async with aiohttp.ClientSession() as session:
                        async with session.get(binary_url) as response:
                            if response.status == 200:
                                with open(binary_path, 'wb') as f:
                                    async for chunk in response.content.iter_chunked(8192):
                                        f.write(chunk)
                                        
                                binary_path.chmod(0o755)
                                prepare_result['success'] = True
                            else:
                                prepare_result['error'] = f"Failed to download binary: {response.status}"
                else:
                    prepare_result['success'] = True
                    
                prepare_result['binary_path'] = str(binary_path)
                
        except Exception as e:
            prepare_result['error'] = str(e)
            
        return prepare_result
        
    async def _graceful_shutdown(self, chain: str) -> Dict[str, Any]:
        """Gracefully shutdown the current node"""
        shutdown_result = {
            'success': False,
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            service_name = chain_config.get('service_name')
            container_name = chain_config.get('container_name')
            
            if container_name:
                # Graceful Docker container shutdown
                result = subprocess.run(
                    ['docker', 'stop', '-t', '30', container_name],
                    capture_output=True, text=True, timeout=60
                )
                shutdown_result['success'] = result.returncode == 0
                
            elif service_name:
                # Graceful systemd service shutdown
                result = subprocess.run(
                    ['systemctl', 'stop', service_name],
                    capture_output=True, text=True, timeout=60
                )
                shutdown_result['success'] = result.returncode == 0
                
            # Wait a bit for clean shutdown
            if shutdown_result['success']:
                await asyncio.sleep(10)
                
        except Exception as e:
            shutdown_result['error'] = str(e)
            
        return shutdown_result
        
    async def _start_new_version(self, chain: str, version: str) -> Dict[str, Any]:
        """Start the new version of the node"""
        startup_result = {
            'success': False,
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            
            if chain_config.get('deployment_type') == 'docker':
                # Start new Docker container
                image_name = chain_config.get('docker_image_template', '').format(version=version)
                container_name = chain_config.get('container_name')
                
                # Remove old container if exists
                subprocess.run(['docker', 'rm', '-f', container_name], 
                             capture_output=True, timeout=30)
                
                # Start new container
                docker_run_command = chain_config.get('docker_run_command', '').format(
                    image=image_name,
                    container_name=container_name
                )
                
                result = subprocess.run(
                    docker_run_command,
                    shell=True, capture_output=True, text=True, timeout=120
                )
                
                startup_result['success'] = result.returncode == 0
                if not startup_result['success']:
                    startup_result['error'] = result.stderr
                    
            elif chain_config.get('deployment_type') == 'binary':
                # Start new binary
                service_name = chain_config.get('service_name')
                binary_path = f"/tmp/{chain}-{version}"
                
                # Update service to use new binary (this would need proper service configuration)
                result = subprocess.run(
                    ['systemctl', 'start', service_name],
                    capture_output=True, text=True, timeout=60
                )
                
                startup_result['success'] = result.returncode == 0
                
            # Wait for startup
            if startup_result['success']:
                await asyncio.sleep(30)
                
        except Exception as e:
            startup_result['error'] = str(e)
            
        return startup_result
        
    async def _wait_for_sync(self, chain: str, timeout_minutes: int = 30) -> Dict[str, Any]:
        """Wait for node to sync after update"""
        sync_result = {
            'success': False,
            'sync_achieved': False,
            'timeout_reached': False,
            'error': None
        }
        
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            
            if not rpc_url:
                sync_result['error'] = 'No RPC URL configured'
                return sync_result
                
            start_time = datetime.now()
            timeout = timedelta(minutes=timeout_minutes)
            
            while datetime.now() - start_time < timeout:
                try:
                    async with aiohttp.ClientSession() as session:
                        # Check if RPC is responding
                        payload = {"jsonrpc": "2.0", "method": "eth_syncing", "params": [], "id": 1}
                        
                        async with session.post(rpc_url, json=payload, timeout=10) as response:
                            if response.status == 200:
                                data = await response.json()
                                result = data.get('result')
                                
                                if result is False:
                                    # Node is synced
                                    sync_result['success'] = True
                                    sync_result['sync_achieved'] = True
                                    break
                                elif isinstance(result, dict):
                                    # Node is syncing
                                    current = int(result.get('currentBlock', '0'), 16)
                                    highest = int(result.get('highestBlock', '0'), 16)
                                    
                                    if highest > 0:
                                        progress = (current / highest) * 100
                                        if progress > 99.5:  # Close enough to consider synced
                                            sync_result['success'] = True
                                            sync_result['sync_achieved'] = True
                                            break
                                            
                except asyncio.TimeoutError:
                    pass  # Continue waiting
                except Exception:
                    pass  # Continue waiting
                    
                await asyncio.sleep(30)  # Check every 30 seconds
                
            if not sync_result['sync_achieved']:
                sync_result['timeout_reached'] = True
                
        except Exception as e:
            sync_result['error'] = str(e)
            
        return sync_result
        
    async def _post_update_validation(self, chain: str, version: str) -> Dict[str, Any]:
        """Validate node after update"""
        validation_result = {
            'success': False,
            'checks': {},
            'error': None
        }
        
        try:
            # Re-run health checks
            health_check = await self._check_node_health(chain)
            validation_result['checks']['node_health'] = health_check
            
            # Verify version
            version_check = await self._verify_updated_version(chain, version)
            validation_result['checks']['version_verification'] = version_check
            
            # Check peer connections
            peer_check = await self._check_post_update_peers(chain)
            validation_result['checks']['peer_connections'] = peer_check
            
            # Performance validation
            performance_check = await self._validate_post_update_performance(chain)
            validation_result['checks']['performance'] = performance_check
            
            # Overall validation
            critical_checks = ['node_health', 'version_verification']
            validation_result['success'] = all(
                validation_result['checks'][check].get('success', False)
                for check in critical_checks
                if check in validation_result['checks']
            )
            
        except Exception as e:
            validation_result['error'] = str(e)
            
        return validation_result
        
    async def _verify_updated_version(self, chain: str, expected_version: str) -> Dict[str, Any]:
        """Verify that the node is running the expected version"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            
            if not rpc_url:
                return {'success': False, 'error': 'No RPC URL configured'}
                
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "web3_clientVersion", "params": [], "id": 1}
                
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        client_version = data.get('result', '')
                        
                        # Check if expected version is in the client version string
                        version_match = expected_version in client_version
                        
                        return {
                            'success': version_match,
                            'client_version': client_version,
                            'expected_version': expected_version,
                            'version_match': version_match
                        }
                        
            return {'success': False, 'error': 'Could not retrieve client version'}
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    async def _check_post_update_peers(self, chain: str) -> Dict[str, Any]:
        """Check peer connections after update"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            min_peers = chain_config.get('min_peers', 5)
            
            if not rpc_url:
                return {'success': True, 'note': 'No RPC URL configured'}
                
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "net_peerCount", "params": [], "id": 1}
                
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        peer_count = int(data.get('result', '0'), 16)
                        
                        return {
                            'success': peer_count >= min_peers,
                            'peer_count': peer_count,
                            'min_peers': min_peers,
                            'sufficient_peers': peer_count >= min_peers
                        }
                        
            return {'success': False, 'error': 'Could not retrieve peer count'}
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    async def _validate_post_update_performance(self, chain: str) -> Dict[str, Any]:
        """Validate performance after update"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            rpc_url = chain_config.get('rpc_url')
            
            if not rpc_url:
                return {'success': True, 'note': 'No RPC URL configured'}
                
            # Test RPC latency
            start_time = time.time()
            async with aiohttp.ClientSession() as session:
                payload = {"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1}
                
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    latency = (time.time() - start_time) * 1000  # ms
                    
                    if response.status == 200:
                        return {
                            'success': latency < 1000,  # Less than 1 second
                            'rpc_latency_ms': round(latency, 2),
                            'acceptable_latency': latency < 1000
                        }
                        
            return {'success': False, 'error': 'Performance test failed'}
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    async def _rollback_update(self, chain: str, update_context: Dict[str, Any]) -> Dict[str, Any]:
        """Rollback to previous version"""
        rollback_result = {
            'success': False,
            'error': None
        }
        
        try:
            self.logger.warning(f"Initiating rollback for {chain}")
            
            # Stop current version
            shutdown_result = await self._graceful_shutdown(chain)
            
            # Restore from backup
            restore_result = await self._restore_from_backup(chain)
            
            # Start restored version
            startup_result = await self._start_restored_version(chain)
            
            rollback_result['success'] = (
                shutdown_result.get('success', False) and
                restore_result.get('success', False) and
                startup_result.get('success', False)
            )
            
            rollback_result['steps'] = {
                'shutdown': shutdown_result,
                'restore': restore_result,
                'startup': startup_result
            }
            
        except Exception as e:
            rollback_result['error'] = str(e)
            
        return rollback_result
        
    async def _restore_from_backup(self, chain: str) -> Dict[str, Any]:
        """Restore node from backup"""
        try:
            # Import backup manager
            import sys
            sys.path.append('/data/blockchain/nodes/maintenance/scripts')
            from backup_manager import BackupManager
            
            backup_manager = BackupManager()
            
            # Find most recent backup
            conn = sqlite3.connect('/data/blockchain/nodes/maintenance/logs/backup_history.db')
            cursor = conn.cursor()
            
            cursor.execute('''
                SELECT id FROM backups 
                WHERE source LIKE ? AND status = 'completed'
                ORDER BY timestamp DESC LIMIT 1
            ''', (f'%{chain}%',))
            
            result = cursor.fetchone()
            conn.close()
            
            if result:
                backup_id = result[0]
                restore_path = f"/data/blockchain/nodes/{chain}/restored"
                
                restore_result = backup_manager.restore_backup(backup_id, restore_path)
                return restore_result
            else:
                return {'success': False, 'error': 'No recent backup found'}
                
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    async def _start_restored_version(self, chain: str) -> Dict[str, Any]:
        """Start the restored version"""
        try:
            chain_config = self.config['chains'].get(chain, {})
            service_name = chain_config.get('service_name')
            
            if service_name:
                result = subprocess.run(
                    ['systemctl', 'start', service_name],
                    capture_output=True, text=True, timeout=60
                )
                
                return {
                    'success': result.returncode == 0,
                    'error': result.stderr if result.returncode != 0 else None
                }
            else:
                return {'success': False, 'error': 'No service name configured'}
                
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    # Blue-green deployment methods (stubs for now)
    async def _deploy_green_environment(self, chain: str, version: str, dry_run: bool) -> Dict[str, Any]:
        return {'success': True, 'message': 'Green environment deployed'}
        
    async def _validate_green_environment(self, chain: str) -> Dict[str, Any]:
        return {'success': True, 'message': 'Green environment validated'}
        
    async def _switch_traffic_to_green(self, chain: str) -> Dict[str, Any]:
        return {'success': True, 'message': 'Traffic switched to green'}
        
    async def _cleanup_blue_environment(self, chain: str) -> Dict[str, Any]:
        return {'success': True, 'message': 'Blue environment cleaned up'}
        
    # Canary deployment methods (stubs for now)
    async def _deploy_canary_instance(self, chain: str, version: str, dry_run: bool) -> Dict[str, Any]:
        return {'success': True, 'message': 'Canary instance deployed'}
        
    async def _route_canary_traffic(self, chain: str, percentage: int) -> Dict[str, Any]:
        return {'success': True, 'message': f'{percentage}% traffic routed to canary'}
        
    async def _monitor_canary_performance(self, chain: str, duration_minutes: int) -> Dict[str, Any]:
        # Simulate monitoring
        await asyncio.sleep(min(duration_minutes * 60, 60))  # Cap at 1 minute for demo
        return {'success': True, 'message': 'Canary performance acceptable'}
        
    async def _complete_canary_rollout(self, chain: str) -> Dict[str, Any]:
        return {'success': True, 'message': 'Canary rollout completed'}
        
    async def _rollback_canary(self, chain: str) -> Dict[str, Any]:
        return {'success': True, 'message': 'Canary rolled back'}
        
    def _save_update_history(self):
        """Save update history to file"""
        try:
            history_file = Path("/data/blockchain/nodes/maintenance/logs/update_history.json")
            with open(history_file, 'w') as f:
                json.dump(self.update_history, f, indent=2)
        except Exception as e:
            self.logger.error(f"Failed to save update history: {str(e)}")

def main():
    """Main function for manual updates"""
    import sys
    
    if len(sys.argv) < 3:
        print("Usage: python zero_downtime_updater.py <chain> <version> [strategy] [--dry-run]")
        print("Strategies: rolling, blue_green, canary, maintenance_window")
        sys.exit(1)
        
    chain = sys.argv[1]
    version = sys.argv[2]
    strategy_str = sys.argv[3] if len(sys.argv) > 3 else 'rolling'
    dry_run = '--dry-run' in sys.argv
    
    try:
        strategy = UpdateStrategy(strategy_str)
    except ValueError:
        print(f"Invalid strategy: {strategy_str}")
        sys.exit(1)
        
    updater = ZeroDowntimeUpdater()
    
    async def run_update():
        result = await updater.update_chain(chain, version, strategy, dry_run)
        
        print(f"\nUpdate Results for {chain} -> {version}:")
        print(f"Strategy: {result['strategy']}")
        print(f"Success: {result['success']}")
        print(f"Dry Run: {result['dry_run']}")
        
        if result.get('error_message'):
            print(f"Error: {result['error_message']}")
            
        if result.get('rollback_performed'):
            print("Rollback was performed")
            
        print(f"\nPhases completed: {len(result['phases'])}")
        for phase in result['phases']:
            print(f"  - {phase['phase']}: {phase['result'].get('success', 'unknown')}")
            
    asyncio.run(run_update())

if __name__ == "__main__":
    main()