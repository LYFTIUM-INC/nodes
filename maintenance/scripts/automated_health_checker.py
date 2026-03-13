#!/usr/bin/env python3
"""
Automated Health Check System for Blockchain Nodes
Performs comprehensive health checks across all blockchain nodes
"""

import json
import time
import asyncio
import aiohttp
import psutil
import logging
import sqlite3
import smtplib
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path
import yaml
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import subprocess
import os

class BlockchainHealthChecker:
    def __init__(self, config_path: str = "/data/blockchain/nodes/maintenance/configs/health_check_config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.db_path = Path("/data/blockchain/nodes/maintenance/logs/health_metrics.db")
        self._init_database()
        
    def _load_config(self, config_path: str) -> Dict:
        """Load configuration from YAML file"""
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
            
    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        logger = logging.getLogger('HealthChecker')
        logger.setLevel(logging.INFO)
        
        # File handler
        fh = logging.FileHandler('/data/blockchain/nodes/maintenance/logs/health_check.log')
        fh.setLevel(logging.INFO)
        
        # Console handler
        ch = logging.StreamHandler()
        ch.setLevel(logging.WARNING)
        
        # Formatter
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        fh.setFormatter(formatter)
        ch.setFormatter(formatter)
        
        logger.addHandler(fh)
        logger.addHandler(ch)
        
        return logger
        
    def _init_database(self):
        """Initialize SQLite database for metrics storage"""
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS health_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                chain TEXT NOT NULL,
                metric_type TEXT NOT NULL,
                metric_value REAL,
                status TEXT,
                details TEXT
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                chain TEXT NOT NULL,
                alert_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                message TEXT,
                resolved BOOLEAN DEFAULT FALSE
            )
        ''')
        
        conn.commit()
        conn.close()
        
    async def check_node_health(self, chain: str, config: Dict) -> Dict[str, Any]:
        """Perform health check for a specific node"""
        health_status = {
            'chain': chain,
            'timestamp': datetime.now().isoformat(),
            'checks': {},
            'overall_status': 'healthy'
        }
        
        # RPC connectivity check
        rpc_health = await self._check_rpc_connectivity(chain, config.get('rpc_url'))
        health_status['checks']['rpc_connectivity'] = rpc_health
        
        # Sync status check
        sync_status = await self._check_sync_status(chain, config.get('rpc_url'))
        health_status['checks']['sync_status'] = sync_status
        
        # Peer count check
        peer_count = await self._check_peer_count(chain, config.get('rpc_url'))
        health_status['checks']['peer_count'] = peer_count
        
        # System resource checks
        resource_status = self._check_system_resources(chain)
        health_status['checks']['system_resources'] = resource_status
        
        # Container/process status
        process_status = self._check_process_status(chain, config)
        health_status['checks']['process_status'] = process_status
        
        # Log analysis
        log_status = self._analyze_logs(chain, config)
        health_status['checks']['log_analysis'] = log_status
        
        # Determine overall status
        critical_checks = ['rpc_connectivity', 'process_status']
        warning_checks = ['sync_status', 'peer_count', 'system_resources']
        
        for check in critical_checks:
            if health_status['checks'][check]['status'] == 'critical':
                health_status['overall_status'] = 'critical'
                break
                
        if health_status['overall_status'] != 'critical':
            for check in warning_checks:
                if health_status['checks'][check]['status'] in ['warning', 'critical']:
                    health_status['overall_status'] = 'warning'
                    break
                    
        # Store metrics in database
        self._store_metrics(health_status)
        
        # Generate alerts if needed
        await self._generate_alerts(health_status)
        
        return health_status
        
    async def _check_rpc_connectivity(self, chain: str, rpc_url: str) -> Dict:
        """Check RPC endpoint connectivity"""
        try:
            async with aiohttp.ClientSession() as session:
                # Test basic RPC call
                payload = {
                    "jsonrpc": "2.0",
                    "method": "web3_clientVersion",
                    "params": [],
                    "id": 1
                }
                
                start_time = time.time()
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    latency = (time.time() - start_time) * 1000  # ms
                    
                    if response.status == 200:
                        data = await response.json()
                        if 'result' in data:
                            return {
                                'status': 'healthy',
                                'latency_ms': round(latency, 2),
                                'client_version': data['result'],
                                'message': 'RPC endpoint responsive'
                            }
                            
            return {
                'status': 'critical',
                'message': 'RPC endpoint not responding correctly'
            }
            
        except Exception as e:
            return {
                'status': 'critical',
                'message': f'RPC connection failed: {str(e)}'
            }
            
    async def _check_sync_status(self, chain: str, rpc_url: str) -> Dict:
        """Check node synchronization status"""
        try:
            async with aiohttp.ClientSession() as session:
                # Get sync status
                payload = {
                    "jsonrpc": "2.0",
                    "method": "eth_syncing",
                    "params": [],
                    "id": 1
                }
                
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        result = data.get('result')
                        
                        if result is False:
                            # Node is synced
                            block_number = await self._get_block_number(session, rpc_url)
                            return {
                                'status': 'healthy',
                                'synced': True,
                                'current_block': block_number,
                                'message': 'Node fully synchronized'
                            }
                        else:
                            # Node is syncing
                            current = int(result.get('currentBlock', '0'), 16)
                            highest = int(result.get('highestBlock', '0'), 16)
                            progress = (current / highest * 100) if highest > 0 else 0
                            
                            status = 'warning' if progress > 95 else 'critical'
                            
                            return {
                                'status': status,
                                'synced': False,
                                'current_block': current,
                                'highest_block': highest,
                                'sync_progress': round(progress, 2),
                                'message': f'Node syncing: {progress:.2f}% complete'
                            }
                            
        except Exception as e:
            return {
                'status': 'critical',
                'message': f'Failed to check sync status: {str(e)}'
            }
            
    async def _get_block_number(self, session: aiohttp.ClientSession, rpc_url: str) -> int:
        """Get current block number"""
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        }
        
        async with session.post(rpc_url, json=payload, timeout=10) as response:
            if response.status == 200:
                data = await response.json()
                return int(data.get('result', '0'), 16)
        return 0
        
    async def _check_peer_count(self, chain: str, rpc_url: str) -> Dict:
        """Check peer connectivity"""
        try:
            async with aiohttp.ClientSession() as session:
                payload = {
                    "jsonrpc": "2.0",
                    "method": "net_peerCount",
                    "params": [],
                    "id": 1
                }
                
                async with session.post(rpc_url, json=payload, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        peer_count = int(data.get('result', '0'), 16)
                        
                        min_peers = self.config['chains'][chain].get('min_peers', 5)
                        
                        if peer_count >= min_peers:
                            status = 'healthy'
                        elif peer_count > 0:
                            status = 'warning'
                        else:
                            status = 'critical'
                            
                        return {
                            'status': status,
                            'peer_count': peer_count,
                            'min_peers': min_peers,
                            'message': f'Connected to {peer_count} peers'
                        }
                        
        except Exception as e:
            return {
                'status': 'critical',
                'message': f'Failed to check peer count: {str(e)}'
            }
            
    def _check_system_resources(self, chain: str) -> Dict:
        """Check system resource usage"""
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            
            # Memory usage
            memory = psutil.virtual_memory()
            
            # Disk usage
            disk = psutil.disk_usage('/')
            
            # Determine status
            status = 'healthy'
            warnings = []
            
            if cpu_percent > 90:
                status = 'critical'
                warnings.append(f'CPU usage critical: {cpu_percent}%')
            elif cpu_percent > 80:
                status = 'warning'
                warnings.append(f'CPU usage high: {cpu_percent}%')
                
            if memory.percent > 90:
                status = 'critical'
                warnings.append(f'Memory usage critical: {memory.percent}%')
            elif memory.percent > 80:
                if status != 'critical':
                    status = 'warning'
                warnings.append(f'Memory usage high: {memory.percent}%')
                
            if disk.percent > 95:
                status = 'critical'
                warnings.append(f'Disk usage critical: {disk.percent}%')
            elif disk.percent > 90:
                if status != 'critical':
                    status = 'warning'
                warnings.append(f'Disk usage high: {disk.percent}%')
                
            return {
                'status': status,
                'cpu_percent': cpu_percent,
                'memory_percent': memory.percent,
                'memory_used_gb': round(memory.used / (1024**3), 2),
                'memory_total_gb': round(memory.total / (1024**3), 2),
                'disk_percent': disk.percent,
                'disk_used_gb': round(disk.used / (1024**3), 2),
                'disk_total_gb': round(disk.total / (1024**3), 2),
                'warnings': warnings,
                'message': 'System resources within limits' if not warnings else '; '.join(warnings)
            }
            
        except Exception as e:
            return {
                'status': 'critical',
                'message': f'Failed to check system resources: {str(e)}'
            }
            
    def _check_process_status(self, chain: str, config: Dict) -> Dict:
        """Check if node process is running"""
        try:
            process_name = config.get('process_name')
            container_name = config.get('container_name')
            
            if container_name:
                # Check Docker container
                result = subprocess.run(
                    ['docker', 'ps', '--filter', f'name={container_name}', '--format', '{{.Status}}'],
                    capture_output=True,
                    text=True
                )
                
                if result.returncode == 0 and result.stdout.strip():
                    return {
                        'status': 'healthy',
                        'container_status': result.stdout.strip(),
                        'message': f'Container {container_name} is running'
                    }
                else:
                    return {
                        'status': 'critical',
                        'message': f'Container {container_name} is not running'
                    }
                    
            elif process_name:
                # Check system process
                for proc in psutil.process_iter(['pid', 'name', 'status']):
                    if process_name in proc.info['name']:
                        return {
                            'status': 'healthy',
                            'pid': proc.info['pid'],
                            'process_status': proc.info['status'],
                            'message': f'Process {process_name} is running'
                        }
                        
                return {
                    'status': 'critical',
                    'message': f'Process {process_name} not found'
                }
                
        except Exception as e:
            return {
                'status': 'critical',
                'message': f'Failed to check process status: {str(e)}'
            }
            
    def _analyze_logs(self, chain: str, config: Dict) -> Dict:
        """Analyze node logs for errors"""
        try:
            log_path = config.get('log_path')
            if not log_path or not Path(log_path).exists():
                return {
                    'status': 'warning',
                    'message': 'Log file not found or not configured'
                }
                
            # Read last 1000 lines of log
            with open(log_path, 'r') as f:
                lines = f.readlines()[-1000:]
                
            error_count = 0
            warning_count = 0
            recent_errors = []
            
            for line in lines:
                line_lower = line.lower()
                if 'error' in line_lower or 'fatal' in line_lower:
                    error_count += 1
                    if len(recent_errors) < 5:
                        recent_errors.append(line.strip())
                elif 'warning' in line_lower or 'warn' in line_lower:
                    warning_count += 1
                    
            if error_count > 10:
                status = 'critical'
                message = f'High error rate: {error_count} errors in recent logs'
            elif error_count > 5:
                status = 'warning'
                message = f'Moderate error rate: {error_count} errors in recent logs'
            else:
                status = 'healthy'
                message = 'Log analysis normal'
                
            return {
                'status': status,
                'error_count': error_count,
                'warning_count': warning_count,
                'recent_errors': recent_errors[:3],  # Limit to 3 most recent
                'message': message
            }
            
        except Exception as e:
            return {
                'status': 'warning',
                'message': f'Failed to analyze logs: {str(e)}'
            }
            
    def _store_metrics(self, health_status: Dict):
        """Store health metrics in database"""
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        chain = health_status['chain']
        timestamp = health_status['timestamp']
        
        # Store overall status
        cursor.execute('''
            INSERT INTO health_metrics (timestamp, chain, metric_type, metric_value, status, details)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (timestamp, chain, 'overall_health', None, health_status['overall_status'], 
              json.dumps(health_status)))
        
        # Store individual metrics
        for check_name, check_data in health_status['checks'].items():
            if isinstance(check_data, dict):
                # Extract numeric values for graphing
                numeric_value = None
                if check_name == 'rpc_connectivity' and 'latency_ms' in check_data:
                    numeric_value = check_data['latency_ms']
                elif check_name == 'sync_status' and 'sync_progress' in check_data:
                    numeric_value = check_data['sync_progress']
                elif check_name == 'peer_count' and 'peer_count' in check_data:
                    numeric_value = check_data['peer_count']
                elif check_name == 'system_resources':
                    # Store CPU usage as primary metric
                    numeric_value = check_data.get('cpu_percent')
                    
                cursor.execute('''
                    INSERT INTO health_metrics (timestamp, chain, metric_type, metric_value, status, details)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (timestamp, chain, check_name, numeric_value, check_data.get('status', 'unknown'),
                      json.dumps(check_data)))
                      
        conn.commit()
        conn.close()
        
    async def _generate_alerts(self, health_status: Dict):
        """Generate alerts for critical issues"""
        if health_status['overall_status'] in ['warning', 'critical']:
            conn = sqlite3.connect(str(self.db_path))
            cursor = conn.cursor()
            
            chain = health_status['chain']
            
            # Check if similar alert was already sent recently (within 1 hour)
            one_hour_ago = (datetime.now() - timedelta(hours=1)).isoformat()
            cursor.execute('''
                SELECT COUNT(*) FROM alerts 
                WHERE chain = ? AND timestamp > ? AND resolved = FALSE
            ''', (chain, one_hour_ago))
            
            recent_alert_count = cursor.fetchone()[0]
            
            if recent_alert_count == 0:
                # Create new alert
                alert_message = self._format_alert_message(health_status)
                
                cursor.execute('''
                    INSERT INTO alerts (chain, alert_type, severity, message)
                    VALUES (?, ?, ?, ?)
                ''', (chain, 'health_check', health_status['overall_status'], alert_message))
                
                conn.commit()
                
                # Send notifications
                await self._send_notifications(chain, health_status['overall_status'], alert_message)
                
            conn.close()
            
    def _format_alert_message(self, health_status: Dict) -> str:
        """Format alert message"""
        chain = health_status['chain']
        status = health_status['overall_status']
        
        issues = []
        for check_name, check_data in health_status['checks'].items():
            if isinstance(check_data, dict) and check_data.get('status') in ['warning', 'critical']:
                issues.append(f"- {check_name}: {check_data.get('message', 'Issue detected')}")
                
        message = f"Health check alert for {chain} node:\n"
        message += f"Status: {status.upper()}\n"
        message += f"Issues:\n" + '\n'.join(issues)
        
        return message
        
    async def _send_notifications(self, chain: str, severity: str, message: str):
        """Send alert notifications"""
        # Email notification
        if self.config.get('notifications', {}).get('email', {}).get('enabled'):
            await self._send_email_alert(chain, severity, message)
            
        # Webhook notification
        if self.config.get('notifications', {}).get('webhook', {}).get('enabled'):
            await self._send_webhook_alert(chain, severity, message)
            
        # Log alert
        self.logger.warning(f"Alert for {chain}: {message}")
        
    async def _send_email_alert(self, chain: str, severity: str, message: str):
        """Send email alert"""
        try:
            email_config = self.config['notifications']['email']
            
            msg = MIMEMultipart()
            msg['From'] = email_config['from']
            msg['To'] = ', '.join(email_config['to'])
            msg['Subject'] = f"[{severity.upper()}] Blockchain Node Alert: {chain}"
            
            msg.attach(MIMEText(message, 'plain'))
            
            with smtplib.SMTP(email_config['smtp_host'], email_config['smtp_port']) as server:
                if email_config.get('use_tls'):
                    server.starttls()
                if email_config.get('username') and email_config.get('password'):
                    server.login(email_config['username'], email_config['password'])
                server.send_message(msg)
                
        except Exception as e:
            self.logger.error(f"Failed to send email alert: {str(e)}")
            
    async def _send_webhook_alert(self, chain: str, severity: str, message: str):
        """Send webhook alert"""
        try:
            webhook_config = self.config['notifications']['webhook']
            
            payload = {
                'chain': chain,
                'severity': severity,
                'message': message,
                'timestamp': datetime.now().isoformat()
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(webhook_config['url'], json=payload, timeout=10) as response:
                    if response.status != 200:
                        self.logger.error(f"Webhook returned status {response.status}")
                        
        except Exception as e:
            self.logger.error(f"Failed to send webhook alert: {str(e)}")
            
    async def run_health_checks(self):
        """Run health checks for all configured nodes"""
        self.logger.info("Starting health check cycle")
        
        tasks = []
        for chain, config in self.config['chains'].items():
            if config.get('enabled', True):
                tasks.append(self.check_node_health(chain, config))
                
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        summary = {
            'timestamp': datetime.now().isoformat(),
            'total_nodes': len(tasks),
            'healthy': 0,
            'warning': 0,
            'critical': 0,
            'results': {}
        }
        
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                self.logger.error(f"Health check failed: {str(result)}")
            else:
                chain = list(self.config['chains'].keys())[i]
                summary['results'][chain] = result
                summary[result['overall_status']] += 1
                
        # Save summary
        summary_path = Path("/data/blockchain/nodes/maintenance/logs/health_summary.json")
        with open(summary_path, 'w') as f:
            json.dump(summary, f, indent=2)
            
        self.logger.info(f"Health check complete: {summary['healthy']} healthy, "
                        f"{summary['warning']} warning, {summary['critical']} critical")
                        
        return summary
        
    def generate_report(self, hours: int = 24) -> Dict:
        """Generate health report for specified time period"""
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        start_time = (datetime.now() - timedelta(hours=hours)).isoformat()
        
        report = {
            'period_hours': hours,
            'generated_at': datetime.now().isoformat(),
            'chains': {}
        }
        
        # Get list of chains
        cursor.execute('SELECT DISTINCT chain FROM health_metrics')
        chains = [row[0] for row in cursor.fetchall()]
        
        for chain in chains:
            # Get overall statistics
            cursor.execute('''
                SELECT status, COUNT(*) as count
                FROM health_metrics
                WHERE chain = ? AND timestamp > ? AND metric_type = 'overall_health'
                GROUP BY status
            ''', (chain, start_time))
            
            status_counts = dict(cursor.fetchall())
            
            # Get average metrics
            cursor.execute('''
                SELECT metric_type, AVG(metric_value) as avg_value
                FROM health_metrics
                WHERE chain = ? AND timestamp > ? AND metric_value IS NOT NULL
                GROUP BY metric_type
            ''', (chain, start_time))
            
            avg_metrics = dict(cursor.fetchall())
            
            # Get recent alerts
            cursor.execute('''
                SELECT timestamp, severity, message
                FROM alerts
                WHERE chain = ? AND timestamp > ?
                ORDER BY timestamp DESC
                LIMIT 10
            ''', (chain, start_time))
            
            recent_alerts = [
                {
                    'timestamp': row[0],
                    'severity': row[1],
                    'message': row[2]
                }
                for row in cursor.fetchall()
            ]
            
            report['chains'][chain] = {
                'status_distribution': status_counts,
                'average_metrics': avg_metrics,
                'recent_alerts': recent_alerts,
                'uptime_percentage': self._calculate_uptime(chain, hours)
            }
            
        conn.close()
        
        return report
        
    def _calculate_uptime(self, chain: str, hours: int) -> float:
        """Calculate uptime percentage"""
        conn = sqlite3.connect(str(self.db_path))
        cursor = conn.cursor()
        
        start_time = (datetime.now() - timedelta(hours=hours)).isoformat()
        
        cursor.execute('''
            SELECT COUNT(*) as total,
                   SUM(CASE WHEN status = 'healthy' THEN 1 ELSE 0 END) as healthy
            FROM health_metrics
            WHERE chain = ? AND timestamp > ? AND metric_type = 'overall_health'
        ''', (chain, start_time))
        
        result = cursor.fetchone()
        total, healthy = result[0], result[1]
        
        conn.close()
        
        if total > 0:
            return round((healthy / total) * 100, 2)
        return 0.0

async def main():
    """Main function"""
    checker = BlockchainHealthChecker()
    
    # Run health checks
    await checker.run_health_checks()
    
    # Generate 24-hour report
    report = checker.generate_report(24)
    
    # Save report
    report_path = Path("/data/blockchain/nodes/maintenance/logs/daily_health_report.json")
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)

if __name__ == "__main__":
    asyncio.run(main())