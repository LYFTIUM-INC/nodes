# MEV Foundation Operational Procedures

## 🔧 Service Management

### Starting Services
```bash
# Start all MEV Foundation services
cd /data/blockchain/nodes/scripts/deployment
./start-mev-infrastructure.sh

# Start individual services
sudo docker start reth-ethereum-mev
sudo docker start lighthouse-mev-foundation
sudo docker start mev-boost-foundation
sudo docker start rbuilder-foundation
```

### Stopping Services
```bash
# Stop all services gracefully
cd /data/blockchain/nodes/scripts/maintenance
./graceful-shutdown.sh

# Force stop if needed (emergency only)
sudo docker stop $(docker ps -q -f)
```

### Service Health Checks
```bash
# Comprehensive health check
cd /data/blockchain/nodes/scripts/monitoring
./comprehensive-health-check.sh

# Individual service checks
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:28545

curl -s -H "Content-Type: application/json" \
  http://localhost:5052/eth/v1/beacon/genesis

curl -s http://localhost:28550/eth/v1/builder/status
curl -s http://localhost:18552/api/status
```

## 🔧 Maintenance Procedures

### Daily Tasks
```bash
# Log rotation
cd /data/blockchain/nodes/scripts/maintenance
./rotate-logs.sh

# Resource monitoring
cd /data/blockchain/nodes/scripts/monitoring
./resource-usage-check.sh

# Security validation
cd /data/blockchain/nodes/security
./security-audit.sh
```

### Weekly Tasks
```bash
# Full backup
cd /data/blockchain/nodes/scripts/maintenance
./create-full-backup.sh

# Performance optimization
cd /data/blockchain/nodes/scripts/maintenance
./performance-tuning.sh

# Configuration review
cd /data/blockchain/nodes/scripts/maintenance
./validate-configs.sh
```

### Monthly Tasks
```bash
# Security patch updates
cd /data/blockchain/nodes/security
./apply-security-updates.sh

# Capacity planning
cd /data/blockchain/nodes/maintenance
./capacity-planning.sh

# Architecture review
cd /data/blockchain/nodes/docs
./architecture-review.sh
```

## 🚨 Emergency Procedures

### Service Recovery
```bash
# Check service status
cd /data/blockchain/nodes/scripts/monitoring
./emergency-status-check.sh

# Restart failed services
cd /data/blockchain/nodes/scripts/maintenance
./restart-failed-services.sh

# Full system recovery
cd /data/blockchain/nodes/scripts/maintenance
./emergency-recovery.sh
```

### Data Recovery
```bash
# Restore from backup
cd /data/blockchain/nodes/scripts/maintenance
./restore-from-backup.sh

# Validate data integrity
cd /data/blockchain/nodes/scripts/monitoring
./data-integrity-check.sh
```

## 📊 Monitoring

### Real-time Monitoring
```bash
# Start monitoring dashboards
cd /data/blockchain/nodes/lib/monitoring
./start-monitoring.sh

# Check system metrics
docker stats --no-stream
```

### Alerting
```bash
# Check alert status
cd /data/blockchain/nodes/security
./check-alerts.sh

# Test notification system
cd /data/blockchain/nodes/scripts/monitoring
./test-alerts.sh
```

## 🔧 Configuration Management

### Environment Variables
```bash
# List all environment variables
env | grep -E "^(MEV|RETH|LIGHTHOUSE)"

# Update configurations
cd /data/blockchain/nodes/configs
./update-configs.sh
```

### Port Management
```bash
# Check port usage
sudo netstat -tulpn | grep -E "(28545|5052|28550|18552)"

# Test port connectivity
nmap -p 28545 localhost
nmap -p 5052 localhost
nmap -p 28550 localhost
nmap -p 18552 localhost
```

## 🔐 Security Procedures

### Access Control
```bash
# Check user permissions
sudo -l /data/blockchain/nodes

# Validate file permissions
cd /data/blockchain/nodes/security
./check-permissions.sh

# Audit API access
cd /data/blockchain/nodes/security
./audit-api-access.sh
```

### Secret Rotation
```bash
# Rotate JWT secrets
cd /data/blockchain/nodes/security
./rotate-jwt-secrets.sh

# Update API keys
cd /data/blockchain/nodes/security
./update-api-keys.sh
```

## 📈 Backup & Recovery

### Automated Backups
```bash
# Schedule daily backups
cd /data/blockchain/nodes/scripts/maintenance
./schedule-daily-backups.sh

# Manual backup
cd /data/blockchain/nodes/scripts/maintenance
./create-manual-backup.sh

# Test backup integrity
cd /data/blockchain/nodes/scripts/maintenance
./verify-backup-integrity.sh
```

### Data Restoration
```bash
# List available backups
cd /data/blockchain/nodes/backups
ls -la

# Select and restore backup
cd /data/blockchain/nodes/scripts/maintenance
./select-and-restore.sh

# Validate restored data
cd /data/blockchain/nodes/scripts/monitoring
./data-integrity-check.sh
```

## 📞 Troubleshooting

### Common Issues
1. **Service Not Starting**
   - Check JWT secret synchronization
   - Verify network connectivity
   - Validate Docker network configuration

2. **Sync Issues**
   - Check peer connections
   - Verify JWT authentication
   - Monitor resource usage

3. **Performance Issues**
   - Check resource allocation
   - Monitor disk I/O
   - Analyze network latency

### Diagnostic Tools
```bash
# System diagnostics
cd /data/blockchain/nodes/scripts/monitoring
./diagnostic-tool.sh

# Network diagnostics
cd /data/blockchain/nodes/scripts/utils
./network-diagnostic.sh

# Service logs analysis
cd /data/blockchain/nodes/logs
./analyze-service-logs.sh
```

## 📊 Reporting

### Daily Status Reports
```bash
# Generate daily status
cd /data/blockchain/nodes/scripts/monitoring
./generate-daily-report.sh
```

### Monthly Performance Reports
```bash
# Generate performance report
cd /data/blockchain/nodes/performance
./monthly-performance-report.sh
```

### Incident Reports
```bash
# Log incidents
cd /data/blockchain/nodes/logs
./log-incident.sh
```

## 🔗 Change Management

### Software Updates
```bash
# Check for updates
cd /data/blockchain/nodes/maintenance
./check-updates.sh

# Apply updates
cd /data/blockchain/nodes/maintenance
./apply-updates.sh

# Validate updates
cd /data/blockchain/nodes/scripts/monitoring
./post-update-validation.sh
```

### Configuration Changes
```bash
# Review configuration changes
cd /data/blockchain/nodes/configs
./review-config-changes.sh

# Apply configuration updates
cd /data/blockchain/nodes/scripts/deployment
./apply-config-changes.sh

# Test configuration changes
cd /data/blockchain/nodes/scripts/monitoring
./test-config-changes.sh
```

## 📞 Training & Documentation

### Team Training
```bash
# Access training materials
cd /data/blockchain/nodes/docs
./training/
```

### Documentation Updates
```bash
# Update operational procedures
cd /data/blockchain/nodes/docs
./update-documentation.sh

# Update runbooks
cd /data/blockchain/nodes/docs
./update-runbooks.sh
```

---

**Document Version**: 2.0.0
**Last Updated**: $(date)
**Maintainer**: MEV Foundation Operations Team
**Status**: ✅ Production Ready
**Review Cycle**: Monthly
**Approval**: Infrastructure Committee
