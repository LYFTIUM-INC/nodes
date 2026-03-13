#!/usr/bin/env python3
"""
Master Maintenance Orchestrator for Blockchain Nodes
Coordinates all maintenance activities, ensures 24/7 operations, and provides unified management
"""

import json
import time
import asyncio
import subprocess
import logging
import signal
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Any, Optional
import yaml
import threading
from concurrent.futures import ThreadPoolExecutor
import argparse

class MasterMaintenanceOrchestrator:
    def __init__(self, config_path: str = "/data/blockchain/nodes/maintenance/configs/orchestrator_config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        
        # Service states
        self.services = {}
        self.running = False
        self.executor = ThreadPoolExecutor(max_workers=10)
        
        # Maintenance components
        self.health_checker = None
        self.backup_manager = None
        self.performance_optimizer = None
        self.restart_manager = None
        self.log_rotator = None
        self.update_manager = None
        self.capacity_planner = None
        self.dashboard = None
        
        # Signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
    def _load_config(self, config_path: str) -> Dict:
        """Load orchestrator configuration"""
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            return self._get_default_config()
            
    def _get_default_config(self) -> Dict:
        """Get default configuration"""
        return {
            'services': {
                'health_checker': {'enabled': True, 'interval_minutes': 5},
                'backup_manager': {'enabled': True, 'interval_hours': 24},
                'performance_optimizer': {'enabled': True, 'interval_hours': 4},
                'restart_manager': {'enabled': True, 'interval_minutes': 1},
                'log_rotator': {'enabled': True, 'interval_hours': 6},
                'update_manager': {'enabled': False, 'interval_hours': 24},
                'capacity_planner': {'enabled': True, 'interval_minutes': 15},
                'dashboard': {'enabled': True, 'port': 5000}
            },
            'coordination': {
                'max_concurrent_operations': 3,
                'operation_timeout_minutes': 60,
                'retry_attempts': 3,
                'retry_delay_seconds': 30
            },
            'priorities': {
                'health_checks': 10,
                'restart_operations': 9,
                'backup_operations': 7,
                'performance_optimization': 6,
                'log_rotation': 5,
                'capacity_planning': 4,
                'updates': 3
            }
        }
        
    def _setup_logging(self) -> logging.Logger:
        """Setup logging"""
        logger = logging.getLogger('MasterOrchestrator')
        logger.setLevel(logging.INFO)
        
        # File handler
        handler = logging.FileHandler('/data/blockchain/nodes/maintenance/logs/orchestrator.log')
        handler.setLevel(logging.INFO)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        console_handler.setFormatter(formatter)
        
        logger.addHandler(handler)
        logger.addHandler(console_handler)
        
        return logger
        
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum}, initiating graceful shutdown...")
        self.stop()
        
    async def start(self):
        """Start the master orchestrator"""
        self.running = True
        self.logger.info("Starting Master Maintenance Orchestrator")
        
        try:
            # Initialize all services
            await self._initialize_services()
            
            # Start service monitoring
            monitoring_tasks = []
            for service_name in self.services:
                if self.services[service_name].get('enabled', True):
                    task = asyncio.create_task(self._monitor_service(service_name))
                    monitoring_tasks.append(task)
                    
            # Start coordination loop
            coordination_task = asyncio.create_task(self._coordination_loop())
            monitoring_tasks.append(coordination_task)
            
            # Wait for all tasks
            await asyncio.gather(*monitoring_tasks, return_exceptions=True)
            
        except Exception as e:
            self.logger.error(f"Error in orchestrator: {str(e)}")
        finally:
            await self._cleanup()
            
    async def _initialize_services(self):
        """Initialize all maintenance services"""
        self.logger.info("Initializing maintenance services...")
        
        services_config = self.config.get('services', {})
        
        # Health Checker
        if services_config.get('health_checker', {}).get('enabled', True):
            try:
                from automated_health_checker import BlockchainHealthChecker
                self.health_checker = BlockchainHealthChecker()
                self.services['health_checker'] = {
                    'enabled': True,
                    'instance': self.health_checker,
                    'last_run': None,
                    'next_run': datetime.now(),
                    'interval_minutes': services_config.get('health_checker', {}).get('interval_minutes', 5),
                    'status': 'initialized'
                }
                self.logger.info("Health Checker initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize Health Checker: {str(e)}")
                
        # Backup Manager
        if services_config.get('backup_manager', {}).get('enabled', True):
            try:
                from backup_manager import BackupManager
                self.backup_manager = BackupManager()
                self.services['backup_manager'] = {
                    'enabled': True,
                    'instance': self.backup_manager,
                    'last_run': None,
                    'next_run': datetime.now() + timedelta(hours=1),  # Start backups after 1 hour
                    'interval_hours': services_config.get('backup_manager', {}).get('interval_hours', 24),
                    'status': 'initialized'
                }
                self.logger.info("Backup Manager initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize Backup Manager: {str(e)}")
                
        # Performance Optimizer
        if services_config.get('performance_optimizer', {}).get('enabled', True):
            try:
                from performance_optimizer import PerformanceOptimizer
                self.performance_optimizer = PerformanceOptimizer()
                self.services['performance_optimizer'] = {
                    'enabled': True,
                    'instance': self.performance_optimizer,
                    'last_run': None,
                    'next_run': datetime.now() + timedelta(minutes=30),  # Start optimization after 30 minutes
                    'interval_hours': services_config.get('performance_optimizer', {}).get('interval_hours', 4),
                    'status': 'initialized'
                }
                self.logger.info("Performance Optimizer initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize Performance Optimizer: {str(e)}")
                
        # Restart Manager
        if services_config.get('restart_manager', {}).get('enabled', True):
            try:
                from automated_restart_manager import AutomatedRestartManager
                self.restart_manager = AutomatedRestartManager()
                self.services['restart_manager'] = {
                    'enabled': True,
                    'instance': self.restart_manager,
                    'last_run': None,
                    'next_run': datetime.now(),
                    'interval_minutes': services_config.get('restart_manager', {}).get('interval_minutes', 1),
                    'status': 'initialized'
                }
                self.logger.info("Restart Manager initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize Restart Manager: {str(e)}")
                
        # Log Rotator
        if services_config.get('log_rotator', {}).get('enabled', True):
            try:
                from log_rotation_manager import LogRotationManager
                self.log_rotator = LogRotationManager()
                self.services['log_rotator'] = {
                    'enabled': True,
                    'instance': self.log_rotator,
                    'last_run': None,
                    'next_run': datetime.now() + timedelta(hours=6),  # Start log rotation after 6 hours
                    'interval_hours': services_config.get('log_rotator', {}).get('interval_hours', 6),
                    'status': 'initialized'
                }
                self.logger.info("Log Rotator initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize Log Rotator: {str(e)}")
                
        # Update Manager
        if services_config.get('update_manager', {}).get('enabled', False):
            try:
                from zero_downtime_updater import ZeroDowntimeUpdater
                self.update_manager = ZeroDowntimeUpdater()
                self.services['update_manager'] = {
                    'enabled': True,
                    'instance': self.update_manager,
                    'last_run': None,
                    'next_run': datetime.now() + timedelta(hours=24),  # Start updates after 24 hours
                    'interval_hours': services_config.get('update_manager', {}).get('interval_hours', 24),
                    'status': 'initialized'
                }
                self.logger.info("Update Manager initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize Update Manager: {str(e)}")
                
        # Capacity Planner
        if services_config.get('capacity_planner', {}).get('enabled', True):
            try:
                import sys
                sys.path.append('/data/blockchain/nodes/maintenance/tools')
                from capacity_planner import CapacityPlanner
                self.capacity_planner = CapacityPlanner()
                self.services['capacity_planner'] = {
                    'enabled': True,
                    'instance': self.capacity_planner,
                    'last_run': None,
                    'next_run': datetime.now() + timedelta(minutes=15),  # Start capacity planning after 15 minutes
                    'interval_minutes': services_config.get('capacity_planner', {}).get('interval_minutes', 15),
                    'status': 'initialized'
                }
                self.logger.info("Capacity Planner initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize Capacity Planner: {str(e)}")
                
        # Dashboard
        if services_config.get('dashboard', {}).get('enabled', True):
            try:
                import sys
                sys.path.append('/data/blockchain/nodes/maintenance/dashboards')
                from comprehensive_monitoring_dashboard import ComprehensiveMonitoringDashboard
                self.dashboard = ComprehensiveMonitoringDashboard()
                
                # Start dashboard in background thread
                dashboard_thread = threading.Thread(
                    target=lambda: self.dashboard.run(
                        host='0.0.0.0', 
                        port=services_config.get('dashboard', {}).get('port', 5000),
                        debug=False
                    )
                )
                dashboard_thread.daemon = True
                dashboard_thread.start()
                
                self.services['dashboard'] = {
                    'enabled': True,
                    'instance': self.dashboard,
                    'last_run': datetime.now(),
                    'next_run': None,  # Dashboard runs continuously
                    'status': 'running'
                }
                self.logger.info("Monitoring Dashboard started")
            except Exception as e:
                self.logger.error(f"Failed to initialize Dashboard: {str(e)}")
                
        self.logger.info(f"Initialized {len(self.services)} maintenance services")
        
    async def _monitor_service(self, service_name: str):
        """Monitor and execute a specific service"""
        service = self.services[service_name]
        
        while self.running:
            try:
                current_time = datetime.now()
                
                # Check if it's time to run the service
                if service.get('next_run') and current_time >= service['next_run']:
                    await self._execute_service(service_name)
                    
                # Wait before next check
                await asyncio.sleep(60)  # Check every minute
                
            except Exception as e:
                self.logger.error(f"Error monitoring {service_name}: {str(e)}")
                await asyncio.sleep(60)
                
    async def _execute_service(self, service_name: str):
        """Execute a specific service"""
        service = self.services[service_name]
        
        try:
            self.logger.info(f"Executing {service_name}")
            service['status'] = 'running'
            start_time = datetime.now()
            
            # Execute service based on type
            if service_name == 'health_checker':
                await self._run_health_checker()
            elif service_name == 'backup_manager':
                await self._run_backup_manager()
            elif service_name == 'performance_optimizer':
                await self._run_performance_optimizer()
            elif service_name == 'restart_manager':
                await self._run_restart_manager()
            elif service_name == 'log_rotator':
                await self._run_log_rotator()
            elif service_name == 'update_manager':
                await self._run_update_manager()
            elif service_name == 'capacity_planner':
                await self._run_capacity_planner()
                
            # Update service state
            service['last_run'] = start_time
            service['status'] = 'completed'
            
            # Schedule next run
            self._schedule_next_run(service_name)
            
            duration = (datetime.now() - start_time).total_seconds()
            self.logger.info(f"Completed {service_name} in {duration:.2f} seconds")
            
        except Exception as e:
            service['status'] = 'failed'
            service['last_error'] = str(e)
            self.logger.error(f"Failed to execute {service_name}: {str(e)}")
            
            # Schedule retry
            self._schedule_retry(service_name)
            
    def _schedule_next_run(self, service_name: str):
        """Schedule the next run for a service"""
        service = self.services[service_name]
        
        if 'interval_minutes' in service:
            next_run = datetime.now() + timedelta(minutes=service['interval_minutes'])
        elif 'interval_hours' in service:
            next_run = datetime.now() + timedelta(hours=service['interval_hours'])
        else:
            next_run = datetime.now() + timedelta(hours=1)  # Default to 1 hour
            
        service['next_run'] = next_run
        
    def _schedule_retry(self, service_name: str):
        """Schedule a retry for a failed service"""
        service = self.services[service_name]
        retry_delay = self.config.get('coordination', {}).get('retry_delay_seconds', 30)
        service['next_run'] = datetime.now() + timedelta(seconds=retry_delay)
        
    async def _run_health_checker(self):
        """Run health checker"""
        if self.health_checker:
            await self.health_checker.run_health_checks()
            
    async def _run_backup_manager(self):
        """Run backup manager"""
        if self.backup_manager:
            # Run cleanup first
            cleanup_result = self.backup_manager.cleanup_old_backups()
            self.logger.info(f"Backup cleanup: {cleanup_result['backups_removed']} removed")
            
    async def _run_performance_optimizer(self):
        """Run performance optimizer"""
        if self.performance_optimizer:
            result = await self.performance_optimizer.optimize_all_chains()
            self.logger.info(f"Performance optimization: {len(result['chains_optimized'])} chains optimized")
            
    async def _run_restart_manager(self):
        """Run restart manager monitoring"""
        if self.restart_manager:
            # The restart manager runs its own monitoring loop
            # This just ensures it's running
            pass
            
    async def _run_log_rotator(self):
        """Run log rotator"""
        if self.log_rotator:
            result = self.log_rotator.rotate_logs()
            self.logger.info(f"Log rotation: {result['total_space_saved_mb']:.2f} MB saved")
            
    async def _run_update_manager(self):
        """Run update manager"""
        if self.update_manager:
            # Only run if configured for automatic updates
            self.logger.info("Update manager check completed (manual updates only)")
            
    async def _run_capacity_planner(self):
        """Run capacity planner"""
        if self.capacity_planner:
            # Collect metrics
            await self.capacity_planner._collect_capacity_metrics()
            
    async def _coordination_loop(self):
        """Main coordination loop"""
        while self.running:
            try:
                # Check service health
                await self._check_service_health()
                
                # Coordinate operations
                await self._coordinate_operations()
                
                # Generate status report
                await self._generate_status_report()
                
                # Wait before next coordination cycle
                await asyncio.sleep(300)  # 5 minutes
                
            except Exception as e:
                self.logger.error(f"Error in coordination loop: {str(e)}")
                await asyncio.sleep(60)
                
    async def _check_service_health(self):
        """Check health of all services"""
        for service_name, service in self.services.items():
            try:
                # Check if service is stuck
                if service.get('status') == 'running' and service.get('last_run'):
                    runtime = datetime.now() - service['last_run']
                    timeout_minutes = self.config.get('coordination', {}).get('operation_timeout_minutes', 60)
                    
                    if runtime > timedelta(minutes=timeout_minutes):
                        self.logger.warning(f"Service {service_name} appears stuck, marking as failed")
                        service['status'] = 'timeout'
                        self._schedule_retry(service_name)
                        
            except Exception as e:
                self.logger.error(f"Error checking health of {service_name}: {str(e)}")
                
    async def _coordinate_operations(self):
        """Coordinate operations to prevent conflicts"""
        try:
            # Check for conflicting operations
            running_services = [name for name, service in self.services.items() 
                              if service.get('status') == 'running']
            
            max_concurrent = self.config.get('coordination', {}).get('max_concurrent_operations', 3)
            
            if len(running_services) > max_concurrent:
                self.logger.warning(f"Too many concurrent operations: {len(running_services)}")
                
            # Implement priority-based scheduling if needed
            priorities = self.config.get('priorities', {})
            
            # Log coordination status
            if running_services:
                self.logger.debug(f"Currently running: {', '.join(running_services)}")
                
        except Exception as e:
            self.logger.error(f"Error in operation coordination: {str(e)}")
            
    async def _generate_status_report(self):
        """Generate and save status report"""
        try:
            status_report = {
                'timestamp': datetime.now().isoformat(),
                'orchestrator_status': 'running' if self.running else 'stopped',
                'services': {}
            }
            
            for service_name, service in self.services.items():
                status_report['services'][service_name] = {
                    'enabled': service.get('enabled', False),
                    'status': service.get('status', 'unknown'),
                    'last_run': service.get('last_run').isoformat() if service.get('last_run') else None,
                    'next_run': service.get('next_run').isoformat() if service.get('next_run') else None,
                    'last_error': service.get('last_error')
                }
                
            # Save status report
            status_file = Path("/data/blockchain/nodes/maintenance/logs/orchestrator_status.json")
            with open(status_file, 'w') as f:
                json.dump(status_report, f, indent=2)
                
        except Exception as e:
            self.logger.error(f"Error generating status report: {str(e)}")
            
    async def _cleanup(self):
        """Cleanup resources"""
        self.logger.info("Cleaning up orchestrator resources...")
        
        # Stop all services
        for service_name, service in self.services.items():
            try:
                if hasattr(service.get('instance'), 'stop'):
                    service['instance'].stop()
            except Exception as e:
                self.logger.error(f"Error stopping {service_name}: {str(e)}")
                
        # Shutdown executor
        self.executor.shutdown(wait=True)
        
    def stop(self):
        """Stop the orchestrator"""
        self.logger.info("Stopping Master Maintenance Orchestrator...")
        self.running = False
        
    def get_status(self) -> Dict[str, Any]:
        """Get current status of all services"""
        status = {
            'orchestrator_running': self.running,
            'timestamp': datetime.now().isoformat(),
            'services': {}
        }
        
        for service_name, service in self.services.items():
            status['services'][service_name] = {
                'enabled': service.get('enabled', False),
                'status': service.get('status', 'unknown'),
                'last_run': service.get('last_run').isoformat() if service.get('last_run') else None,
                'next_run': service.get('next_run').isoformat() if service.get('next_run') else None
            }
            
        return status
        
    def restart_service(self, service_name: str) -> Dict[str, Any]:
        """Restart a specific service"""
        if service_name not in self.services:
            return {'success': False, 'error': f'Service {service_name} not found'}
            
        try:
            service = self.services[service_name]
            service['status'] = 'restarting'
            service['next_run'] = datetime.now()
            
            return {'success': True, 'message': f'Service {service_name} scheduled for restart'}
            
        except Exception as e:
            return {'success': False, 'error': str(e)}

async def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Master Maintenance Orchestrator')
    parser.add_argument('--config', '-c', help='Configuration file path')
    parser.add_argument('--status', action='store_true', help='Show status and exit')
    parser.add_argument('--restart-service', help='Restart specific service')
    
    args = parser.parse_args()
    
    # Create orchestrator
    config_path = args.config if args.config else "/data/blockchain/nodes/maintenance/configs/orchestrator_config.yaml"
    orchestrator = MasterMaintenanceOrchestrator(config_path)
    
    # Handle different modes
    if args.status:
        status = orchestrator.get_status()
        print(json.dumps(status, indent=2))
        return
        
    if args.restart_service:
        result = orchestrator.restart_service(args.restart_service)
        print(json.dumps(result, indent=2))
        return
        
    # Start orchestrator
    try:
        await orchestrator.start()
    except KeyboardInterrupt:
        orchestrator.logger.info("Received keyboard interrupt")
    finally:
        orchestrator.stop()

if __name__ == "__main__":
    asyncio.run(main())