# Performance Monitoring Guide - Advanced Optimization & KPI Dashboards
**Version 3.6.5 | July 2025**

## Table of Contents
1. [Performance KPI Overview](#performance-kpi-overview)
2. [Real-Time Dashboard Configuration](#real-time-dashboard-configuration)
3. [Performance Baseline Tracking](#performance-baseline-tracking)
4. [Latency Optimization Procedures](#latency-optimization-procedures)
5. [Resource Utilization Monitoring](#resource-utilization-monitoring)
6. [Bottleneck Identification Workflows](#bottleneck-identification-workflows)
7. [Performance Tuning Protocols](#performance-tuning-protocols)

---

## Performance KPI Overview

### Critical Performance Metrics

| Metric | Target | Current | Status |
|--------|--------|---------|---------|
| RPC Latency | <10ms | 8.5ms | ✅ OPTIMAL |
| MEV Success Rate | >60% | 65% | ✅ GOOD |
| Transaction Throughput | >100 TPS | 125 TPS | ✅ EXCELLENT |
| Bundle Success Rate | >80% | 82% | ✅ GOOD |
| P99 Response Time | <50ms | 42ms | ✅ GOOD |
| System Uptime | 99.99% | 99.97% | ⚠️ MONITOR |
| Resource Efficiency | >85% | 87% | ✅ OPTIMAL |

### Performance Scoring Matrix

```yaml
performance_scoring:
  latency:
    excellent: < 5ms
    good: 5-10ms
    acceptable: 10-20ms
    poor: > 20ms
  
  success_rate:
    excellent: > 80%
    good: 60-80%
    acceptable: 40-60%
    poor: < 40%
  
  resource_utilization:
    optimal: 70-85%
    good: 60-70% or 85-90%
    warning: 50-60% or 90-95%
    critical: < 50% or > 95%
```

---

## Real-Time Dashboard Configuration

### Launch Performance Dashboard

```bash
# Start comprehensive performance dashboard
cd /data/blockchain/nodes/monitoring
python3 performance-dashboard-optimized.py &

# Access dashboards
echo "Main Dashboard: http://localhost:8080"
echo "MEV Dashboard: http://localhost:8082"
echo "Grafana: http://localhost:3000"
```

### Dashboard Components

#### 1. MEV Performance Dashboard
```python
# Configure MEV-specific metrics
cat > /data/blockchain/nodes/monitoring/mev_dashboard_config.py << 'EOF'
#!/usr/bin/env python3
import json
from datetime import datetime, timedelta

class MEVDashboardConfig:
    def __init__(self):
        self.metrics = {
            "real_time": {
                "opportunity_detection_rate": {
                    "query": "rate(mev_opportunities_detected[1m])",
                    "unit": "ops/sec",
                    "threshold": 10
                },
                "execution_latency": {
                    "query": "histogram_quantile(0.99, mev_execution_duration_bucket)",
                    "unit": "ms",
                    "threshold": 15
                },
                "profit_rate": {
                    "query": "rate(mev_profit_eth[5m])",
                    "unit": "ETH/min",
                    "threshold": 0.01
                }
            },
            "historical": {
                "daily_profit": {
                    "query": "sum(increase(mev_profit_eth[24h]))",
                    "unit": "ETH"
                },
                "success_rate": {
                    "query": "rate(mev_successful_bundles[1h]) / rate(mev_total_bundles[1h])",
                    "unit": "%"
                },
                "gas_efficiency": {
                    "query": "avg(mev_gas_used / mev_gas_limit)",
                    "unit": "%"
                }
            }
        }
    
    def generate_grafana_dashboard(self):
        """Generate Grafana dashboard JSON"""
        return {
            "dashboard": {
                "title": "MEV Performance Monitoring",
                "panels": [
                    {
                        "title": "Real-Time Opportunity Detection",
                        "type": "graph",
                        "targets": [{"expr": self.metrics["real_time"]["opportunity_detection_rate"]["query"]}],
                        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8}
                    },
                    {
                        "title": "Execution Latency P99",
                        "type": "gauge",
                        "targets": [{"expr": self.metrics["real_time"]["execution_latency"]["query"]}],
                        "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8}
                    },
                    {
                        "title": "Profit Rate",
                        "type": "stat",
                        "targets": [{"expr": self.metrics["real_time"]["profit_rate"]["query"]}],
                        "gridPos": {"x": 0, "y": 8, "w": 8, "h": 8}
                    }
                ]
            }
        }

# Apply configuration
config = MEVDashboardConfig()
with open('/etc/grafana/dashboards/mev_performance.json', 'w') as f:
    json.dump(config.generate_grafana_dashboard(), f)
EOF
```

#### 2. System Performance Dashboard
```bash
# Create system performance monitoring dashboard
cat > /data/blockchain/nodes/monitoring/templates/performance_dashboard.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Blockchain Performance Monitor</title>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #1a1a1a; color: #fff; }
        .metric-card { 
            background: #2a2a2a; 
            border: 1px solid #444; 
            border-radius: 8px; 
            padding: 20px; 
            margin: 10px;
            display: inline-block;
            min-width: 300px;
        }
        .metric-value { font-size: 48px; font-weight: bold; }
        .metric-label { font-size: 18px; color: #888; }
        .status-good { color: #4CAF50; }
        .status-warning { color: #FFC107; }
        .status-critical { color: #F44336; }
        #charts { margin-top: 30px; }
        .chart-container { 
            background: #2a2a2a; 
            border: 1px solid #444; 
            border-radius: 8px; 
            padding: 20px; 
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <h1>Enterprise Blockchain Performance Monitor</h1>
    
    <div id="metrics">
        <div class="metric-card">
            <div class="metric-label">RPC Latency</div>
            <div class="metric-value" id="latency">--ms</div>
        </div>
        <div class="metric-card">
            <div class="metric-label">MEV Success Rate</div>
            <div class="metric-value" id="success-rate">--%</div>
        </div>
        <div class="metric-card">
            <div class="metric-label">Active Nodes</div>
            <div class="metric-value" id="active-nodes">--</div>
        </div>
        <div class="metric-card">
            <div class="metric-label">Daily Profit</div>
            <div class="metric-value" id="daily-profit">-- ETH</div>
        </div>
    </div>
    
    <div id="charts">
        <div class="chart-container">
            <div id="latency-chart"></div>
        </div>
        <div class="chart-container">
            <div id="throughput-chart"></div>
        </div>
        <div class="chart-container">
            <div id="resource-chart"></div>
        </div>
    </div>
    
    <script>
        // Real-time metric updates
        function updateMetrics() {
            $.get('/api/metrics', function(data) {
                $('#latency').text(data.latency + 'ms').removeClass().addClass(
                    data.latency < 10 ? 'metric-value status-good' : 
                    data.latency < 20 ? 'metric-value status-warning' : 
                    'metric-value status-critical'
                );
                $('#success-rate').text(data.success_rate + '%').removeClass().addClass(
                    data.success_rate > 60 ? 'metric-value status-good' : 
                    data.success_rate > 40 ? 'metric-value status-warning' : 
                    'metric-value status-critical'
                );
                $('#active-nodes').text(data.active_nodes);
                $('#daily-profit').text(data.daily_profit.toFixed(3) + ' ETH');
            });
        }
        
        // Initialize charts
        function initCharts() {
            // Latency trend chart
            Plotly.newPlot('latency-chart', [{
                x: [],
                y: [],
                type: 'scatter',
                name: 'RPC Latency',
                line: { color: '#4CAF50' }
            }], {
                title: 'RPC Latency Trend (Last Hour)',
                yaxis: { title: 'Latency (ms)' },
                paper_bgcolor: '#2a2a2a',
                plot_bgcolor: '#2a2a2a',
                font: { color: '#fff' }
            });
            
            // Throughput chart
            Plotly.newPlot('throughput-chart', [{
                x: [],
                y: [],
                type: 'scatter',
                fill: 'tozeroy',
                name: 'Transactions/sec'
            }], {
                title: 'Transaction Throughput',
                yaxis: { title: 'TPS' },
                paper_bgcolor: '#2a2a2a',
                plot_bgcolor: '#2a2a2a',
                font: { color: '#fff' }
            });
            
            // Resource utilization
            Plotly.newPlot('resource-chart', [{
                labels: ['CPU', 'Memory', 'Disk I/O', 'Network'],
                values: [0, 0, 0, 0],
                type: 'pie',
                marker: {
                    colors: ['#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0']
                }
            }], {
                title: 'Resource Utilization',
                paper_bgcolor: '#2a2a2a',
                plot_bgcolor: '#2a2a2a',
                font: { color: '#fff' }
            });
        }
        
        // Update charts with live data
        function updateCharts() {
            $.get('/api/chart-data', function(data) {
                // Update latency chart
                Plotly.extendTraces('latency-chart', {
                    x: [[new Date()]],
                    y: [[data.current_latency]]
                }, [0]);
                
                // Keep only last 60 points
                if (document.getElementById('latency-chart').data[0].x.length > 60) {
                    Plotly.relayout('latency-chart', {
                        xaxis: {
                            range: [
                                new Date(Date.now() - 3600000),
                                new Date()
                            ]
                        }
                    });
                }
                
                // Update throughput
                Plotly.extendTraces('throughput-chart', {
                    x: [[new Date()]],
                    y: [[data.current_tps]]
                }, [0]);
                
                // Update resource pie
                Plotly.restyle('resource-chart', {
                    values: [[data.cpu, data.memory, data.disk_io, data.network]]
                });
            });
        }
        
        // Initialize and start updates
        $(document).ready(function() {
            initCharts();
            updateMetrics();
            updateCharts();
            
            setInterval(updateMetrics, 1000);
            setInterval(updateCharts, 5000);
        });
    </script>
</body>
</html>
EOF
```

---

## Performance Baseline Tracking

### Establish Performance Baselines

```python
# Performance baseline tracker
cat > /data/blockchain/nodes/monitoring/performance_baseline_tracker.py << 'EOF'
#!/usr/bin/env python3
import sqlite3
import numpy as np
from datetime import datetime, timedelta
import json

class PerformanceBaselineTracker:
    def __init__(self):
        self.db_path = "/data/blockchain/nodes/monitoring/performance_baselines.db"
        self.init_database()
    
    def init_database(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS baselines (
                metric TEXT,
                period TEXT,
                timestamp TIMESTAMP,
                mean REAL,
                std_dev REAL,
                p50 REAL,
                p95 REAL,
                p99 REAL,
                min_val REAL,
                max_val REAL,
                sample_count INTEGER,
                PRIMARY KEY (metric, period, timestamp)
            )
        ''')
        conn.execute('''
            CREATE TABLE IF NOT EXISTS raw_metrics (
                metric TEXT,
                value REAL,
                timestamp TIMESTAMP,
                metadata TEXT
            )
        ''')
        conn.commit()
        conn.close()
    
    def record_metric(self, metric: str, value: float, metadata: dict = None):
        """Record a performance metric"""
        conn = sqlite3.connect(self.db_path)
        conn.execute(
            "INSERT INTO raw_metrics (metric, value, timestamp, metadata) VALUES (?, ?, ?, ?)",
            (metric, value, datetime.now(), json.dumps(metadata or {}))
        )
        conn.commit()
        conn.close()
    
    def calculate_baseline(self, metric: str, period: str = "1h"):
        """Calculate performance baseline for a metric"""
        conn = sqlite3.connect(self.db_path)
        
        # Determine time window
        if period == "1h":
            window = timedelta(hours=1)
        elif period == "24h":
            window = timedelta(days=1)
        elif period == "7d":
            window = timedelta(days=7)
        else:
            window = timedelta(hours=1)
        
        # Fetch metrics
        cursor = conn.execute(
            """SELECT value FROM raw_metrics 
               WHERE metric = ? AND timestamp > ?
               ORDER BY timestamp""",
            (metric, datetime.now() - window)
        )
        values = [row[0] for row in cursor.fetchall()]
        
        if not values:
            return None
        
        # Calculate statistics
        baseline = {
            "metric": metric,
            "period": period,
            "timestamp": datetime.now(),
            "mean": np.mean(values),
            "std_dev": np.std(values),
            "p50": np.percentile(values, 50),
            "p95": np.percentile(values, 95),
            "p99": np.percentile(values, 99),
            "min_val": min(values),
            "max_val": max(values),
            "sample_count": len(values)
        }
        
        # Store baseline
        conn.execute(
            """INSERT OR REPLACE INTO baselines 
               (metric, period, timestamp, mean, std_dev, p50, p95, p99, min_val, max_val, sample_count)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            tuple(baseline.values())
        )
        conn.commit()
        conn.close()
        
        return baseline
    
    def detect_anomaly(self, metric: str, current_value: float) -> dict:
        """Detect if current value is anomalous compared to baseline"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.execute(
            """SELECT mean, std_dev, p95, p99 FROM baselines 
               WHERE metric = ? AND period = '1h' 
               ORDER BY timestamp DESC LIMIT 1""",
            (metric,)
        )
        baseline = cursor.fetchone()
        conn.close()
        
        if not baseline:
            return {"anomaly": False, "reason": "No baseline available"}
        
        mean, std_dev, p95, p99 = baseline
        
        # Check for anomalies
        if current_value > mean + 3 * std_dev:
            return {
                "anomaly": True,
                "severity": "high",
                "reason": f"Value {current_value} exceeds 3 standard deviations from mean {mean}",
                "baseline_mean": mean,
                "baseline_std": std_dev
            }
        elif current_value > p99:
            return {
                "anomaly": True,
                "severity": "medium",
                "reason": f"Value {current_value} exceeds 99th percentile {p99}",
                "baseline_p99": p99
            }
        elif current_value > p95:
            return {
                "anomaly": True,
                "severity": "low",
                "reason": f"Value {current_value} exceeds 95th percentile {p95}",
                "baseline_p95": p95
            }
        
        return {"anomaly": False, "within_baseline": True}

# Automated baseline monitoring
def monitor_performance_baselines():
    tracker = PerformanceBaselineTracker()
    
    # Define critical metrics
    metrics = [
        "rpc_latency_ms",
        "mev_success_rate",
        "transaction_throughput",
        "cpu_usage_percent",
        "memory_usage_percent",
        "disk_io_mbps",
        "network_latency_ms"
    ]
    
    # Calculate baselines
    for metric in metrics:
        for period in ["1h", "24h", "7d"]:
            baseline = tracker.calculate_baseline(metric, period)
            if baseline:
                print(f"Baseline for {metric} ({period}): mean={baseline['mean']:.2f}, p99={baseline['p99']:.2f}")
    
    # Check for anomalies
    import requests
    current_metrics = requests.get("http://localhost:8082/api/metrics").json()
    
    for metric, value in current_metrics.items():
        anomaly = tracker.detect_anomaly(metric, value)
        if anomaly["anomaly"]:
            print(f"ANOMALY DETECTED: {metric}={value} - {anomaly['reason']}")
EOF

chmod +x /data/blockchain/nodes/monitoring/performance_baseline_tracker.py
```

### Baseline Reporting

```bash
# Generate baseline report
cat > /data/blockchain/nodes/monitoring/generate_baseline_report.sh << 'EOF'
#!/bin/bash

REPORT_DATE=$(date +%Y%m%d)
REPORT_FILE="/data/blockchain/nodes/reports/baseline_report_$REPORT_DATE.md"

cat > $REPORT_FILE << REPORT
# Performance Baseline Report
Date: $(date)

## Executive Summary
This report provides performance baselines for the MEV infrastructure over multiple time periods.

## Baseline Metrics

### RPC Latency (milliseconds)
| Period | Mean | Std Dev | P50 | P95 | P99 | Min | Max |
|--------|------|---------|-----|-----|-----|-----|-----|
REPORT

# Query baseline data
sqlite3 /data/blockchain/nodes/monitoring/performance_baselines.db << SQL >> $REPORT_FILE
.mode markdown
SELECT period, 
       printf("%.2f", mean) as mean,
       printf("%.2f", std_dev) as std_dev,
       printf("%.2f", p50) as p50,
       printf("%.2f", p95) as p95,
       printf("%.2f", p99) as p99,
       printf("%.2f", min_val) as min,
       printf("%.2f", max_val) as max
FROM baselines 
WHERE metric = 'rpc_latency_ms' 
AND timestamp > datetime('now', '-1 day')
ORDER BY period;
SQL

echo "Baseline report generated: $REPORT_FILE"
EOF

chmod +x /data/blockchain/nodes/monitoring/generate_baseline_report.sh
```

---

## Latency Optimization Procedures

### Network Latency Analysis

```python
# Advanced latency analyzer
cat > /data/blockchain/nodes/performance/latency_analyzer.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import aiohttp
import time
import statistics
from typing import Dict, List
import json

class LatencyAnalyzer:
    def __init__(self):
        self.endpoints = {
            "ethereum_rpc": "http://localhost:8545",
            "arbitrum_rpc": "http://localhost:8590",
            "optimism_rpc": "http://localhost:8591",
            "base_rpc": "http://localhost:8592",
            "polygon_rpc": "http://localhost:8593",
            "mev_boost": "http://localhost:18550",
            "flashbots_relay": "https://relay.flashbots.net",
            "mev_engine": "http://localhost:8082"
        }
        self.results = {}
    
    async def measure_latency(self, name: str, url: str, payload: dict = None) -> Dict:
        """Measure latency for a single endpoint"""
        if payload is None:
            payload = {
                "jsonrpc": "2.0",
                "method": "eth_blockNumber",
                "params": [],
                "id": 1
            }
        
        latencies = []
        errors = 0
        
        async with aiohttp.ClientSession() as session:
            for _ in range(10):  # 10 measurements
                try:
                    start = time.perf_counter()
                    async with session.post(url, json=payload, timeout=5) as resp:
                        await resp.json()
                    latency = (time.perf_counter() - start) * 1000  # Convert to ms
                    latencies.append(latency)
                except Exception as e:
                    errors += 1
                
                await asyncio.sleep(0.1)  # Small delay between requests
        
        if latencies:
            return {
                "name": name,
                "url": url,
                "min": min(latencies),
                "max": max(latencies),
                "mean": statistics.mean(latencies),
                "median": statistics.median(latencies),
                "p95": statistics.quantiles(latencies, n=20)[18] if len(latencies) > 1 else latencies[0],
                "p99": statistics.quantiles(latencies, n=100)[98] if len(latencies) > 2 else max(latencies),
                "errors": errors,
                "samples": len(latencies)
            }
        else:
            return {
                "name": name,
                "url": url,
                "error": "All requests failed",
                "errors": errors
            }
    
    async def analyze_all_endpoints(self):
        """Analyze latency for all endpoints"""
        tasks = []
        for name, url in self.endpoints.items():
            tasks.append(self.measure_latency(name, url))
        
        results = await asyncio.gather(*tasks)
        self.results = {r["name"]: r for r in results}
        return self.results
    
    def generate_optimization_recommendations(self) -> List[Dict]:
        """Generate optimization recommendations based on analysis"""
        recommendations = []
        
        for name, metrics in self.results.items():
            if "error" in metrics:
                recommendations.append({
                    "endpoint": name,
                    "priority": "HIGH",
                    "issue": "Endpoint unreachable",
                    "recommendation": f"Check if {name} service is running and accessible"
                })
            elif metrics["p99"] > 50:  # Over 50ms P99
                recommendations.append({
                    "endpoint": name,
                    "priority": "HIGH",
                    "issue": f"High latency: P99={metrics['p99']:.1f}ms",
                    "recommendation": "Consider local caching, connection pooling, or infrastructure upgrade"
                })
            elif metrics["mean"] > 20:  # Over 20ms average
                recommendations.append({
                    "endpoint": name,
                    "priority": "MEDIUM",
                    "issue": f"Elevated latency: mean={metrics['mean']:.1f}ms",
                    "recommendation": "Optimize network path or implement request batching"
                })
            elif metrics["errors"] > 0:
                recommendations.append({
                    "endpoint": name,
                    "priority": "MEDIUM",
                    "issue": f"Intermittent errors: {metrics['errors']} failures",
                    "recommendation": "Implement retry logic and circuit breaker pattern"
                })
        
        return recommendations
    
    def export_results(self, filename: str):
        """Export results to JSON file"""
        output = {
            "timestamp": time.time(),
            "results": self.results,
            "recommendations": self.generate_optimization_recommendations()
        }
        
        with open(filename, 'w') as f:
            json.dump(output, f, indent=2)

# Run latency analysis
async def main():
    analyzer = LatencyAnalyzer()
    results = await analyzer.analyze_all_endpoints()
    
    print("=== Latency Analysis Results ===")
    for name, metrics in results.items():
        if "error" not in metrics:
            print(f"\n{name}:")
            print(f"  Mean: {metrics['mean']:.1f}ms")
            print(f"  P95: {metrics['p95']:.1f}ms")
            print(f"  P99: {metrics['p99']:.1f}ms")
    
    print("\n=== Optimization Recommendations ===")
    for rec in analyzer.generate_optimization_recommendations():
        print(f"\n[{rec['priority']}] {rec['endpoint']}")
        print(f"  Issue: {rec['issue']}")
        print(f"  Recommendation: {rec['recommendation']}")
    
    analyzer.export_results("/data/blockchain/nodes/reports/latency_analysis.json")

if __name__ == "__main__":
    asyncio.run(main())
EOF

chmod +x /data/blockchain/nodes/performance/latency_analyzer.py
```

### Latency Optimization Implementation

```bash
# Automated latency optimization script
cat > /data/blockchain/nodes/performance/optimize_latency.sh << 'EOF'
#!/bin/bash

echo "=== MEV Infrastructure Latency Optimization ==="
echo "Timestamp: $(date)"

# 1. Network stack optimization
echo -e "\n[1] Optimizing network stack..."
# Enable TCP Fast Open
echo 3 > /proc/sys/net/ipv4/tcp_fastopen
# Reduce TCP handshake time
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
echo 1 > /proc/sys/net/ipv4/tcp_tw_recycle
# Increase network buffers
echo 134217728 > /proc/sys/net/core/rmem_max
echo 134217728 > /proc/sys/net/core/wmem_max

# 2. DNS optimization
echo -e "\n[2] Optimizing DNS resolution..."
# Add local DNS cache
cat > /etc/dnsmasq.conf << DNS
cache-size=10000
no-negcache
server=8.8.8.8
server=1.1.1.1
DNS
systemctl restart dnsmasq

# 3. Connection pooling
echo -e "\n[3] Configuring connection pools..."
cat > /data/blockchain/nodes/config/connection_pools.yaml << POOLS
ethereum:
  min_connections: 10
  max_connections: 50
  connection_timeout: 1000ms
  keep_alive: true
  
mev_relays:
  min_connections: 5
  max_connections: 20
  connection_timeout: 500ms
  retry_count: 3
POOLS

# 4. Load balancer configuration
echo -e "\n[4] Optimizing load balancer..."
cat > /etc/haproxy/haproxy-mev.cfg << HAPROXY
global
    maxconn 10000
    tune.ssl.default-dh-param 2048
    
defaults
    timeout connect 1s
    timeout client 10s
    timeout server 10s
    option http-keep-alive
    
backend ethereum_nodes
    balance leastconn
    option httpchk POST / HTTP/1.1\\r\\nContent-Type:\ application/json\\r\\n\\r\\n{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}
    server eth1 127.0.0.1:8545 check inter 1000 fastinter 500
    server eth2 127.0.0.1:8546 check inter 1000 fastinter 500 backup
HAPROXY
systemctl reload haproxy

# 5. Redis optimization for caching
echo -e "\n[5] Optimizing Redis cache..."
cat >> /etc/redis/redis.conf << REDIS
maxmemory 4gb
maxmemory-policy allkeys-lru
tcp-keepalive 60
timeout 0
REDIS
systemctl restart redis

echo -e "\nLatency optimization complete!"
EOF

chmod +x /data/blockchain/nodes/performance/optimize_latency.sh
```

---

## Resource Utilization Monitoring

### Comprehensive Resource Monitor

```python
# Resource utilization tracker
cat > /data/blockchain/nodes/monitoring/resource_monitor.py << 'EOF'
#!/usr/bin/env python3
import psutil
import docker
import json
import time
from datetime import datetime
import sqlite3

class ResourceMonitor:
    def __init__(self):
        self.docker_client = docker.from_env()
        self.db_path = "/data/blockchain/nodes/monitoring/resource_metrics.db"
        self.init_database()
    
    def init_database(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS resource_metrics (
                timestamp TIMESTAMP,
                component TEXT,
                cpu_percent REAL,
                memory_percent REAL,
                memory_mb REAL,
                disk_io_read_mbps REAL,
                disk_io_write_mbps REAL,
                network_in_mbps REAL,
                network_out_mbps REAL,
                open_files INTEGER,
                threads INTEGER
            )
        ''')
        conn.commit()
        conn.close()
    
    def get_system_metrics(self) -> dict:
        """Get overall system metrics"""
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk_io = psutil.disk_io_counters()
        network_io = psutil.net_io_counters()
        
        return {
            "timestamp": datetime.now(),
            "component": "system",
            "cpu_percent": cpu_percent,
            "memory_percent": memory.percent,
            "memory_mb": memory.used / 1024 / 1024,
            "disk_io_read_mbps": disk_io.read_bytes / 1024 / 1024,
            "disk_io_write_mbps": disk_io.write_bytes / 1024 / 1024,
            "network_in_mbps": network_io.bytes_recv / 1024 / 1024,
            "network_out_mbps": network_io.bytes_sent / 1024 / 1024,
            "open_files": len(psutil.Process().open_files()),
            "threads": psutil.Process().num_threads()
        }
    
    def get_container_metrics(self) -> list:
        """Get metrics for all blockchain containers"""
        metrics = []
        
        for container in self.docker_client.containers.list():
            if any(chain in container.name for chain in ['ethereum', 'arbitrum', 'optimism', 'base', 'polygon', 'mev']):
                stats = container.stats(stream=False)
                
                # Calculate CPU percentage
                cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - \
                           stats['precpu_stats']['cpu_usage']['total_usage']
                system_delta = stats['cpu_stats']['system_cpu_usage'] - \
                              stats['precpu_stats']['system_cpu_usage']
                cpu_percent = (cpu_delta / system_delta) * 100.0 if system_delta > 0 else 0
                
                # Memory usage
                memory_usage = stats['memory_stats']['usage']
                memory_limit = stats['memory_stats']['limit']
                memory_percent = (memory_usage / memory_limit) * 100 if memory_limit > 0 else 0
                
                metrics.append({
                    "timestamp": datetime.now(),
                    "component": container.name,
                    "cpu_percent": cpu_percent,
                    "memory_percent": memory_percent,
                    "memory_mb": memory_usage / 1024 / 1024,
                    "disk_io_read_mbps": 0,  # Would need to track separately
                    "disk_io_write_mbps": 0,
                    "network_in_mbps": stats['networks']['eth0']['rx_bytes'] / 1024 / 1024 if 'networks' in stats else 0,
                    "network_out_mbps": stats['networks']['eth0']['tx_bytes'] / 1024 / 1024 if 'networks' in stats else 0,
                    "open_files": 0,
                    "threads": 0
                })
        
        return metrics
    
    def store_metrics(self, metrics: list):
        """Store metrics in database"""
        conn = sqlite3.connect(self.db_path)
        for metric in metrics:
            conn.execute('''
                INSERT INTO resource_metrics VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', tuple(metric.values()))
        conn.commit()
        conn.close()
    
    def get_resource_alerts(self) -> list:
        """Check for resource constraint alerts"""
        alerts = []
        
        # System metrics
        system_metrics = self.get_system_metrics()
        if system_metrics['cpu_percent'] > 90:
            alerts.append({
                "severity": "CRITICAL",
                "component": "system",
                "message": f"CPU usage critical: {system_metrics['cpu_percent']:.1f}%"
            })
        elif system_metrics['cpu_percent'] > 80:
            alerts.append({
                "severity": "WARNING",
                "component": "system",
                "message": f"CPU usage high: {system_metrics['cpu_percent']:.1f}%"
            })
        
        if system_metrics['memory_percent'] > 95:
            alerts.append({
                "severity": "CRITICAL",
                "component": "system",
                "message": f"Memory usage critical: {system_metrics['memory_percent']:.1f}%"
            })
        
        # Container metrics
        for metric in self.get_container_metrics():
            if metric['cpu_percent'] > 90:
                alerts.append({
                    "severity": "WARNING",
                    "component": metric['component'],
                    "message": f"Container CPU high: {metric['cpu_percent']:.1f}%"
                })
            if metric['memory_percent'] > 90:
                alerts.append({
                    "severity": "WARNING",
                    "component": metric['component'],
                    "message": f"Container memory high: {metric['memory_percent']:.1f}%"
                })
        
        return alerts
    
    def generate_resource_report(self) -> dict:
        """Generate comprehensive resource utilization report"""
        conn = sqlite3.connect(self.db_path)
        
        # Get average utilization over last hour
        query = '''
            SELECT component,
                   AVG(cpu_percent) as avg_cpu,
                   MAX(cpu_percent) as max_cpu,
                   AVG(memory_percent) as avg_memory,
                   MAX(memory_percent) as max_memory
            FROM resource_metrics
            WHERE timestamp > datetime('now', '-1 hour')
            GROUP BY component
        '''
        
        cursor = conn.execute(query)
        results = cursor.fetchall()
        conn.close()
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "components": {}
        }
        
        for row in results:
            component, avg_cpu, max_cpu, avg_memory, max_memory = row
            report["components"][component] = {
                "cpu": {
                    "average": round(avg_cpu, 2),
                    "peak": round(max_cpu, 2)
                },
                "memory": {
                    "average": round(avg_memory, 2),
                    "peak": round(max_memory, 2)
                }
            }
        
        return report

# Continuous monitoring loop
def monitor_resources():
    monitor = ResourceMonitor()
    
    while True:
        # Collect metrics
        metrics = [monitor.get_system_metrics()]
        metrics.extend(monitor.get_container_metrics())
        
        # Store in database
        monitor.store_metrics(metrics)
        
        # Check for alerts
        alerts = monitor.get_resource_alerts()
        for alert in alerts:
            print(f"[{alert['severity']}] {alert['component']}: {alert['message']}")
        
        # Generate hourly reports
        if datetime.now().minute == 0:
            report = monitor.generate_resource_report()
            with open(f"/data/blockchain/nodes/reports/resource_report_{datetime.now().strftime('%Y%m%d_%H')}.json", 'w') as f:
                json.dump(report, f, indent=2)
        
        time.sleep(60)  # Check every minute

if __name__ == "__main__":
    monitor_resources()
EOF

chmod +x /data/blockchain/nodes/monitoring/resource_monitor.py
```

---

## Bottleneck Identification Workflows

### Automated Bottleneck Detection

```python
# Bottleneck analyzer
cat > /data/blockchain/nodes/performance/bottleneck_analyzer.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import aiohttp
import psutil
import time
import statistics
from typing import Dict, List, Tuple
import json

class BottleneckAnalyzer:
    def __init__(self):
        self.metrics = {
            "cpu_bottleneck": False,
            "memory_bottleneck": False,
            "disk_io_bottleneck": False,
            "network_bottleneck": False,
            "database_bottleneck": False,
            "rpc_bottleneck": False
        }
        self.thresholds = {
            "cpu_usage": 80,
            "memory_usage": 85,
            "disk_io_util": 90,
            "network_util": 80,
            "db_query_time": 100,  # ms
            "rpc_response_time": 50  # ms
        }
    
    async def analyze_cpu_bottleneck(self) -> Tuple[bool, Dict]:
        """Check for CPU bottlenecks"""
        cpu_percent = psutil.cpu_percent(interval=5, percpu=True)
        avg_cpu = statistics.mean(cpu_percent)
        
        # Check for CPU saturation
        load_avg = psutil.getloadavg()
        cpu_count = psutil.cpu_count()
        
        bottleneck = avg_cpu > self.thresholds["cpu_usage"] or load_avg[0] > cpu_count
        
        return bottleneck, {
            "average_cpu": avg_cpu,
            "per_core": cpu_percent,
            "load_average": load_avg,
            "cpu_count": cpu_count,
            "bottleneck": bottleneck,
            "severity": "HIGH" if avg_cpu > 90 else "MEDIUM" if bottleneck else "LOW"
        }
    
    async def analyze_memory_bottleneck(self) -> Tuple[bool, Dict]:
        """Check for memory bottlenecks"""
        memory = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        bottleneck = memory.percent > self.thresholds["memory_usage"] or swap.percent > 50
        
        # Check for memory pressure
        with open('/proc/pressure/memory', 'r') as f:
            pressure = f.read()
        
        return bottleneck, {
            "memory_percent": memory.percent,
            "memory_available_gb": memory.available / 1024 / 1024 / 1024,
            "swap_percent": swap.percent,
            "memory_pressure": pressure.strip(),
            "bottleneck": bottleneck,
            "severity": "CRITICAL" if memory.percent > 95 else "HIGH" if bottleneck else "LOW"
        }
    
    async def analyze_disk_io_bottleneck(self) -> Tuple[bool, Dict]:
        """Check for disk I/O bottlenecks"""
        # Get initial counters
        disk_io_1 = psutil.disk_io_counters()
        await asyncio.sleep(1)
        disk_io_2 = psutil.disk_io_counters()
        
        # Calculate rates
        read_rate = (disk_io_2.read_bytes - disk_io_1.read_bytes) / 1024 / 1024  # MB/s
        write_rate = (disk_io_2.write_bytes - disk_io_1.write_bytes) / 1024 / 1024  # MB/s
        
        # Check disk utilization
        disk_usage = psutil.disk_usage('/')
        
        # Simple heuristic for bottleneck detection
        bottleneck = (read_rate + write_rate > 100) or disk_usage.percent > 90
        
        return bottleneck, {
            "read_rate_mbps": read_rate,
            "write_rate_mbps": write_rate,
            "disk_usage_percent": disk_usage.percent,
            "bottleneck": bottleneck,
            "severity": "HIGH" if disk_usage.percent > 95 else "MEDIUM" if bottleneck else "LOW"
        }
    
    async def analyze_network_bottleneck(self) -> Tuple[bool, Dict]:
        """Check for network bottlenecks"""
        # Test network latency to critical endpoints
        endpoints = [
            ("ethereum_rpc", "http://localhost:8545"),
            ("flashbots_relay", "https://relay.flashbots.net"),
            ("mev_boost", "http://localhost:18550")
        ]
        
        latencies = {}
        async with aiohttp.ClientSession() as session:
            for name, url in endpoints:
                try:
                    start = time.time()
                    async with session.get(url, timeout=5) as resp:
                        await resp.text()
                    latencies[name] = (time.time() - start) * 1000
                except:
                    latencies[name] = 999999  # Timeout/error
        
        # Get network stats
        net_io = psutil.net_io_counters()
        
        # Check for high latency or packet loss
        avg_latency = statistics.mean(latencies.values())
        bottleneck = avg_latency > 100 or any(l > 200 for l in latencies.values())
        
        return bottleneck, {
            "endpoint_latencies": latencies,
            "average_latency": avg_latency,
            "packets_dropped": net_io.dropin + net_io.dropout,
            "bottleneck": bottleneck,
            "severity": "HIGH" if avg_latency > 200 else "MEDIUM" if bottleneck else "LOW"
        }
    
    async def analyze_database_bottleneck(self) -> Tuple[bool, Dict]:
        """Check for database bottlenecks"""
        import psycopg2
        
        try:
            conn = psycopg2.connect(
                host="localhost",
                database="mev_db",
                user="mev_user",
                password="mev_password"
            )
            cursor = conn.cursor()
            
            # Test query performance
            start = time.time()
            cursor.execute("SELECT COUNT(*) FROM mev_opportunities WHERE timestamp > NOW() - INTERVAL '1 hour'")
            cursor.fetchone()
            query_time = (time.time() - start) * 1000
            
            # Check connection count
            cursor.execute("SELECT count(*) FROM pg_stat_activity")
            connection_count = cursor.fetchone()[0]
            
            # Check for long-running queries
            cursor.execute("""
                SELECT count(*) 
                FROM pg_stat_activity 
                WHERE state = 'active' 
                AND query_start < NOW() - INTERVAL '5 seconds'
            """)
            long_queries = cursor.fetchone()[0]
            
            conn.close()
            
            bottleneck = query_time > self.thresholds["db_query_time"] or connection_count > 90 or long_queries > 5
            
            return bottleneck, {
                "query_time_ms": query_time,
                "connection_count": connection_count,
                "long_running_queries": long_queries,
                "bottleneck": bottleneck,
                "severity": "HIGH" if long_queries > 10 else "MEDIUM" if bottleneck else "LOW"
            }
        except Exception as e:
            return True, {
                "error": str(e),
                "bottleneck": True,
                "severity": "CRITICAL"
            }
    
    async def analyze_all_bottlenecks(self) -> Dict:
        """Run all bottleneck analyses"""
        results = {}
        
        # Run all analyses concurrently
        analyses = [
            ("cpu", self.analyze_cpu_bottleneck()),
            ("memory", self.analyze_memory_bottleneck()),
            ("disk_io", self.analyze_disk_io_bottleneck()),
            ("network", self.analyze_network_bottleneck()),
            ("database", self.analyze_database_bottleneck())
        ]
        
        for name, analysis in analyses:
            bottleneck, details = await analysis
            results[name] = details
            self.metrics[f"{name}_bottleneck"] = bottleneck
        
        # Overall assessment
        critical_bottlenecks = [k for k, v in results.items() if v.get("severity") == "CRITICAL"]
        high_bottlenecks = [k for k, v in results.items() if v.get("severity") == "HIGH"]
        
        results["summary"] = {
            "has_bottlenecks": any(self.metrics.values()),
            "critical_bottlenecks": critical_bottlenecks,
            "high_bottlenecks": high_bottlenecks,
            "recommendations": self.generate_recommendations(results)
        }
        
        return results
    
    def generate_recommendations(self, results: Dict) -> List[str]:
        """Generate recommendations based on bottleneck analysis"""
        recommendations = []
        
        if results["cpu"]["bottleneck"]:
            recommendations.append("CPU: Consider upgrading CPU or optimizing compute-intensive operations")
            recommendations.append("CPU: Enable CPU affinity for critical processes")
        
        if results["memory"]["bottleneck"]:
            recommendations.append("Memory: Increase system RAM or optimize memory usage")
            recommendations.append("Memory: Review and tune application memory settings")
        
        if results["disk_io"]["bottleneck"]:
            recommendations.append("Disk: Upgrade to faster storage (NVMe SSD)")
            recommendations.append("Disk: Implement caching layer to reduce disk I/O")
        
        if results["network"]["bottleneck"]:
            recommendations.append("Network: Optimize network routes and reduce latency")
            recommendations.append("Network: Implement local caching for external API calls")
        
        if results["database"]["bottleneck"]:
            recommendations.append("Database: Optimize slow queries and add indexes")
            recommendations.append("Database: Consider database clustering or sharding")
        
        return recommendations

# Run bottleneck analysis
async def main():
    analyzer = BottleneckAnalyzer()
    results = await analyzer.analyze_all_bottlenecks()
    
    print("=== Bottleneck Analysis Results ===")
    print(json.dumps(results, indent=2))
    
    # Save to file
    with open("/data/blockchain/nodes/reports/bottleneck_analysis.json", 'w') as f:
        json.dump(results, f, indent=2)
    
    # Alert on critical bottlenecks
    if results["summary"]["critical_bottlenecks"]:
        print("\n⚠️  CRITICAL BOTTLENECKS DETECTED:")
        for bottleneck in results["summary"]["critical_bottlenecks"]:
            print(f"  - {bottleneck}")

if __name__ == "__main__":
    asyncio.run(main())
EOF

chmod +x /data/blockchain/nodes/performance/bottleneck_analyzer.py
```

---

## Performance Tuning Protocols

### Automated Performance Tuning

```bash
# Master performance tuning script
cat > /data/blockchain/nodes/performance/master_tuning.sh << 'EOF'
#!/bin/bash

echo "=== MEV Infrastructure Performance Tuning ==="
echo "Starting comprehensive performance optimization..."

# 1. CPU Optimization
echo -e "\n[1] CPU Optimization"
# Set performance governor
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance > $cpu 2>/dev/null
done

# Disable CPU frequency scaling
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
    cat ${cpu%_max_freq}_cpuinfo_max_freq > $cpu 2>/dev/null
done

# Set IRQ affinity for network interfaces
CORES=$(nproc)
for irq in $(grep eth /proc/interrupts | awk '{print $1}' | sed 's/://'); do
    echo $((CORES-1)) > /proc/irq/$irq/smp_affinity_list 2>/dev/null
done

# 2. Memory Optimization
echo -e "\n[2] Memory Optimization"
# Configure huge pages
echo 2048 > /proc/sys/vm/nr_hugepages
echo always > /sys/kernel/mm/transparent_hugepage/enabled

# Optimize memory parameters
echo 10 > /proc/sys/vm/swappiness
echo 1 > /proc/sys/vm/zone_reclaim_mode
echo 3 > /proc/sys/vm/drop_caches  # Clear caches

# 3. I/O Optimization
echo -e "\n[3] I/O Optimization"
# Set I/O scheduler for SSDs
for disk in /sys/block/nvme*n*/queue/scheduler; do
    echo none > $disk 2>/dev/null
done

# Increase read-ahead
for disk in /sys/block/*/queue/read_ahead_kb; do
    echo 4096 > $disk 2>/dev/null
done

# 4. Network Optimization
echo -e "\n[4] Network Optimization"
# TCP optimization
cat > /etc/sysctl.d/99-mev-network.conf << SYSCTL
# TCP Performance Tuning
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# Connection handling
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Security and performance
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-mev-network.conf

# 5. Service-specific optimization
echo -e "\n[5] Service Optimization"

# Optimize PostgreSQL for MEV workload
cat > /tmp/postgres_optimize.sql << SQL
-- Increase shared buffers
ALTER SYSTEM SET shared_buffers = '4GB';
-- Increase work memory
ALTER SYSTEM SET work_mem = '256MB';
-- Enable parallel queries
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
-- Optimize for SSDs
ALTER SYSTEM SET random_page_cost = 1.1;
-- Increase checkpoint segments
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
SQL
sudo -u postgres psql < /tmp/postgres_optimize.sql
systemctl reload postgresql

# Optimize Redis
cat >> /etc/redis/redis.conf << REDIS
# Performance optimizations
tcp-nodelay yes
tcp-backlog 65535
maxclients 10000
# Disable persistence for pure cache
save ""
appendonly no
REDIS
systemctl restart redis

# 6. Process Priority Optimization
echo -e "\n[6] Process Priority"
# Set high priority for critical services
renice -n -10 $(pgrep erigon)
renice -n -10 $(pgrep mev-boost)
renice -n -5 $(pgrep postgres)

# Set CPU affinity for MEV processes
MEV_PID=$(pgrep -f mev-infra)
if [ ! -z "$MEV_PID" ]; then
    taskset -cp 0-3 $MEV_PID  # Bind to first 4 cores
fi

# 7. Monitoring and Validation
echo -e "\n[7] Validating optimizations..."
# Check if optimizations are applied
echo "CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
echo "Huge Pages: $(cat /proc/meminfo | grep HugePages_Total)"
echo "Network buffers: $(sysctl net.core.rmem_max)"

echo -e "\nPerformance tuning complete!"
echo "Please monitor system performance for the next 30 minutes."
EOF

chmod +x /data/blockchain/nodes/performance/master_tuning.sh
```

### Performance Validation Script

```python
# Performance validation
cat > /data/blockchain/nodes/performance/validate_performance.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import time
import statistics
import json
from typing import Dict, List

class PerformanceValidator:
    def __init__(self):
        self.baseline_metrics = {
            "rpc_latency_target": 10,  # ms
            "mev_success_rate_target": 60,  # %
            "cpu_usage_target": 70,  # %
            "memory_usage_target": 80,  # %
            "transaction_throughput_target": 100  # TPS
        }
        self.results = {}
    
    async def validate_rpc_latency(self) -> Dict:
        """Validate RPC latency meets targets"""
        import aiohttp
        
        endpoints = [
            "http://localhost:8545",
            "http://localhost:8590",
            "http://localhost:8591"
        ]
        
        latencies = []
        for endpoint in endpoints:
            async with aiohttp.ClientSession() as session:
                for _ in range(10):
                    start = time.perf_counter()
                    try:
                        async with session.post(
                            endpoint,
                            json={"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1},
                            timeout=5
                        ) as resp:
                            await resp.json()
                        latency = (time.perf_counter() - start) * 1000
                        latencies.append(latency)
                    except:
                        pass
        
        avg_latency = statistics.mean(latencies) if latencies else 999
        p99_latency = statistics.quantiles(latencies, n=100)[98] if len(latencies) > 2 else 999
        
        return {
            "metric": "rpc_latency",
            "average": avg_latency,
            "p99": p99_latency,
            "target": self.baseline_metrics["rpc_latency_target"],
            "passed": avg_latency < self.baseline_metrics["rpc_latency_target"],
            "score": min(100, (self.baseline_metrics["rpc_latency_target"] / avg_latency) * 100) if avg_latency > 0 else 0
        }
    
    async def validate_all_metrics(self) -> Dict:
        """Run all performance validations"""
        validations = [
            self.validate_rpc_latency(),
            # Add other validations here
        ]
        
        results = await asyncio.gather(*validations)
        
        overall_score = statistics.mean([r["score"] for r in results])
        all_passed = all([r["passed"] for r in results])
        
        return {
            "timestamp": time.time(),
            "validations": results,
            "overall_score": overall_score,
            "all_passed": all_passed,
            "recommendation": "Performance optimal" if all_passed else "Tuning required"
        }

# Run validation
async def main():
    validator = PerformanceValidator()
    results = await validator.validate_all_metrics()
    
    print("=== Performance Validation Results ===")
    print(f"Overall Score: {results['overall_score']:.1f}%")
    print(f"Status: {results['recommendation']}")
    
    for validation in results["validations"]:
        status = "✅" if validation["passed"] else "❌"
        print(f"{status} {validation['metric']}: {validation['average']:.1f}ms (target: {validation['target']}ms)")

if __name__ == "__main__":
    asyncio.run(main())
EOF

chmod +x /data/blockchain/nodes/performance/validate_performance.py
```

---

## Appendix: Performance Quick Reference

### Key Performance Commands
```bash
# Check latency
curl -w "Time: %{time_total}s\n" -o /dev/null -s http://localhost:8545

# Monitor MEV performance
curl -s http://localhost:8082/metrics | grep mev_

# System performance
htop -d 1
iotop -o
nethogs

# Database performance
psql -U mev_user -d mev_db -c "SELECT * FROM pg_stat_activity WHERE state = 'active';"

# Redis performance
redis-cli --latency
redis-cli info stats
```

### Performance Tuning Checklist
- [ ] CPU governor set to performance
- [ ] Huge pages configured
- [ ] Network buffers optimized
- [ ] I/O scheduler optimized for SSDs
- [ ] Database indexes optimized
- [ ] Connection pooling enabled
- [ ] Caching layer active
- [ ] Monitoring dashboards running

### Performance Targets Summary
| Component | Metric | Target | Critical |
|-----------|--------|--------|----------|
| RPC | Latency | <10ms | >50ms |
| MEV | Success Rate | >60% | <40% |
| System | CPU Usage | <70% | >90% |
| System | Memory Usage | <80% | >95% |
| Network | Packet Loss | <0.1% | >1% |
| Database | Query Time | <100ms | >500ms |

---

**Document Classification**: CONFIDENTIAL - INTERNAL USE ONLY  
**Last Updated**: July 17, 2025  
**Next Review**: July 24, 2025