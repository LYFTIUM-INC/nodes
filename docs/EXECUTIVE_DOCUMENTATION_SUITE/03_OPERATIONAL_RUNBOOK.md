# Operational Runbook: MEV Infrastructure
**Version**: 2.0  
**Last Updated**: July 11, 2025  
**Classification**: Operational Documentation  
**Standard**: SRE Best Practices / ITIL v4

---

## 📋 Table of Contents

1. [Daily Operations](#daily-operations)
2. [System Startup Procedures](#system-startup-procedures)
3. [Health Monitoring](#health-monitoring)
4. [Incident Response](#incident-response)
5. [Maintenance Procedures](#maintenance-procedures)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Emergency Procedures](#emergency-procedures)
8. [Performance Tuning](#performance-tuning)

---

## 🌅 Daily Operations

### Morning Checklist (Start of Trading Day)

```bash
#!/bin/bash
# Daily startup verification script

echo "=== MEV Infrastructure Daily Startup Checklist ==="
echo "Time: $(date)"
echo "Operator: $USER"

# 1. Verify all nodes are synced
echo -e "\n[1/8] Checking node sync status..."
for node in ethereum base polygon arbitrum optimism avalanche; do
    echo -n "  $node: "
    curl -s http://localhost:8545/health | jq -r '.status'
done

# 2. Check MEV engine status
echo -e "\n[2/8] Verifying MEV engine components..."
systemctl status mev-detection mev-execution mev-analytics

# 3. Verify wallet balances
echo -e "\n[3/8] Checking operational wallet balances..."
python3 /opt/mev/scripts/check_wallets.py

# 4. Test oracle connectivity
echo -e "\n[4/8] Testing oracle price feeds..."
python3 /opt/mev/scripts/test_oracles.py

# 5. Review overnight alerts
echo -e "\n[5/8] Reviewing overnight incidents..."
journalctl -u mev-* --since "12 hours ago" | grep -E "ERROR|CRITICAL"

# 6. Check system resources
echo -e "\n[6/8] System resource check..."
df -h | grep -E "/$|/data"
free -h
top -bn1 | head -20

# 7. Verify monitoring dashboards
echo -e "\n[7/8] Dashboard accessibility check..."
curl -Is http://localhost:8091 | head -1
curl -Is http://localhost:3000 | head -1  # Grafana

# 8. Enable production mode
echo -e "\n[8/8] Enabling production trading mode..."
curl -X POST http://localhost:8090/api/v1/trading/enable \
     -H "Authorization: Bearer $MEV_API_TOKEN"

echo -e "\n=== Checklist Complete ==="
```

### Hourly Operations Tasks

| Time | Task | Command/Procedure | SLA |
|------|------|------------------|-----|
| :00 | Performance snapshot | `mev-cli snapshot create` | 2 min |
| :15 | Wallet balance check | `mev-cli wallet check --all` | 1 min |
| :30 | Oracle price verification | `mev-cli oracle verify` | 1 min |
| :45 | Competition analysis | `mev-cli competition report` | 3 min |

### End of Day Procedures

```bash
#!/bin/bash
# End of day procedures

# 1. Generate daily P&L report
mev-cli report daily --date today --output /reports/daily/

# 2. Backup transaction logs
tar -czf /backup/txlogs-$(date +%Y%m%d).tar.gz /data/logs/transactions/

# 3. Archive performance metrics
mev-cli metrics export --period 24h --format prometheus

# 4. Update strategy parameters
mev-cli strategy optimize --auto-commit

# 5. Send daily summary
mev-cli notify summary --recipients ops-team@company.com
```

---

## 🚀 System Startup Procedures

### Complete System Startup (Cold Start)

```bash
#!/bin/bash
# Master startup script - Execute with care!

echo "Starting MEV Infrastructure..."

# Phase 1: Infrastructure Layer
echo "[Phase 1/4] Starting blockchain nodes..."
systemctl start ethereum-erigon
systemctl start base-node
systemctl start polygon-bor polygon-heimdall
systemctl start arbitrum-nitro
systemctl start optimism-node
systemctl start avalanche-node

# Wait for sync
echo "Waiting for nodes to sync (this may take several minutes)..."
sleep 300

# Phase 2: Support Services
echo "[Phase 2/4] Starting support services..."
systemctl start redis
systemctl start postgresql
systemctl start nginx
systemctl start mev-oracle-aggregator

# Phase 3: MEV Core Engine
echo "[Phase 3/4] Starting MEV engine..."
systemctl start mev-detection
systemctl start mev-calculation
systemctl start mev-execution
systemctl start mev-monitoring

# Phase 4: Analytics & Monitoring
echo "[Phase 4/4] Starting monitoring systems..."
systemctl start prometheus
systemctl start grafana
systemctl start mev-dashboard
systemctl start alert-manager

echo "Startup complete! Verifying system health..."
mev-cli health check --full
```

### Service-Specific Startup

#### Ethereum Node Startup
```bash
# Start Ethereum node with MEV optimizations
systemctl start ethereum-erigon

# Verify startup
journalctl -u ethereum-erigon -f

# Check sync status
curl -X POST http://localhost:8545 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

#### MEV Engine Startup
```bash
# Pre-startup checks
mev-cli preflight check

# Start MEV services in order
systemctl start mev-detection
sleep 10
systemctl start mev-calculation
sleep 10
systemctl start mev-execution

# Verify operational status
mev-cli status --detailed
```

---

## 🏥 Health Monitoring

### Critical Health Checks

```python
#!/usr/bin/env python3
"""
MEV Infrastructure Health Monitor
Runs every 60 seconds via cron
"""

import requests
import json
from datetime import datetime

class HealthMonitor:
    def __init__(self):
        self.checks = {
            "node_sync": self.check_node_sync,
            "mev_engine": self.check_mev_engine,
            "wallet_balance": self.check_wallets,
            "oracle_feeds": self.check_oracles,
            "system_resources": self.check_resources
        }
        
    def run_all_checks(self):
        results = {}
        for name, check in self.checks.items():
            try:
                results[name] = check()
            except Exception as e:
                results[name] = {"status": "ERROR", "error": str(e)}
        
        return results
    
    def check_node_sync(self):
        """Verify all nodes are synced"""
        nodes = {
            "ethereum": "http://localhost:8545",
            "base": "http://localhost:8546",
            "polygon": "http://localhost:8547",
            "arbitrum": "http://localhost:8548",
            "optimism": "http://localhost:8549"
        }
        
        results = {}
        for name, url in nodes.items():
            try:
                resp = requests.post(url, json={
                    "jsonrpc": "2.0",
                    "method": "eth_syncing",
                    "params": [],
                    "id": 1
                })
                data = resp.json()
                results[name] = "synced" if data["result"] == False else "syncing"
            except:
                results[name] = "offline"
                
        return results
```

### Monitoring Dashboard URLs

| Dashboard | URL | Purpose | Update Frequency |
|-----------|-----|---------|------------------|
| Main Operations | http://localhost:8091 | Real-time MEV metrics | 1 second |
| Grafana | http://localhost:3000 | System metrics | 10 seconds |
| Prometheus | http://localhost:9090 | Raw metrics | 15 seconds |
| Alert Manager | http://localhost:9093 | Active alerts | Real-time |

### Key Metrics to Monitor

```yaml
# Prometheus alert rules
groups:
  - name: mev_critical
    interval: 30s
    rules:
      - alert: HighDetectionLatency
        expr: mev_detection_latency_ms > 15
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MEV detection latency exceeds 15ms"
          
      - alert: LowWalletBalance
        expr: mev_wallet_balance_eth < 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Wallet balance below 0.5 ETH"
          
      - alert: NodeOutOfSync
        expr: blockchain_sync_status != 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Blockchain node out of sync"
```

---

## 🚨 Incident Response

### Incident Classification

| Severity | Response Time | Examples | Escalation |
|----------|--------------|----------|------------|
| Critical | < 5 minutes | System down, major loss | VP Engineering |
| High | < 15 minutes | Performance degradation | Team Lead |
| Medium | < 1 hour | Minor issues | On-call Engineer |
| Low | < 4 hours | Cosmetic issues | Next shift |

### Critical Incident Response Playbook

#### 1. Initial Response (0-5 minutes)
```bash
# Incident response checklist
incident_response() {
    # 1. Acknowledge alert
    echo "[$(date)] Incident acknowledged by $USER"
    
    # 2. Initial assessment
    mev-cli health check --emergency
    
    # 3. Capture system state
    mev-cli debug snapshot --incident
    
    # 4. Notify stakeholders
    mev-cli notify incident --severity critical \
        --message "Investigating MEV system issue"
    
    # 5. Begin investigation
    tail -f /var/log/mev/*.log | grep -E "ERROR|CRITICAL"
}
```

#### 2. Common Incident Scenarios

##### Scenario: MEV Engine Not Detecting Opportunities
```bash
# Diagnostic steps
1. Check node connectivity
   curl -X POST http://localhost:8545 -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

2. Verify mempool access
   mev-cli mempool status

3. Check detection service
   systemctl status mev-detection
   journalctl -u mev-detection --since "10 minutes ago"

4. Restart detection engine
   systemctl restart mev-detection

5. Monitor recovery
   mev-cli monitor detection --realtime
```

##### Scenario: High Latency Alerts
```bash
# Performance troubleshooting
1. Check system resources
   htop
   iotop
   iftop

2. Analyze latency breakdown
   mev-cli latency analyze --components

3. Check network connectivity
   mtr ethereum-node.internal
   ping -c 10 oracle-api.chainlink.com

4. Review recent changes
   git log --oneline -10
   mev-cli config diff

5. Apply emergency optimizations
   mev-cli optimize emergency --apply
```

---

## 🔧 Maintenance Procedures

### Planned Maintenance Window

```bash
#!/bin/bash
# Planned maintenance procedure

# Pre-maintenance (T-30 minutes)
echo "[$(date)] Starting pre-maintenance procedures..."

# 1. Notify users
mev-cli notify maintenance --start-in 30m

# 2. Disable new trades
mev-cli trading disable --graceful

# 3. Complete in-flight transactions
mev-cli transactions wait --timeout 300

# 4. Create backup
mev-cli backup create --full

# During maintenance
echo "[$(date)] Entering maintenance mode..."

# 5. Stop services
systemctl stop mev-*

# 6. Perform maintenance tasks
# - Update software
# - Apply patches
# - Database maintenance
# - Log rotation

# 7. Start services
systemctl start mev-*

# Post-maintenance
echo "[$(date)] Completing maintenance..."

# 8. Verify system health
mev-cli health check --post-maintenance

# 9. Re-enable trading
mev-cli trading enable

# 10. Notify completion
mev-cli notify maintenance --completed
```

### Database Maintenance

```sql
-- Weekly PostgreSQL maintenance
-- Run during low-activity periods

-- 1. Analyze tables for query optimization
ANALYZE mev_opportunities;
ANALYZE mev_transactions;
ANALYZE mev_profits;

-- 2. Vacuum to reclaim space
VACUUM ANALYZE mev_opportunities;
VACUUM ANALYZE mev_transactions;

-- 3. Reindex for performance
REINDEX TABLE mev_opportunities;
REINDEX TABLE mev_transactions;

-- 4. Update statistics
SELECT pg_stat_reset();

-- 5. Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables 
WHERE schemaname = 'mev'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

---

## 🔍 Troubleshooting Guide

### Common Issues and Solutions

#### Issue: Node Sync Falling Behind
```bash
# Symptoms: Increasing block lag, missed opportunities

# Solution 1: Check peer connections
curl -X POST http://localhost:8545 \
     -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Solution 2: Increase peer limit
sed -i 's/maxpeers=.*/maxpeers=100/g' /etc/erigon/config.toml
systemctl restart ethereum-erigon

# Solution 3: Add static peers
echo "enode://pubkey@ip:port" >> /data/ethereum/static-nodes.json

# Solution 4: Check disk I/O
iostat -x 1 10
# If disk is bottleneck, consider:
# - Moving to faster NVMe
# - Enabling RAID 0 for chaindata
```

#### Issue: Memory Leak in MEV Engine
```bash
# Symptoms: Gradual memory increase, eventual OOM

# Diagnosis
ps aux | grep mev
pmap -x <pid>
gdb -p <pid>

# Temporary fix
systemctl restart mev-detection

# Permanent fix
# 1. Enable memory profiling
export MEV_MEMORY_PROFILE=1
systemctl restart mev-detection

# 2. Analyze heap dump
go tool pprof http://localhost:6060/debug/pprof/heap

# 3. Apply memory limits
echo "LimitAS=32G" >> /etc/systemd/system/mev-detection.service
systemctl daemon-reload
```

### Performance Optimization Checklist

```bash
#!/bin/bash
# Performance optimization script

echo "=== MEV Performance Optimization ==="

# 1. CPU Optimization
echo "Setting CPU governor to performance..."
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance > $cpu
done

# 2. Network Optimization
echo "Applying network optimizations..."
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"

# 3. Disk I/O Optimization
echo "Setting disk scheduler..."
echo noop > /sys/block/nvme0n1/queue/scheduler
echo 256 > /sys/block/nvme0n1/queue/nr_requests

# 4. Memory Optimization
echo "Configuring huge pages..."
echo 2048 > /proc/sys/vm/nr_hugepages
echo always > /sys/kernel/mm/transparent_hugepage/enabled

# 5. Process Priority
echo "Setting process priorities..."
renice -20 $(pgrep mev-detection)
renice -20 $(pgrep mev-execution)

echo "Optimizations applied!"
```

---

## 🆘 Emergency Procedures

### Emergency Shutdown

```bash
#!/bin/bash
# EMERGENCY SHUTDOWN - Use only in critical situations!

echo "!!! EMERGENCY SHUTDOWN INITIATED !!!"
echo "Operator: $USER"
echo "Time: $(date)"
echo "Reason: $1"

# 1. Immediately stop all trading
curl -X POST http://localhost:8090/api/v1/emergency/stop \
     -H "Authorization: Bearer $EMERGENCY_TOKEN"

# 2. Cancel all pending transactions
mev-cli transactions cancel --all --force

# 3. Withdraw funds to cold storage
mev-cli wallet withdraw --emergency --to $COLD_WALLET

# 4. Stop all services
systemctl stop mev-* nginx redis postgresql

# 5. Capture system state
tar -czf /emergency/state-$(date +%s).tar.gz \
    /var/log/mev/ \
    /data/mev/state/ \
    /etc/mev/

# 6. Notify emergency contacts
mev-cli notify emergency --all-contacts \
    --message "Emergency shutdown completed: $1"

echo "Emergency shutdown complete"
```

### Disaster Recovery

```bash
#!/bin/bash
# Disaster recovery from backup

echo "=== Disaster Recovery Procedure ==="

# 1. Verify backup integrity
echo "Checking backup..."
mev-cli backup verify --latest

# 2. Stop all services
systemctl stop mev-* postgresql redis

# 3. Restore data
echo "Restoring from backup..."
mev-cli backup restore --latest --confirm

# 4. Restore configuration
cp -r /backup/latest/config/* /etc/mev/

# 5. Start services
systemctl start postgresql redis
sleep 30
systemctl start mev-*

# 6. Verify recovery
mev-cli health check --post-recovery

# 7. Resync with blockchain
mev-cli sync --fast

echo "Recovery complete!"
```

---

## 📞 Escalation Matrix

| Issue Type | Level 1 | Level 2 | Level 3 |
|------------|---------|---------|---------|
| System Down | On-call Engineer | Team Lead | VP Engineering |
| Performance | DevOps Engineer | Senior SRE | Director of Infrastructure |
| Security | Security Engineer | CISO | CEO |
| Financial Loss | Trading Ops | CFO | CEO |

### On-Call Rotation

```yaml
# On-call schedule configuration
on_call_schedule:
  primary:
    - name: John Smith
      phone: +1-555-0100
      slack: @jsmith
      schedule: Mon-Wed
    
    - name: Jane Doe
      phone: +1-555-0101
      slack: @jdoe
      schedule: Thu-Sun
  
  secondary:
    - name: Bob Johnson
      phone: +1-555-0102
      slack: @bjohnson
      schedule: Always
  
  escalation:
    team_lead:
      name: Alice Williams
      phone: +1-555-0200
      slack: @awilliams
    
    director:
      name: Charlie Brown
      phone: +1-555-0300
      slack: @cbrown
```

---

*This operational runbook provides comprehensive procedures for operating, maintaining, and troubleshooting the MEV infrastructure. It should be reviewed and updated monthly to reflect system changes and lessons learned from incidents.*