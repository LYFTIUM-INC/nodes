#!/bin/bash

# MEV Infrastructure Monitoring Setup
# Phase 4: Comprehensive monitoring and alerting

set -e

echo "🔧 Setting up MEV infrastructure monitoring..."

# Create monitoring directory
mkdir -p /data/blockchain/nodes/monitoring
cd /data/blockchain/nodes/monitoring

# 1. Kafka Producer Health Monitor
echo "📊 Setting up Kafka producer monitoring..."
cat > kafka-producer-monitor.py << 'PYTHON'
#!/usr/bin/env python3

import time
import json
import subprocess
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class KafkaProducerMonitor:
    def __init__(self):
        self.spool_directory = "/data/blockchain/nodes/data/kafka-spools"
        self.alert_threshold_mb = 50
        self.producer_health_file = "/tmp/kafka-producer-health.json"
    
    def check_spool_size(self):
        """Check spool directory size and alert if threshold exceeded"""
        try:
            result = subprocess.run(['du', '-sm', self.spool_directory], 
                                  capture_output=True, text=True)
            spool_size_mb = int(result.stdout.split()[0])
            
            health_data = {
                'timestamp': datetime.now().isoformat(),
                'spool_size_mb': spool_size_mb,
                'alert_threshold_mb': self.alert_threshold_mb,
                'status': 'healthy' if spool_size_mb < self.alert_threshold_mb else 'alert'
            }
            
            with open(self.producer_health_file, 'w') as f:
                json.dump(health_data, f, indent=2)
            
            if spool_size_mb >= self.alert_threshold_mb:
                logger.error(f"🚨 ALERT: Spool size {spool_size_mb}MB exceeds threshold {self.alert_threshold_mb}MB")
                return False
            else:
                logger.info(f"✅ Spool size {spool_size_mb}MB within threshold")
                return True
                
        except Exception as e:
            logger.error(f"❌ Error checking spool size: {e}")
            return False
    
    def monitor_loop(self):
        """Main monitoring loop"""
        logger.info("🚀 Starting Kafka Producer Health Monitor")
        
        while True:
            self.check_spool_size()
            time.sleep(30)  # Check every 30 seconds

if __name__ == "__main__":
    monitor = KafkaProducerMonitor()
    monitor.monitor_loop()
PYTHON

chmod +x kafka-producer-monitor.py

# 2. Redis Queue Performance Monitor
echo "📈 Setting up Redis queue performance monitoring..."
cat > redis-queue-monitor.py << 'PYTHON'
#!/usr/bin/env python3

import time
import json
import redis
import statistics
from datetime import datetime, timedelta
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class RedisQueueMonitor:
    def __init__(self):
        self.redis_client = redis.Redis(host='localhost', port=6379, db=0)
        self.latency_threshold_ms = 100
        self.metrics_window = 100
        self.health_file = "/tmp/redis-queue-health.json"
        self.latency_history = []
    
    def test_queue_latency(self):
        """Test Redis BLPOP latency"""
        start_time = time.time()
        
        # Push test item and measure BLPOP time
        test_key = "mev_latency_test"
        self.redis_client.lpush(test_key, "test_payload")
        
        pop_start = time.time()
        result = self.redis_client.blpop([test_key], timeout=1)
        pop_end = time.time()
        
        latency_ms = (pop_end - pop_start) * 1000
        
        # Store latency history
        self.latency_history.append(latency_ms)
        if len(self.latency_history) > self.metrics_window:
            self.latency_history.pop(0)
        
        return latency_ms
    
    def calculate_metrics(self):
        """Calculate performance metrics"""
        if not self.latency_history:
            return None
        
        return {
            'avg_latency_ms': statistics.mean(self.latency_history),
            'p95_latency_ms': statistics.quantiles(self.latency_history, n=20)[18] * 1000,
            'p99_latency_ms': statistics.quantiles(self.latency_history, n=100)[98] * 1000,
            'min_latency_ms': min(self.latency_history),
            'max_latency_ms': max(self.latency_history)
        }
    
    def check_queue_health(self):
        """Check Redis queue performance and generate health report"""
        latency_ms = self.test_queue_latency()
        metrics = self.calculate_metrics()
        
        health_data = {
            'timestamp': datetime.now().isoformat(),
            'current_latency_ms': latency_ms,
            'metrics': metrics,
            'threshold_ms': self.latency_threshold_ms,
            'status': 'healthy' if latency_ms < self.latency_threshold_ms else 'alert'
        }
        
        with open(self.health_file, 'w') as f:
            json.dump(health_data, f, indent=2)
        
        if latency_ms >= self.latency_threshold_ms:
            logger.error(f"🚨 ALERT: Redis latency {latency_ms:.2f}ms exceeds threshold {self.latency_threshold_ms}ms")
            return False
        else:
            logger.info(f"✅ Redis latency {latency_ms:.2f}ms within threshold")
            return True
    
    def monitor_loop(self):
        """Main monitoring loop"""
        logger.info("🚀 Starting Redis Queue Performance Monitor")
        
        while True:
            self.check_queue_health()
            time.sleep(10)  # Check every 10 seconds

if __name__ == "__main__":
    monitor = RedisQueueMonitor()
    monitor.monitor_loop()
PYTHON

chmod +x redis-queue-monitor.py

# 3. MEV Pipeline Health Dashboard
echo "📋 Creating MEV Pipeline Health Dashboard..."
cat > mev-health-dashboard.py << 'PYTHON'
#!/usr/bin/env python3

import json
import time
import subprocess
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class MEVHealthDashboard:
    def __init__(self):
        self.services = [
            'mev-pipeline.service',
            'mev-execution.service', 
            'mev-dashboard.service',
            'kafka.service',
            'redis.service'
        ]
        self.health_file = "/tmp/mev-pipeline-health.json"
    
    def check_service_status(self, service_name):
        """Check systemd service status"""
        try:
            result = subprocess.run(['systemctl', 'is-active', service_name], 
                                  capture_output=True, text=True)
            status = result.stdout.strip()
            
            # Get additional service info
            info_result = subprocess.run(['systemctl', 'show', service_name, '--property=ActiveState,SubState'], 
                                        capture_output=True, text=True)
            
            return {
                'service': service_name,
                'status': status,
                'active': status == 'active',
                'details': info_result.stdout.strip()
            }
        except Exception as e:
            return {
                'service': service_name,
                'status': 'unknown',
                'active': False,
                'error': str(e)
            }
    
    def check_system_resources(self):
        """Check system resource usage"""
        try:
            # CPU usage
            cpu_result = subprocess.run(['top', '-bn1', '|', 'grep', 'Cpu(s)'], 
                                       shell=True, capture_output=True, text=True)
            
            # Memory usage  
            mem_result = subprocess.run(['free', '-m'], capture_output=True, text=True)
            
            return {
                'cpu_usage': cpu_result.stdout.strip() if cpu_result.returncode == 0 else 'unknown',
                'memory_usage': mem_result.stdout.strip() if mem_result.returncode == 0 else 'unknown'
            }
        except Exception as e:
            return {'error': str(e)}
    
    def generate_health_report(self):
        """Generate comprehensive health report"""
        health_report = {
            'timestamp': datetime.now().isoformat(),
            'services': {},
            'system_resources': self.check_system_resources(),
            'overall_status': 'healthy'
        }
        
        failed_services = []
        
        for service in self.services:
            service_health = self.check_service_status(service)
            health_report['services'][service] = service_health
            
            if not service_health['active']:
                failed_services.append(service)
        
        # Determine overall status
        if failed_services:
            health_report['overall_status'] = 'degraded' if len(failed_services) < 3 else 'critical'
            health_report['failed_services'] = failed_services
        
        # Save health report
        with open(self.health_file, 'w') as f:
            json.dump(health_report, f, indent=2)
        
        return health_report
    
    def monitor_loop(self):
        """Main monitoring loop"""
        logger.info("🚀 Starting MEV Pipeline Health Dashboard")
        
        while True:
            health_report = self.generate_health_report()
            
            # Log summary
            active_count = sum(1 for s in health_report['services'].values() if s['active'])
            total_count = len(health_report['services'])
            
            if health_report['overall_status'] == 'healthy':
                logger.info(f"✅ All systems operational ({active_count}/{total_count} services active)")
            else:
                logger.error(f"🚨 Systems degraded ({health_report['overall_status']}): {active_count}/{total_count} services active")
                
                # Log failed services
                for service, status in health_report['services'].items():
                    if not status['active']:
                        logger.error(f"  ❌ {service}: {status['status']}")
            
            time.sleep(60)  # Check every minute

if __name__ == "__main__":
    dashboard = MEVHealthDashboard()
    dashboard.monitor_loop()
PYTHON

chmod +x mev-health-dashboard.py

# 4. Create systemd services for monitoring
echo "⚙️ Creating systemd services for monitoring..."

# Kafka Producer Monitor Service
cat > /etc/systemd/system/kafka-producer-monitor.service << 'EOF'
[Unit]
Description=Kafka Producer Health Monitor
After=network.target kafka.service
Requires=kafka.service

[Service]
Type=simple
User=blockchain
Group=blockchain
WorkingDirectory=/data/blockchain/nodes/monitoring
ExecStart=/usr/bin/python3 /data/blockchain/nodes/monitoring/kafka-producer-monitor.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
