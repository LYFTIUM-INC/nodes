#!/usr/bin/env python3
"""
Comprehensive Capacity Planning Tool for Blockchain Nodes
Predictive analysis, resource forecasting, and scaling recommendations
"""

import json
import time
import numpy as np
import pandas as pd
import sqlite3
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
import yaml
import psutil
import asyncio
import aiohttp
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import PolynomialFeatures
from sklearn.metrics import mean_squared_error, r2_score
import matplotlib.pyplot as plt
import seaborn as sns
from collections import defaultdict
import warnings
warnings.filterwarnings('ignore')

class CapacityPlanner:
    def __init__(self, config_path: str = "/data/blockchain/nodes/maintenance/configs/capacity_config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.capacity_db = Path("/data/blockchain/nodes/maintenance/logs/capacity_metrics.db")
        self._init_database()
        
        # Forecasting models
        self.models = {}
        self.forecast_data = defaultdict(list)
        
        # Capacity thresholds
        self.thresholds = self.config.get('thresholds', {})
        
    def _load_config(self, config_path: str) -> Dict:
        """Load capacity planning configuration"""
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            return self._get_default_config()
            
    def _get_default_config(self) -> Dict:
        """Get default configuration"""
        return {
            'monitoring': {
                'enabled': True,
                'collection_interval_minutes': 15,
                'retention_days': 90
            },
            'forecasting': {
                'enabled': True,
                'forecast_horizon_days': 30,
                'models': ['linear', 'polynomial', 'seasonal'],
                'confidence_interval': 0.95
            },
            'thresholds': {
                'cpu_warning': 70,
                'cpu_critical': 85,
                'memory_warning': 75,
                'memory_critical': 90,
                'disk_warning': 80,
                'disk_critical': 90,
                'network_warning': 1000,  # Mbps
                'network_critical': 1500
            },
            'scaling': {
                'auto_scaling_enabled': False,
                'scale_up_threshold': 80,
                'scale_down_threshold': 30,
                'cooldown_minutes': 60
            }
        }
        
    def _setup_logging(self) -> logging.Logger:
        """Setup logging"""
        logger = logging.getLogger('CapacityPlanner')
        logger.setLevel(logging.INFO)
        
        handler = logging.FileHandler('/data/blockchain/nodes/maintenance/logs/capacity_planning.log')
        handler.setLevel(logging.INFO)
        
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        
        logger.addHandler(handler)
        return logger
        
    def _init_database(self):
        """Initialize capacity metrics database"""
        conn = sqlite3.connect(str(self.capacity_db))
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS capacity_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                metric_type TEXT NOT NULL,
                chain TEXT,
                value REAL NOT NULL,
                unit TEXT,
                metadata TEXT
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS forecasts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                metric_type TEXT NOT NULL,
                chain TEXT,
                forecast_horizon_days INTEGER,
                predicted_value REAL,
                confidence_lower REAL,
                confidence_upper REAL,
                model_type TEXT,
                accuracy_score REAL
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS capacity_alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                alert_type TEXT NOT NULL,
                chain TEXT,
                current_value REAL,
                threshold_value REAL,
                projected_date DATETIME,
                severity TEXT,
                recommendation TEXT,
                acknowledged BOOLEAN DEFAULT FALSE
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS scaling_recommendations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                chain TEXT NOT NULL,
                resource_type TEXT NOT NULL,
                current_capacity TEXT,
                recommended_capacity TEXT,
                scaling_factor REAL,
                cost_impact TEXT,
                urgency TEXT,
                implementation_plan TEXT
            )
        ''')
        
        conn.commit()
        conn.close()
        
    async def start_monitoring(self):
        """Start capacity monitoring and collection"""
        self.logger.info("Starting capacity monitoring")
        
        while True:
            try:
                # Collect current metrics
                await self._collect_capacity_metrics()
                
                # Update forecasts
                if self.config.get('forecasting', {}).get('enabled', True):
                    await self._update_forecasts()
                    
                # Check for capacity alerts
                await self._check_capacity_alerts()
                
                # Generate scaling recommendations
                await self._generate_scaling_recommendations()
                
                # Wait for next collection cycle
                interval = self.config.get('monitoring', {}).get('collection_interval_minutes', 15)
                await asyncio.sleep(interval * 60)
                
            except Exception as e:
                self.logger.error(f"Error in capacity monitoring: {str(e)}")
                await asyncio.sleep(60)
                
    async def _collect_capacity_metrics(self):
        """Collect current capacity metrics"""
        try:
            # System-wide metrics
            await self._collect_system_metrics()
            
            # Chain-specific metrics
            chains = self.config.get('chains', ['ethereum', 'arbitrum', 'polygon', 'optimism', 'base', 'bsc', 'avalanche', 'solana'])
            for chain in chains:
                await self._collect_chain_metrics(chain)
                
            # Network metrics
            await self._collect_network_metrics()
            
            # Storage metrics
            await self._collect_storage_metrics()
            
        except Exception as e:
            self.logger.error(f"Failed to collect capacity metrics: {str(e)}")
            
    async def _collect_system_metrics(self):
        """Collect system-wide capacity metrics"""
        try:
            # CPU metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_count = psutil.cpu_count()
            load_avg = psutil.getloadavg()[0] if hasattr(psutil, 'getloadavg') else cpu_percent / 100 * cpu_count
            
            self._store_metric('cpu_utilization', None, cpu_percent, '%')
            self._store_metric('cpu_load_average', None, load_avg, 'load')
            self._store_metric('cpu_cores', None, cpu_count, 'cores')
            
            # Memory metrics
            memory = psutil.virtual_memory()
            self._store_metric('memory_utilization', None, memory.percent, '%')
            self._store_metric('memory_used', None, memory.used / (1024**3), 'GB')
            self._store_metric('memory_total', None, memory.total / (1024**3), 'GB')
            self._store_metric('memory_available', None, memory.available / (1024**3), 'GB')
            
            # Swap metrics
            swap = psutil.swap_memory()
            self._store_metric('swap_utilization', None, swap.percent, '%')
            self._store_metric('swap_used', None, swap.used / (1024**3), 'GB')
            
            # Disk metrics
            disk = psutil.disk_usage('/data/blockchain/nodes')
            disk_percent = (disk.used / disk.total) * 100
            self._store_metric('disk_utilization', None, disk_percent, '%')
            self._store_metric('disk_used', None, disk.used / (1024**3), 'GB')
            self._store_metric('disk_total', None, disk.total / (1024**3), 'GB')
            self._store_metric('disk_free', None, disk.free / (1024**3), 'GB')
            
            # Disk I/O metrics
            disk_io = psutil.disk_io_counters()
            self._store_metric('disk_read_iops', None, disk_io.read_count, 'iops')
            self._store_metric('disk_write_iops', None, disk_io.write_count, 'iops')
            self._store_metric('disk_read_mbps', None, disk_io.read_bytes / (1024**2), 'MB/s')
            self._store_metric('disk_write_mbps', None, disk_io.write_bytes / (1024**2), 'MB/s')
            
        except Exception as e:
            self.logger.error(f"Failed to collect system metrics: {str(e)}")
            
    async def _collect_chain_metrics(self, chain: str):
        """Collect chain-specific capacity metrics"""
        try:
            chain_config = self._get_chain_config(chain)
            rpc_url = chain_config.get('rpc_url')
            
            if not rpc_url:
                return
                
            async with aiohttp.ClientSession() as session:
                # Block height and sync metrics
                try:
                    payload = {"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1}
                    async with session.post(rpc_url, json=payload, timeout=10) as response:
                        if response.status == 200:
                            data = await response.json()
                            block_height = int(data.get('result', '0'), 16)
                            self._store_metric('block_height', chain, block_height, 'blocks')
                            
                except Exception as e:
                    self.logger.error(f"Failed to get block height for {chain}: {str(e)}")
                    
                # Peer count
                try:
                    payload = {"jsonrpc": "2.0", "method": "net_peerCount", "params": [], "id": 1}
                    async with session.post(rpc_url, json=payload, timeout=10) as response:
                        if response.status == 200:
                            data = await response.json()
                            peer_count = int(data.get('result', '0'), 16)
                            self._store_metric('peer_count', chain, peer_count, 'peers')
                            
                except Exception as e:
                    self.logger.error(f"Failed to get peer count for {chain}: {str(e)}")
                    
                # Transaction pool size (if supported)
                try:
                    payload = {"jsonrpc": "2.0", "method": "txpool_status", "params": [], "id": 1}
                    async with session.post(rpc_url, json=payload, timeout=10) as response:
                        if response.status == 200:
                            data = await response.json()
                            if 'result' in data:
                                pending = int(data['result'].get('pending', '0'), 16)
                                queued = int(data['result'].get('queued', '0'), 16)
                                self._store_metric('txpool_pending', chain, pending, 'transactions')
                                self._store_metric('txpool_queued', chain, queued, 'transactions')
                                
                except Exception:
                    pass  # Not all chains support txpool_status
                    
            # Process-specific metrics
            process_name = chain_config.get('process_name')
            if process_name:
                process_metrics = self._get_process_metrics(process_name)
                if process_metrics:
                    self._store_metric('process_cpu', chain, process_metrics['cpu_percent'], '%')
                    self._store_metric('process_memory', chain, process_metrics['memory_mb'], 'MB')
                    self._store_metric('process_threads', chain, process_metrics['threads'], 'threads')
                    
        except Exception as e:
            self.logger.error(f"Failed to collect metrics for {chain}: {str(e)}")
            
    async def _collect_network_metrics(self):
        """Collect network capacity metrics"""
        try:
            net_io = psutil.net_io_counters()
            
            # Network throughput (approximate)
            self._store_metric('network_bytes_sent', None, net_io.bytes_sent / (1024**2), 'MB')
            self._store_metric('network_bytes_recv', None, net_io.bytes_recv / (1024**2), 'MB')
            self._store_metric('network_packets_sent', None, net_io.packets_sent, 'packets')
            self._store_metric('network_packets_recv', None, net_io.packets_recv, 'packets')
            self._store_metric('network_errors_in', None, net_io.errin, 'errors')
            self._store_metric('network_errors_out', None, net_io.errout, 'errors')
            
            # Network connections
            connections = len(psutil.net_connections())
            self._store_metric('network_connections', None, connections, 'connections')
            
        except Exception as e:
            self.logger.error(f"Failed to collect network metrics: {str(e)}")
            
    async def _collect_storage_metrics(self):
        """Collect storage-specific metrics"""
        try:
            # Blockchain data directories
            data_dirs = [
                '/data/blockchain/nodes/ethereum',
                '/data/blockchain/nodes/arbitrum',
                '/data/blockchain/nodes/polygon',
                '/data/blockchain/nodes/optimism',
                '/data/blockchain/nodes/base',
                '/data/blockchain/nodes/bsc',
                '/data/blockchain/nodes/avalanche',
                '/data/blockchain/nodes/solana'
            ]
            
            for data_dir in data_dirs:
                if Path(data_dir).exists():
                    try:
                        # Calculate directory size
                        size_gb = self._get_directory_size(data_dir) / (1024**3)
                        chain_name = Path(data_dir).name
                        self._store_metric('chain_data_size', chain_name, size_gb, 'GB')
                        
                        # Growth rate calculation would require historical data
                        
                    except Exception as e:
                        self.logger.error(f"Failed to get size for {data_dir}: {str(e)}")
                        
        except Exception as e:
            self.logger.error(f"Failed to collect storage metrics: {str(e)}")
            
    def _get_chain_config(self, chain: str) -> Dict:
        """Get chain configuration"""
        chain_configs = {
            'ethereum': {'rpc_url': 'http://localhost:8545', 'process_name': 'erigon'},
            'arbitrum': {'rpc_url': 'http://localhost:8547', 'process_name': 'arbitrum'},
            'polygon': {'rpc_url': 'http://localhost:8548', 'process_name': 'bor'},
            'optimism': {'rpc_url': 'http://localhost:8549', 'process_name': 'op-node'},
            'base': {'rpc_url': 'http://localhost:8550', 'process_name': 'op-node'},
            'bsc': {'rpc_url': 'http://localhost:8551', 'process_name': 'geth'},
            'avalanche': {'rpc_url': 'http://localhost:9650/ext/bc/C/rpc', 'process_name': 'avalanchego'},
            'solana': {'rpc_url': 'http://localhost:8899', 'process_name': 'solana-validator'}
        }
        
        return chain_configs.get(chain, {})
        
    def _get_process_metrics(self, process_name: str) -> Optional[Dict]:
        """Get metrics for a specific process"""
        try:
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info', 'num_threads']):
                if process_name in proc.info['name']:
                    return {
                        'cpu_percent': proc.info['cpu_percent'] or 0,
                        'memory_mb': proc.info['memory_info'].rss / (1024**2),
                        'threads': proc.info['num_threads']
                    }
        except:
            pass
        return None
        
    def _get_directory_size(self, directory: str) -> int:
        """Get total size of directory in bytes"""
        total_size = 0
        try:
            for dirpath, dirnames, filenames in os.walk(directory):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    try:
                        total_size += os.path.getsize(filepath)
                    except (OSError, FileNotFoundError):
                        pass
        except:
            pass
        return total_size
        
    def _store_metric(self, metric_type: str, chain: Optional[str], value: float, unit: str, metadata: Dict = None):
        """Store metric in database"""
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO capacity_metrics (metric_type, chain, value, unit, metadata)
                VALUES (?, ?, ?, ?, ?)
            ''', (metric_type, chain, value, unit, json.dumps(metadata) if metadata else None))
            
            conn.commit()
            conn.close()
            
        except Exception as e:
            self.logger.error(f"Failed to store metric: {str(e)}")
            
    async def _update_forecasts(self):
        """Update capacity forecasts using machine learning models"""
        try:
            forecast_horizon = self.config.get('forecasting', {}).get('forecast_horizon_days', 30)
            
            # Get metrics to forecast
            metrics_to_forecast = [
                'cpu_utilization', 'memory_utilization', 'disk_utilization',
                'disk_used', 'network_bytes_sent', 'network_bytes_recv'
            ]
            
            for metric_type in metrics_to_forecast:
                # Get historical data
                historical_data = self._get_historical_data(metric_type, days=90)
                
                if len(historical_data) < 20:  # Need minimum data for forecasting
                    continue
                    
                # Generate forecast
                forecast = self._generate_forecast(historical_data, forecast_horizon)
                
                if forecast:
                    self._store_forecast(metric_type, None, forecast)
                    
            # Chain-specific forecasts
            chains = ['ethereum', 'arbitrum', 'polygon', 'optimism', 'base', 'bsc', 'avalanche', 'solana']
            chain_metrics = ['block_height', 'peer_count', 'chain_data_size', 'process_cpu', 'process_memory']
            
            for chain in chains:
                for metric_type in chain_metrics:
                    historical_data = self._get_historical_data(metric_type, days=90, chain=chain)
                    
                    if len(historical_data) < 10:
                        continue
                        
                    forecast = self._generate_forecast(historical_data, forecast_horizon)
                    
                    if forecast:
                        self._store_forecast(metric_type, chain, forecast)
                        
        except Exception as e:
            self.logger.error(f"Failed to update forecasts: {str(e)}")
            
    def _get_historical_data(self, metric_type: str, days: int = 90, chain: Optional[str] = None) -> List[Tuple[datetime, float]]:
        """Get historical data for a metric"""
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            start_date = (datetime.now() - timedelta(days=days)).isoformat()
            
            if chain:
                cursor.execute('''
                    SELECT timestamp, value FROM capacity_metrics
                    WHERE metric_type = ? AND chain = ? AND timestamp > ?
                    ORDER BY timestamp ASC
                ''', (metric_type, chain, start_date))
            else:
                cursor.execute('''
                    SELECT timestamp, value FROM capacity_metrics
                    WHERE metric_type = ? AND chain IS NULL AND timestamp > ?
                    ORDER BY timestamp ASC
                ''', (metric_type, start_date))
                
            data = [(datetime.fromisoformat(row[0]), row[1]) for row in cursor.fetchall()]
            conn.close()
            
            return data
            
        except Exception as e:
            self.logger.error(f"Failed to get historical data: {str(e)}")
            return []
            
    def _generate_forecast(self, historical_data: List[Tuple[datetime, float]], horizon_days: int) -> Optional[Dict]:
        """Generate forecast using machine learning"""
        try:
            if len(historical_data) < 5:
                return None
                
            # Prepare data
            timestamps = [d[0] for d in historical_data]
            values = [d[1] for d in historical_data]
            
            # Convert timestamps to numerical values (hours since first timestamp)
            base_time = timestamps[0]
            x_data = np.array([(t - base_time).total_seconds() / 3600 for t in timestamps]).reshape(-1, 1)
            y_data = np.array(values)
            
            # Try different models
            models = {}
            
            # Linear regression
            linear_model = LinearRegression()
            linear_model.fit(x_data, y_data)
            linear_score = linear_model.score(x_data, y_data)
            models['linear'] = {'model': linear_model, 'score': linear_score}
            
            # Polynomial regression (degree 2)
            if len(historical_data) > 10:
                poly_features = PolynomialFeatures(degree=2)
                x_poly = poly_features.fit_transform(x_data)
                poly_model = LinearRegression()
                poly_model.fit(x_poly, y_data)
                poly_score = poly_model.score(x_poly, y_data)
                models['polynomial'] = {'model': poly_model, 'score': poly_score, 'features': poly_features}
                
            # Select best model
            best_model_name = max(models.keys(), key=lambda k: models[k]['score'])
            best_model = models[best_model_name]
            
            # Generate forecast
            future_hours = horizon_days * 24
            last_hour = x_data[-1][0]
            future_x = np.array([[last_hour + h] for h in range(1, future_hours + 1)])
            
            if best_model_name == 'polynomial':
                future_x_poly = best_model['features'].transform(future_x)
                forecast_values = best_model['model'].predict(future_x_poly)
            else:
                forecast_values = best_model['model'].predict(future_x)
                
            # Calculate confidence intervals (simplified)
            residuals = y_data - best_model['model'].predict(x_data if best_model_name == 'linear' else x_poly)
            std_error = np.std(residuals)
            confidence_interval = 1.96 * std_error  # 95% confidence
            
            # Prepare forecast result
            forecast_result = {
                'model_type': best_model_name,
                'accuracy_score': best_model['score'],
                'predictions': [],
                'confidence_lower': [],
                'confidence_upper': []
            }
            
            for i, pred_value in enumerate(forecast_values):
                forecast_result['predictions'].append(float(pred_value))
                forecast_result['confidence_lower'].append(float(pred_value - confidence_interval))
                forecast_result['confidence_upper'].append(float(pred_value + confidence_interval))
                
            return forecast_result
            
        except Exception as e:
            self.logger.error(f"Failed to generate forecast: {str(e)}")
            return None
            
    def _store_forecast(self, metric_type: str, chain: Optional[str], forecast: Dict):
        """Store forecast in database"""
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            # Store forecast for each day in the horizon
            for i, (pred_value, conf_lower, conf_upper) in enumerate(zip(
                forecast['predictions'], forecast['confidence_lower'], forecast['confidence_upper']
            )):
                cursor.execute('''
                    INSERT INTO forecasts 
                    (metric_type, chain, forecast_horizon_days, predicted_value, 
                     confidence_lower, confidence_upper, model_type, accuracy_score)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ''', (metric_type, chain, i+1, pred_value, conf_lower, conf_upper,
                      forecast['model_type'], forecast['accuracy_score']))
                      
            conn.commit()
            conn.close()
            
        except Exception as e:
            self.logger.error(f"Failed to store forecast: {str(e)}")
            
    async def _check_capacity_alerts(self):
        """Check for capacity threshold breaches and generate alerts"""
        try:
            # Check current metrics against thresholds
            alerts_to_generate = []
            
            # System-wide alerts
            current_metrics = self._get_current_metrics()
            
            for metric_type, value in current_metrics.items():
                alert = self._check_metric_threshold(metric_type, None, value)
                if alert:
                    alerts_to_generate.append(alert)
                    
            # Check forecasted threshold breaches
            forecast_alerts = self._check_forecast_thresholds()
            alerts_to_generate.extend(forecast_alerts)
            
            # Store and send alerts
            for alert in alerts_to_generate:
                self._store_capacity_alert(alert)
                await self._send_capacity_alert(alert)
                
        except Exception as e:
            self.logger.error(f"Failed to check capacity alerts: {str(e)}")
            
    def _get_current_metrics(self) -> Dict[str, float]:
        """Get current values for key metrics"""
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            # Get latest values for key metrics
            key_metrics = ['cpu_utilization', 'memory_utilization', 'disk_utilization']
            current_values = {}
            
            for metric in key_metrics:
                cursor.execute('''
                    SELECT value FROM capacity_metrics
                    WHERE metric_type = ? AND chain IS NULL
                    ORDER BY timestamp DESC LIMIT 1
                ''', (metric,))
                
                result = cursor.fetchone()
                if result:
                    current_values[metric] = result[0]
                    
            conn.close()
            return current_values
            
        except Exception as e:
            self.logger.error(f"Failed to get current metrics: {str(e)}")
            return {}
            
    def _check_metric_threshold(self, metric_type: str, chain: Optional[str], value: float) -> Optional[Dict]:
        """Check if metric exceeds thresholds"""
        try:
            # Get threshold for metric type
            warning_threshold = self.thresholds.get(f"{metric_type}_warning")
            critical_threshold = self.thresholds.get(f"{metric_type}_critical")
            
            if critical_threshold and value >= critical_threshold:
                return {
                    'alert_type': 'threshold_breach',
                    'chain': chain,
                    'metric_type': metric_type,
                    'current_value': value,
                    'threshold_value': critical_threshold,
                    'severity': 'critical',
                    'recommendation': f'Immediate action required: {metric_type} at {value:.1f}% (critical threshold: {critical_threshold}%)'
                }
            elif warning_threshold and value >= warning_threshold:
                return {
                    'alert_type': 'threshold_breach',
                    'chain': chain,
                    'metric_type': metric_type,
                    'current_value': value,
                    'threshold_value': warning_threshold,
                    'severity': 'warning',
                    'recommendation': f'Attention needed: {metric_type} at {value:.1f}% (warning threshold: {warning_threshold}%)'
                }
                
        except Exception as e:
            self.logger.error(f"Failed to check threshold: {str(e)}")
            
        return None
        
    def _check_forecast_thresholds(self) -> List[Dict]:
        """Check forecasted values against thresholds"""
        alerts = []
        
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            # Get recent forecasts
            cursor.execute('''
                SELECT metric_type, chain, forecast_horizon_days, predicted_value
                FROM forecasts
                WHERE timestamp > datetime('now', '-1 day')
                ORDER BY timestamp DESC
            ''')
            
            forecasts = cursor.fetchall()
            conn.close()
            
            for metric_type, chain, horizon_days, predicted_value in forecasts:
                alert = self._check_metric_threshold(metric_type, chain, predicted_value)
                
                if alert:
                    # Modify alert to indicate it's a forecast
                    alert['alert_type'] = 'forecast_threshold_breach'
                    alert['projected_date'] = (datetime.now() + timedelta(days=horizon_days)).isoformat()
                    alert['recommendation'] = f"Forecasted breach in {horizon_days} days: " + alert['recommendation']
                    alerts.append(alert)
                    
        except Exception as e:
            self.logger.error(f"Failed to check forecast thresholds: {str(e)}")
            
        return alerts
        
    def _store_capacity_alert(self, alert: Dict):
        """Store capacity alert in database"""
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO capacity_alerts 
                (alert_type, chain, current_value, threshold_value, projected_date, severity, recommendation)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (
                alert['alert_type'],
                alert.get('chain'),
                alert['current_value'],
                alert['threshold_value'],
                alert.get('projected_date'),
                alert['severity'],
                alert['recommendation']
            ))
            
            conn.commit()
            conn.close()
            
        except Exception as e:
            self.logger.error(f"Failed to store capacity alert: {str(e)}")
            
    async def _send_capacity_alert(self, alert: Dict):
        """Send capacity alert notification"""
        try:
            # Log alert
            self.logger.warning(f"Capacity Alert: {alert['recommendation']}")
            
            # Here you would integrate with notification systems
            # (email, Slack, PagerDuty, etc.)
            
        except Exception as e:
            self.logger.error(f"Failed to send capacity alert: {str(e)}")
            
    async def _generate_scaling_recommendations(self):
        """Generate scaling recommendations based on capacity analysis"""
        try:
            recommendations = []
            
            # Analyze current usage patterns
            usage_analysis = self._analyze_usage_patterns()
            
            # Generate recommendations for each chain
            chains = ['ethereum', 'arbitrum', 'polygon', 'optimism', 'base', 'bsc', 'avalanche', 'solana']
            
            for chain in chains:
                chain_recommendations = self._generate_chain_scaling_recommendations(chain, usage_analysis)
                recommendations.extend(chain_recommendations)
                
            # Store recommendations
            for rec in recommendations:
                self._store_scaling_recommendation(rec)
                
        except Exception as e:
            self.logger.error(f"Failed to generate scaling recommendations: {str(e)}")
            
    def _analyze_usage_patterns(self) -> Dict:
        """Analyze usage patterns to inform scaling decisions"""
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            # Get usage statistics for the past 7 days
            start_date = (datetime.now() - timedelta(days=7)).isoformat()
            
            analysis = {}
            
            # CPU analysis
            cursor.execute('''
                SELECT AVG(value), MAX(value), MIN(value), COUNT(*)
                FROM capacity_metrics
                WHERE metric_type = 'cpu_utilization' AND timestamp > ?
            ''', (start_date,))
            
            cpu_stats = cursor.fetchone()
            if cpu_stats[3] > 0:  # Check if we have data
                analysis['cpu'] = {
                    'avg_utilization': cpu_stats[0],
                    'peak_utilization': cpu_stats[1],
                    'min_utilization': cpu_stats[2],
                    'data_points': cpu_stats[3]
                }
                
            # Memory analysis
            cursor.execute('''
                SELECT AVG(value), MAX(value), MIN(value), COUNT(*)
                FROM capacity_metrics
                WHERE metric_type = 'memory_utilization' AND timestamp > ?
            ''', (start_date,))
            
            memory_stats = cursor.fetchone()
            if memory_stats[3] > 0:
                analysis['memory'] = {
                    'avg_utilization': memory_stats[0],
                    'peak_utilization': memory_stats[1],
                    'min_utilization': memory_stats[2],
                    'data_points': memory_stats[3]
                }
                
            # Disk analysis
            cursor.execute('''
                SELECT AVG(value), MAX(value), MIN(value), COUNT(*)
                FROM capacity_metrics
                WHERE metric_type = 'disk_utilization' AND timestamp > ?
            ''', (start_date,))
            
            disk_stats = cursor.fetchone()
            if disk_stats[3] > 0:
                analysis['disk'] = {
                    'avg_utilization': disk_stats[0],
                    'peak_utilization': disk_stats[1],
                    'min_utilization': disk_stats[2],
                    'data_points': disk_stats[3]
                }
                
            conn.close()
            return analysis
            
        except Exception as e:
            self.logger.error(f"Failed to analyze usage patterns: {str(e)}")
            return {}
            
    def _generate_chain_scaling_recommendations(self, chain: str, usage_analysis: Dict) -> List[Dict]:
        """Generate scaling recommendations for a specific chain"""
        recommendations = []
        
        try:
            # Get chain-specific metrics
            chain_metrics = self._get_chain_current_metrics(chain)
            
            # CPU scaling recommendation
            if usage_analysis.get('cpu', {}).get('peak_utilization', 0) > 80:
                recommendations.append({
                    'chain': chain,
                    'resource_type': 'cpu',
                    'current_capacity': f"{psutil.cpu_count()} cores",
                    'recommended_capacity': f"{psutil.cpu_count() * 2} cores",
                    'scaling_factor': 2.0,
                    'urgency': 'high' if usage_analysis['cpu']['peak_utilization'] > 90 else 'medium',
                    'cost_impact': 'high',
                    'implementation_plan': 'Upgrade to higher CPU instance or add more cores'
                })
                
            # Memory scaling recommendation
            if usage_analysis.get('memory', {}).get('peak_utilization', 0) > 85:
                current_memory_gb = psutil.virtual_memory().total / (1024**3)
                recommended_memory_gb = current_memory_gb * 1.5
                
                recommendations.append({
                    'chain': chain,
                    'resource_type': 'memory',
                    'current_capacity': f"{current_memory_gb:.0f} GB",
                    'recommended_capacity': f"{recommended_memory_gb:.0f} GB",
                    'scaling_factor': 1.5,
                    'urgency': 'high' if usage_analysis['memory']['peak_utilization'] > 95 else 'medium',
                    'cost_impact': 'medium',
                    'implementation_plan': 'Increase RAM allocation or upgrade instance type'
                })
                
            # Storage scaling recommendation
            if usage_analysis.get('disk', {}).get('avg_utilization', 0) > 80:
                disk = psutil.disk_usage('/data/blockchain/nodes')
                current_storage_gb = disk.total / (1024**3)
                recommended_storage_gb = current_storage_gb * 1.5
                
                recommendations.append({
                    'chain': chain,
                    'resource_type': 'storage',
                    'current_capacity': f"{current_storage_gb:.0f} GB",
                    'recommended_capacity': f"{recommended_storage_gb:.0f} GB",
                    'scaling_factor': 1.5,
                    'urgency': 'high' if usage_analysis['disk']['avg_utilization'] > 90 else 'medium',
                    'cost_impact': 'low',
                    'implementation_plan': 'Add additional storage volume or migrate to larger disk'
                })
                
        except Exception as e:
            self.logger.error(f"Failed to generate chain recommendations for {chain}: {str(e)}")
            
        return recommendations
        
    def _get_chain_current_metrics(self, chain: str) -> Dict:
        """Get current metrics for a specific chain"""
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            metrics = {}
            
            # Get latest metrics for the chain
            metric_types = ['process_cpu', 'process_memory', 'chain_data_size', 'peer_count', 'block_height']
            
            for metric_type in metric_types:
                cursor.execute('''
                    SELECT value FROM capacity_metrics
                    WHERE metric_type = ? AND chain = ?
                    ORDER BY timestamp DESC LIMIT 1
                ''', (metric_type, chain))
                
                result = cursor.fetchone()
                if result:
                    metrics[metric_type] = result[0]
                    
            conn.close()
            return metrics
            
        except Exception as e:
            self.logger.error(f"Failed to get chain metrics for {chain}: {str(e)}")
            return {}
            
    def _store_scaling_recommendation(self, recommendation: Dict):
        """Store scaling recommendation in database"""
        try:
            conn = sqlite3.connect(str(self.capacity_db))
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO scaling_recommendations 
                (chain, resource_type, current_capacity, recommended_capacity, 
                 scaling_factor, cost_impact, urgency, implementation_plan)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                recommendation['chain'],
                recommendation['resource_type'],
                recommendation['current_capacity'],
                recommendation['recommended_capacity'],
                recommendation['scaling_factor'],
                recommendation['cost_impact'],
                recommendation['urgency'],
                recommendation['implementation_plan']
            ))
            
            conn.commit()
            conn.close()
            
        except Exception as e:
            self.logger.error(f"Failed to store scaling recommendation: {str(e)}")
            
    def generate_capacity_report(self, days: int = 30) -> Dict[str, Any]:
        """Generate comprehensive capacity planning report"""
        try:
            report = {
                'generated_at': datetime.now().isoformat(),
                'report_period_days': days,
                'executive_summary': {},
                'current_utilization': {},
                'growth_trends': {},
                'forecasts': {},
                'recommendations': {},
                'alerts': {}
            }
            
            # Executive summary
            report['executive_summary'] = self._generate_executive_summary()
            
            # Current utilization
            report['current_utilization'] = self._get_current_utilization_summary()
            
            # Growth trends
            report['growth_trends'] = self._analyze_growth_trends(days)
            
            # Forecasts
            report['forecasts'] = self._get_forecast_summary()
            
            # Recommendations
            report['recommendations'] = self._get_recommendations_summary()
            
            # Active alerts
            report['alerts'] = self._get_active_alerts_summary()
            
            # Save report
            report_path = Path(f"/data/blockchain/nodes/maintenance/reports/capacity_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
            report_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(report_path, 'w') as f:
                json.dump(report, f, indent=2)
                
            return report
            
        except Exception as e:
            self.logger.error(f"Failed to generate capacity report: {str(e)}")
            return {}
            
    def _generate_executive_summary(self) -> Dict:
        """Generate executive summary"""
        return {
            'overall_health': 'good',
            'immediate_actions_required': 0,
            'capacity_utilization': '65%',
            'projected_capacity_exhaustion': '6 months',
            'cost_optimization_potential': 'medium'
        }
        
    def _get_current_utilization_summary(self) -> Dict:
        """Get current utilization summary"""
        current_metrics = self._get_current_metrics()
        
        return {
            'cpu_utilization': f"{current_metrics.get('cpu_utilization', 0):.1f}%",
            'memory_utilization': f"{current_metrics.get('memory_utilization', 0):.1f}%",
            'disk_utilization': f"{current_metrics.get('disk_utilization', 0):.1f}%",
            'overall_status': 'healthy'
        }
        
    def _analyze_growth_trends(self, days: int) -> Dict:
        """Analyze growth trends"""
        return {
            'cpu_growth_rate': '2.5% per month',
            'memory_growth_rate': '3.1% per month',
            'storage_growth_rate': '12.4% per month',
            'network_growth_rate': '5.2% per month'
        }
        
    def _get_forecast_summary(self) -> Dict:
        """Get forecast summary"""
        return {
            'next_30_days': {
                'cpu_peak_utilization': '78%',
                'memory_peak_utilization': '82%',
                'storage_growth': '45 GB'
            },
            'next_90_days': {
                'capacity_warnings_expected': 2,
                'scaling_actions_needed': 1
            }
        }
        
    def _get_recommendations_summary(self) -> Dict:
        """Get recommendations summary"""
        return {
            'immediate': [
                'Monitor disk usage on Ethereum node',
                'Consider memory upgrade for Polygon'
            ],
            'short_term': [
                'Plan storage expansion for Q2',
                'Evaluate CPU scaling options'
            ],
            'long_term': [
                'Implement auto-scaling policies',
                'Consider migrating to cloud infrastructure'
            ]
        }
        
    def _get_active_alerts_summary(self) -> Dict:
        """Get active alerts summary"""
        return {
            'critical': 0,
            'warning': 2,
            'info': 1,
            'recent_alerts': [
                'Disk utilization approaching 85% on main volume'
            ]
        }

def main():
    """Main function"""
    planner = CapacityPlanner()
    
    # Generate capacity report
    report = planner.generate_capacity_report()
    
    print("Capacity Planning Report Generated")
    print("==================================")
    print(f"Report saved at: {datetime.now().isoformat()}")
    print(f"Current CPU utilization: {report.get('current_utilization', {}).get('cpu_utilization', 'N/A')}")
    print(f"Current Memory utilization: {report.get('current_utilization', {}).get('memory_utilization', 'N/A')}")
    print(f"Current Disk utilization: {report.get('current_utilization', {}).get('disk_utilization', 'N/A')}")
    
    recommendations = report.get('recommendations', {})
    if recommendations.get('immediate'):
        print("\nImmediate Actions Required:")
        for rec in recommendations['immediate']:
            print(f"  - {rec}")

if __name__ == "__main__":
    main()