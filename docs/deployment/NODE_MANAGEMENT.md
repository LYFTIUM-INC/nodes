# Node Management Runbook

## Overview
Comprehensive procedures for managing blockchain nodes in the data lab environment.

## Service Status Monitoring

### Quick Status Check
```bash
# All services overview
./scripts/monitoring/quick-status.sh

# Individual service checks
systemctl status erigon
systemctl status geth
systemctl status lighthouse
systemctl status mev-boost
```

### Detailed Health Check
```bash
# Comprehensive node analysis
./node_admin_overview.py

# Generate status report
python3 /data/blockchain/nodes/node_admin_overview.py --output /tmp/node_status.json
cat /tmp/node_status.json
```

## Service Management

### Start/Stop Procedures

#### Individual Services
```bash
# Start services (order matters for dependencies)
sudo systemctl start lighthouse          # Beacon chain first
sudo systemctl start erigon             # Primary Ethereum node
sudo systemctl start geth               # Backup Ethereum node
sudo systemctl start mev-boost          # MEV infrastructure

# Stop services
sudo systemctl stop geth
sudo systemctl stop erigon
sudo systemctl stop lighthouse
sudo systemctl stop mev-boost
```

#### Bulk Operations
```bash
# Start all blockchain services
sudo systemctl start lighthouse erigon geth mev-boost

# Stop all blockchain services
sudo systemctl stop geth erigon lighthouse mev-boost

# Restart all services
sudo systemctl restart lighthouse erigon geth mev-boost
```

### Service Configuration Updates
```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Apply updated service configuration
sudo systemctl restart [service-name]

# Verify configuration changes
sudo systemctl status [service-name] --no-pager
```

## Sync Management

### Monitor Sync Progress
```bash
# Real-time sync monitoring
./geth_sync_monitor.sh

# Layer 2 sync monitoring
./scripts/monitoring/monitor_l2_sync.sh

# Quick sync check
./quick_sync_check.py
```

### Sync Troubleshooting
```bash
# Comprehensive sync verification
./verify_blockchain_sync.sh

# Advanced sync diagnostics
./blockchain_sync_verification_comprehensive.py

# Chain integrity verification
./chain_integrity_verifier.py
```

## Performance Optimization

### Resource Monitoring
```bash
# Performance guardian
./scripts/monitoring/performance-guardian.sh

# Resource usage dashboard
./scripts/monitoring/resource-dashboard.sh

# Memory optimization
./scripts/maintenance/memory-optimization.sh

# CPU optimization
./performance/cpu_optimizer.py
```

### Sync Optimization
```bash
# Optimize sync performance
./scripts/monitoring/optimize-erigon.sh

# Monitor sync optimization
./run_optimization_monitoring.sh
```

## Log Management

### Access Logs
```bash
# Systemd logs
sudo journalctl -u erigon -f
sudo journalctl -u geth -f
sudo journalctl -u lighthouse -f

# Application logs
tail -f /data/blockchain/nodes/data/logs/erigon.log
tail -f /data/blockchain/nodes/data/logs/geth.log
tail -f /data/blockchain/nodes/data/logs/lighthouse.log

# MEV logs
tail -f /data/blockchain/nodes/data/logs/mev.log
```

### Log Analysis
```bash
# Error log analysis
./scripts/maintenance/analyze-error-logs.sh

# Performance log analysis
./performance/realtime_monitor.py --analyze

# Sync log analysis
./scripts/monitoring/analyze-sync-logs.sh
```

## Backup Procedures

### Data Backup
```bash
# Automated backup
./scripts/maintenance/create-data-backup.sh

# Manual backup
sudo systemctl stop erigon
rsync -av /data/blockchain/storage/erigon/ /data/blockchain/nodes/data/backups/erigon_$(date +%Y%m%d)
sudo systemctl start erigon
```

### Configuration Backup
```bash
# Backup all configurations
tar -czf /data/blockchain/nodes/data/backups/config_backup_$(date +%Y%m%d).tar.gz /data/blockchain/nodes/config/

# Backup service files
tar -czf /data/blockchain/nodes/data/backups/services_backup_$(date +%Y%m%d).tar.gz /data/blockchain/nodes/infrastructure/systemd/
```

### Recovery Procedures
```bash
# Data integrity verification
./scripts/disaster-recovery/verify-data-integrity.sh

# Restore from backup
./scripts/disaster-recovery/restore-from-backup.sh

# Full service recovery
./scripts/disaster-recovery/emergency-recovery.sh
```

## Troubleshooting

### Common Issues

#### Service Won't Start
1. **Check Configuration**
   ```bash
   sudo systemctl status [service-name] --no-pager
   sudo journalctl -u [service-name] --no-pager
   ```

2. **Check Resources**
   ```bash
   df -h /data/blockchain/storage/
   free -h
   ps aux | grep [service-name]
   ```

3. **Check Permissions**
   ```bash
   ls -la /data/blockchain/storage/[service]/
   chown -R blockchain: blockchain /data/blockchain/storage/[service]/
   ```

4. **Clear Locks**
   ```bash
   sudo rm -f /data/blockchain/storage/[service]/LOCK
   sudo rm -f /data/blockchain/storage/[service]/erigon.lock
   ```

#### RPC Connectivity Issues
1. **Verify Service Status**
   ```bash
   systemctl status [service-name]
   netstat -tlnp | grep [port]
   ```

2. **Test Locally**
   ```bash
   curl -X POST -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
     http://127.0.0.1:[port]
   ```

3. **Check Firewall**
   ```bash
   sudo ufw status
   sudo iptables -L -n | grep [port]
   ```

#### High Resource Usage
1. **Identify Process**
   ```bash
   ps aux | grep [service-name] | sort -k4 -nr
   top -p $(pgrep [service-name] | head -1)
   ```

2. **Resource Limits**
   ```bash
   systemctl show [service-name] | grep -i limit
   cat /proc/$(pgrep [service-name] | head -1)/limits
   ```

3. **Optimization**
   ```bash
   # Increase memory limits
   sudo systemctl edit [service-name]
   # Add: MemoryMax=16G
   ```

### Performance Issues

#### Slow Sync
1. **Check Peer Connectivity**
   ```bash
   curl -s http://127.0.0.1:8545 -X POST \
     -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq
   ```

2. **Monitor Bandwidth**
   ```bash
   iftop -t
   nload
   ```

3. **Disk I/O Analysis**
   ```bash
   iotop -o
   iostat -x 1 5
   ```

#### High CPU Usage
1. **Identify Cause**
   ```bash
   top -p $(pgrep [service-name] | head -1)
   perf top -p $(pgrep [service-name] | head -1)
   ```

2. **Reduce Load**
   ```bash
   # Reduce max peers
   sudo systemctl edit [service-name]
   # Add: --maxpeers=50
   ```

## Emergency Procedures

### Service Recovery
```bash
# Immediate recovery
./scripts/maintenance/emergency-recovery.sh [service-name]

# Full recovery
./scripts/maintenance/factory-reset.sh [service-name]
```

### Data Corruption
```bash
# Stop all services
sudo systemctl stop erigon geth lighthouse

# Verify data integrity
./scripts/disaster-recovery/verify-data-integrity.sh

# Re-initialize if necessary
./scripts/disaster-recovery/reinitialize-node.sh
```

### Network Issues
```bash
# Check network connectivity
ping 8.8.8.8
traceroute 8.8.8.8

# Check DNS resolution
nslookup eth-us-east1.alchemyapi.io

# Test external connectivity
curl -I https://eth-us-east1.alchemyapi.io/v2/eth_blockNumber
```

## Maintenance Schedule

### Daily Tasks
- [ ] Check service status
- [ ] Monitor resource usage
- [ ] Review error logs
- [ ] Verify backup completion

### Weekly Tasks
- [ ] Performance analysis
- [ ] Update configurations
- [ ] Clean up old logs
- [ ] Security audit

### Monthly Tasks
- [ ] Full system backup
- [ ] Performance benchmarking
- [ ] Infrastructure review
- [ ] Documentation update

## Contact Information

### Support Escalation
- **Critical Issues**: Page on-call administrator
- **Performance Issues**: Contact network engineer
- **MEV Issues**: Contact MEV specialist

### Documentation Updates
- Architecture changes: Update `/docs/architecture/`
- Procedure changes: Update this runbook
- Service updates: Update `/docs/deployment/`