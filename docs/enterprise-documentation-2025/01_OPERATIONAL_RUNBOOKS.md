# Operational Runbooks - 24/7 MEV Infrastructure Operations
**Version 3.6.5 | July 2025**

## Table of Contents
1. [Daily Operational Checklist](#daily-operational-checklist)
2. [MEV Opportunity Monitoring](#mev-opportunity-monitoring)
3. [Performance Optimization Workflows](#performance-optimization-workflows)
4. [System Health Verification](#system-health-verification)
5. [Emergency Response Procedures](#emergency-response-procedures)
6. [Shift Handover Documentation](#shift-handover-documentation)

---

## Daily Operational Checklist

### Morning Shift (06:00 - 14:00 UTC)

#### 06:00 - System Health Check
```bash
# 1. Check overall system status
cd /data/blockchain/nodes
./scripts/quick-status.sh

# 2. Verify node sync status
./scripts/check-node-status.sh

# 3. Check MEV system health
./scripts/mev-health-check.sh

# 4. Review overnight alerts
tail -n 1000 /data/blockchain/nodes/logs/system-alerts.log | grep "CRITICAL\|ERROR"
```

#### 06:30 - Performance Verification
```bash
# 1. Check latency metrics
curl -s http://localhost:8082/metrics | grep latency

# 2. Verify MEV success rate
curl -s http://localhost:8082/mev/stats | jq '.success_rate'

# 3. Check resource utilization
./monitoring/quick-status.sh
```

#### 07:00 - MEV Opportunity Analysis
```bash
# 1. Review missed opportunities
python3 ./mev/performance_analysis_dashboard.py --missed-opportunities

# 2. Check profit metrics
curl -s http://localhost:8082/mev/profits | jq '.daily_total'

# 3. Analyze strategy performance
sqlite3 /data/blockchain/nodes/logs/mev_strategies.db "SELECT strategy, COUNT(*), SUM(profit_eth) FROM transactions WHERE timestamp > datetime('now', '-24 hours') GROUP BY strategy;"
```

### Afternoon Shift (14:00 - 22:00 UTC)

#### 14:00 - Shift Handover
1. Review morning shift incidents
2. Check pending maintenance tasks
3. Verify all monitoring dashboards active

#### 15:00 - Peak Hour Preparation
```bash
# 1. Optimize resource allocation
python3 ./performance/resource_allocator.py --optimize

# 2. Clear unnecessary logs
./scripts/cleanup-disk-space.sh --safe

# 3. Verify failover systems
python3 ./failover/test-failover.py --quick
```

### Night Shift (22:00 - 06:00 UTC)

#### 22:00 - Maintenance Window Preparation
1. Schedule non-critical updates
2. Prepare backup systems
3. Notify stakeholders of maintenance

#### 00:00 - System Maintenance
```bash
# 1. Database optimization
./scripts/optimize-databases.sh

# 2. Log rotation
logrotate -f /data/blockchain/nodes/logrotate.conf

# 3. Cache cleanup
redis-cli FLUSHDB
```

---

## MEV Opportunity Monitoring

### Real-Time Monitoring Setup

#### 1. Launch Monitoring Dashboard
```bash
cd /data/blockchain/nodes/monitoring
./start-expert-dashboard.sh
```
Access at: http://localhost:8080

#### 2. Configure Alert Thresholds
```yaml
# /data/blockchain/nodes/monitoring/monitor-config.yaml
mev_alerts:
  missed_opportunity_threshold: 0.1 ETH
  low_success_rate: 50%
  high_latency_ms: 15
  gas_spike_multiplier: 2.0
```

### Opportunity Detection Workflow

#### Step 1: Monitor Mempool
```bash
# Watch real-time mempool
watch -n 1 'curl -s http://localhost:8545/eth_mempool | jq ".pending | length"'

# Check high-value transactions
python3 <<EOF
import requests
import json

mempool = requests.post('http://localhost:8545', 
    json={'jsonrpc':'2.0','method':'eth_getBlockByNumber','params':['pending', True],'id':1}
).json()

if 'result' in mempool and mempool['result']:
    txs = mempool['result'].get('transactions', [])
    high_value = [tx for tx in txs if int(tx.get('value', '0x0'), 16) > 10**18]
    print(f"High value transactions: {len(high_value)}")
EOF
```

#### Step 2: Analyze Arbitrage Opportunities
```bash
# Check cross-DEX price differences
curl -s http://localhost:8082/mev/arbitrage/opportunities | jq '.opportunities[] | select(.profit_eth > 0.01)'

# Monitor flash loan opportunities
curl -s http://localhost:8082/mev/flashloan/monitor
```

#### Step 3: Execute MEV Strategies
```bash
# Enable auto-execution for profitable opportunities
curl -X POST http://localhost:8082/mev/config \
  -H "Content-Type: application/json" \
  -d '{
    "auto_execute": true,
    "min_profit_eth": 0.01,
    "max_gas_price_gwei": 200,
    "strategies": ["arbitrage", "sandwich", "liquidation"]
  }'
```

---

## Performance Optimization Workflows

### Latency Optimization Procedure

#### 1. Identify Latency Sources
```bash
# Network latency check
./performance/network_latency_optimizer.py --analyze

# RPC endpoint latency
for endpoint in eth arb op base polygon; do
  echo "Testing $endpoint..."
  curl -w "Total time: %{time_total}s\n" -o /dev/null -s http://localhost:854${endpoint: -1}/
done
```

#### 2. Apply Optimizations
```bash
# Optimize kernel parameters
sudo ./performance/mev_performance_optimizer.py --apply-kernel

# Update network routing
sudo ./performance/network_latency_optimizer.py --optimize-routes

# Restart affected services
systemctl restart erigon-mev mev-boost
```

### Resource Allocation Optimization

#### 1. Current Resource Analysis
```bash
# Check current allocation
./performance/resource_allocator.py --status

# Identify bottlenecks
htop -d 10
iotop -o
```

#### 2. Dynamic Reallocation
```bash
# Reallocate based on MEV activity
python3 ./performance/resource_allocator.py --dynamic \
  --priority ethereum=high,arbitrum=medium,base=medium

# Monitor impact
watch -n 5 './performance/realtime_monitor.py --summary'
```

---

## System Health Verification

### Comprehensive Health Check Protocol

#### 1. Node Health Verification
```bash
# Check all node statuses
for node in ethereum arbitrum optimism base polygon; do
  echo "=== $node ==="
  curl -s http://localhost:854X/ -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq
done
```

#### 2. MEV System Health
```bash
# Check MEV boost status
curl -s http://localhost:18550/eth/v1/builder/status

# Verify MEV relay connections
curl -s http://localhost:8082/mev/relays/status

# Check strategy engine health
systemctl status mev-infra mev-artemis
```

#### 3. Infrastructure Health
```bash
# Database health
psql -U mev_user -d mev_db -c "SELECT pg_database_size('mev_db');"

# Redis health
redis-cli ping
redis-cli info stats | grep instantaneous_ops_per_sec

# Disk space
df -h | grep -E "/$|/data"
```

### Automated Health Monitoring

```bash
# Setup continuous monitoring
cat > /tmp/health_monitor.sh << 'EOF'
#!/bin/bash
while true; do
  # Check critical services
  for service in erigon-mev mev-boost mev-infra mev-artemis; do
    if ! systemctl is-active --quiet $service; then
      echo "ALERT: $service is down!" | mail -s "MEV System Alert" ops@company.com
      systemctl restart $service
    fi
  done
  
  # Check disk space
  if [ $(df /data | tail -1 | awk '{print $5}' | sed 's/%//') -gt 85 ]; then
    ./scripts/emergency-disk-cleanup.sh
  fi
  
  sleep 60
done
EOF

chmod +x /tmp/health_monitor.sh
nohup /tmp/health_monitor.sh &
```

---

## Emergency Response Procedures

### Critical Incident Response Matrix

| Incident Type | Severity | Response Time | Action |
|--------------|----------|---------------|---------|
| Node Crash | CRITICAL | < 2 min | Execute failover |
| MEV Engine Failure | CRITICAL | < 5 min | Restart with fallback |
| Network Attack | CRITICAL | Immediate | Enable DDoS protection |
| Database Corruption | HIGH | < 15 min | Restore from backup |
| High Latency | MEDIUM | < 30 min | Optimize routes |

### Emergency Procedures

#### 1. Node Failure Recovery
```bash
# Immediate response
./scripts/emergency-node-recovery.sh [node_name]

# If primary recovery fails
systemctl stop [node_name]
./scripts/restore-from-snapshot.sh [node_name]
systemctl start [node_name]
```

#### 2. MEV System Failure
```bash
# Stop all MEV services
systemctl stop mev-infra mev-artemis mev-boost

# Clear corrupted state
rm -rf /data/blockchain/mev/state/*

# Restart with safe mode
MEV_SAFE_MODE=true ./mev/deploy-production-mev.sh
```

#### 3. Security Incident Response
```bash
# Enable emergency firewall rules
sudo ./security/emergency-lockdown.sh

# Rotate all credentials
./security/rotate_all_secrets.sh

# Enable enhanced monitoring
./security/security_monitoring.py --enhanced
```

### Disaster Recovery Procedures

#### 1. Complete System Recovery
```bash
# From backup server
rsync -avz backup:/data/blockchain/backups/latest/ /data/blockchain/

# Verify data integrity
./scripts/verify-backup-integrity.sh

# Restart all services
./scripts/start-all-nodes.sh
```

#### 2. Data Recovery
```bash
# Database recovery
pg_restore -U postgres -d mev_db /backups/mev_db_latest.sql

# Blockchain data recovery
for chain in ethereum arbitrum optimism base polygon; do
  ./scripts/restore-chain-data.sh $chain
done
```

---

## Shift Handover Documentation

### Shift Handover Checklist

#### Outgoing Shift Responsibilities
1. **Document all incidents** in shift log
2. **Update status board** with current issues
3. **Brief incoming shift** on:
   - Active incidents
   - Pending maintenance
   - Performance anomalies
   - MEV opportunities status

#### Shift Log Template
```markdown
# Shift Log - [DATE] [SHIFT]

## Shift Summary
- Start Time: [TIME]
- End Time: [TIME]
- Operator: [NAME]

## System Status
- Overall Health: [GREEN/YELLOW/RED]
- Node Sync Status: [STATUS]
- MEV Performance: [X]% success rate
- Daily Profit: [X] ETH

## Incidents
### Incident 1
- Time: [TIME]
- Description: [DESCRIPTION]
- Action Taken: [ACTION]
- Status: [RESOLVED/ONGOING]

## Pending Items
- [ ] [TASK 1]
- [ ] [TASK 2]

## Notes for Next Shift
[NOTES]
```

### Handover Communication Protocol

#### 1. Status Update Meeting (10 minutes)
- Review dashboard together
- Discuss active issues
- Confirm understanding of pending tasks

#### 2. Documentation Update
```bash
# Update shift log
vim /data/blockchain/nodes/logs/shift-logs/$(date +%Y%m%d)_shift.md

# Update status dashboard
curl -X POST http://localhost:8080/api/shift/handover \
  -H "Content-Type: application/json" \
  -d '{
    "outgoing_operator": "NAME",
    "incoming_operator": "NAME",
    "status": "GREEN",
    "notes": "..."
  }'
```

#### 3. Access Verification
```bash
# Verify incoming operator access
./scripts/verify-operator-access.sh [operator_id]

# Transfer active sessions
screen -ls
tmux ls
```

---

## Appendix: Quick Reference Commands

### Most Used Commands
```bash
# System status
./scripts/quick-status.sh

# MEV performance
curl -s http://localhost:8082/mev/stats | jq

# Node health
./scripts/check-node-status.sh

# Resource usage
htop -d 10

# Logs
tail -f /data/blockchain/nodes/logs/mev-profits.log

# Restart services
systemctl restart erigon-mev mev-boost

# Emergency stop
./scripts/emergency-stop-all.sh
```

### Important URLs
- Main Dashboard: http://localhost:8080
- MEV Dashboard: http://localhost:8082
- Monitoring: http://localhost:8081
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

### Emergency Contacts
- On-Call Engineer: Check PagerDuty
- Security Team: security@company.com
- Infrastructure: infra@company.com

---

**Document Classification**: CONFIDENTIAL - INTERNAL USE ONLY  
**Last Updated**: July 17, 2025  
**Next Review**: August 17, 2025