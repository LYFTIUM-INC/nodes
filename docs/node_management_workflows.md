# 🔗 Blockchain Node Lab Management Workflows

## 📋 Executive Summary

Your blockchain node lab currently runs **3 Ethereum client instances** with mixed operational status. This workflow guide provides comprehensive command patterns for node management, monitoring, and troubleshooting.

### Current Node Inventory:
- ✅ **Geth**: Active (Port 8549, 20h uptime, needs sync)
- ⚠️ **Reth**: Active (Port 8551, JWT auth required, sync status unknown)
- ❌ **Erigon**: Inactive (Service not running)

---

## 🚀 Quick Start Commands

### Immediate Status Check:
```bash
# Run comprehensive node status
python /data/blockchain/nodes/blockchain_node_monitor.py --node all

# Watch mode (continuous monitoring)
python /data/blockchain/nodes/blockchain_node_monitor.py --watch --interval 30

# Check specific node
python /data/blockchain/nodes/blockchain_node_monitor.py --node geth
```

### Service Management:
```bash
# Check all blockchain services
systemctl status geth reth erigon --no-pager

# Restart services as needed
sudo systemctl restart geth
sudo systemctl restart reth
sudo systemctl start erigon

# Enable services on boot
sudo systemctl enable geth reth erigon
```

---

## 🔍 Node Status Monitoring

### 1. Real-time Status Dashboard
**Command**: `python /data/blockchain/nodes/blockchain_node_monitor.py --watch`

**Features**:
- Live monitoring of all nodes
- Health scoring (0-100%)
- Sync progress tracking
- Peer count monitoring
- Resource usage (CPU/Memory)
- RPC availability checks

### 2. Quick Health Checks
```bash
# Service status
systemctl is-active geth reth erigon

# Network ports
netstat -tlnp | grep -E "(8545|8549|8551|30303|30312)"

# Block numbers
curl -s http://127.0.0.1:8549 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Peer connectivity
curl -s http://127.0.0.1:8549 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

### 3. Detailed Sync Status
```bash
# Geth sync progress
curl -s http://127.0.0.1:8549 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq

# Reth sync with JWT auth
JWT=$(cat /data/blockchain/storage/jwt-secret-common.hex)
curl -s http://127.0.0.1:8551 -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq
```

---

## 🛠️ Node Management Workflows

### Workflow 1: Daily Health Check
**Frequency**: Every 12 hours
**Purpose**: Ensure operational status and identify issues

```bash
#!/bin/bash
# daily_node_check.sh

echo "🔗 Daily Blockchain Node Health Check"
echo "======================================"
date

# Run comprehensive check
python /data/blockchain/nodes/blockchain_node_monitor.py --node all

# Check disk space
echo -e "\n💾 Disk Usage:"
df -h /data/blockchain/storage/
du -sh /data/blockchain/nodes/

# Check logs for errors
echo -e "\n📋 Recent Errors:"
journalctl -u geth --since "12 hours ago" | grep -i error | tail -5
journalctl -u reth --since "12 hours ago" | grep -i error | tail -5

# System resources
echo -e "\n💻 System Resources:"
free -h
iostat -x 1 1 | grep -E "(Device|sda|sdb|nvme)"
```

### Workflow 2: Sync Recovery
**Trigger**: Node not synced or falling behind
**Purpose**: Restore sync progress

```bash
#!/bin/bash
# sync_recovery.sh

NODE=${1:-geth}
echo "🔄 Sync Recovery for $NODE"

# Stop service
sudo systemctl stop $NODE

# Check for corrupted data
echo "🔍 Checking data integrity..."
if [ "$NODE" = "geth" ]; then
    /usr/bin/geth removedb --datadir /data/blockchain/storage/geth-backup
fi

# Restart service
sudo systemctl start $NODE

# Monitor progress
watch -n 10 "python /data/blockchain/nodes/blockchain_node_monitor.py --node $NODE"
```

### Workflow 3: JWT Authentication Setup
**Purpose**: Enable authenticated RPC access

```bash
#!/bin/bash
# setup_jwt_auth.sh

echo "🔐 Setting up JWT Authentication"

# Check JWT secrets
JWT_FILES=(
    "/data/blockchain/storage/jwt-secret-common.hex"
    "/data/blockchain/storage/erigon/jwt.hex"
)

for jwt_file in "${JWT_FILES[@]}"; do
    if [[ -f "$jwt_file" ]]; then
        echo "✅ JWT found: $jwt_file"
        echo "Secret: $(cat $jwt_file)"
    else
        echo "❌ JWT missing: $jwt_file"
        echo "Generating new JWT secret..."
        openssl rand -hex 32 > "$jwt_file"
        chmod 600 "$jwt_file"
    fi
done

# Test Reth with JWT
JWT=$(cat /data/blockchain/storage/erigon/jwt.hex)
curl -s http://127.0.0.1:8551 -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Workflow 4: Node Upgrade
**Purpose**: Safe client version upgrades

```bash
#!/bin/bash
# upgrade_node.sh

NODE=${1:-geth}
echo "⬆️  Upgrading $NODE"

# Get current version
echo "📋 Current version:"
if [ "$NODE" = "geth" ]; then
    /usr/bin/geth version
elif [ "$NODE" = "reth" ]; then
    /usr/local/bin/reth --version
fi

# Backup data
echo "💾 Backing up data..."
BACKUP_DIR="/data/blockchain/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ "$NODE" = "geth" ]; then
    cp -r /data/blockchain/storage/geth-backup "$BACKUP_DIR/"
elif [ "$NODE" = "reth" ]; then
    cp -r /data/blockchain/nodes/reth/data "$BACKUP_DIR/reth-data"
fi

# Stop service
sudo systemctl stop $NODE

# Upgrade client (implement specific upgrade steps)
echo "🔄 Upgrade steps here..."

# Start service
sudo systemctl start $NODE

# Verify upgrade
echo "✅ Verifying upgrade..."
sleep 30
python /data/blockchain/nodes/blockchain_node_monitor.py --node $NODE
```

---

## 📊 Monitoring and Alerting

### Prometheus Metrics Setup:
```bash
# Geth metrics
curl http://127.0.0.1:6061/metrics

# Custom node health metrics
cat <<EOF > /tmp/node_health.prom
# HELP node_health Overall node health score
# TYPE node_health gauge
node_health{node="geth"} 0.7
node_health{node="reth"} 0.4
node_health{node="erigon"} 0.0

# HELP node_sync_percentage Sync progress percentage
# TYPE node_sync_percentage gauge
node_sync_percentage{node="geth"} 0
node_sync_percentage{node="reth"} 0
node_sync_percentage{node="erigon"} 100
EOF
```

### Alert Thresholds:
- **Health Score < 50%**: Alert
- **Sync Progress < 95%**: Warning
- **Peer Count < 10**: Warning
- **RPC Unresponsive**: Critical
- **Disk Usage > 80%**: Critical

---

## 🔧 Advanced Configuration

### Multi-Client Load Balancer:
```nginx
upstream eth_nodes {
    server 127.0.0.1:8549;  # Geth
    server 127.0.0.1:8551;  # Reth
    # server 127.0.0.1:8545;  # Erigon (when active)
}

server {
    listen 8080;
    location / {
        proxy_pass http://eth_nodes;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Archive Node Configuration:
```toml
# For Reth archive mode
[pruning]
block-pruning = "disabled"
transaction-pruning = "disabled"
receipt-pruning = "disabled"
```

---

## 🚨 Troubleshooting Guide

### Common Issues and Solutions:

#### 1. Node Not Syncing
**Symptoms**: Block number 0, sync status shows starting phase
**Solutions**:
```bash
# Check consensus layer
curl -s http://127.0.0.1:8554 -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat /data/blockchain/storage/jwt-secret-common.hex)" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Restart with fresh sync
sudo systemctl stop geth
# Consider re-sync with snapshots
sudo systemctl start geth
```

#### 2. RPC Authentication Failed
**Symptoms**: 401 Unauthorized, Authorization header missing
**Solutions**:
```bash
# Verify JWT secret exists
ls -la /data/blockchain/storage/erigon/jwt.hex

# Regenerate JWT secret
openssl rand -hex 32 > /data/blockchain/storage/erigon/jwt.hex
chmod 600 /data/blockchain/storage/erigon/jwt.hex

# Restart service
sudo systemctl restart reth
```

#### 3. Port Conflicts
**Symptoms**: Address already in use, service fails to start
**Solutions**:
```bash
# Find conflicting processes
sudo netstat -tulpn | grep :8545

# Update configuration
sudo nano /data/blockchain/nodes/reth/config/reth-simple.toml

# Restart with new config
sudo systemctl restart reth
```

#### 4. High Memory Usage
**Symptoms**: OOM errors, system slow
**Solutions**:
```bash
# Check memory usage
ps aux | grep -E "(geth|reth)" | sort -k4 -nr

# Tune cache settings
# Add to service file ExecStart:
# --cache=1024 (Geth)
# --db.cache-size=1GB (Reth)
```

---

## 📚 Command Reference

### Essential Commands:
```bash
# Status
python /data/blockchain/nodes/blockchain_node_monitor.py --node all
systemctl status geth reth erigon

# Control
sudo systemctl start|stop|restart geth reth erigon
sudo systemctl enable|disable geth reth erigon

# Monitoring
journalctl -u geth -f
tail -f /var/log/geth.log
htop
iotop

# Network
netstat -tulpn | grep -E "(8545|8551|30303)"
ss -tulpn | grep reth

# RPC calls
curl -s http://127.0.0.1:8549 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### File Locations:
- **Geth Data**: `/data/blockchain/storage/geth-backup/`
- **Reth Data**: `/data/blockchain/nodes/reth/data/`
- **Erigon Data**: `/data/blockchain/storage/erigon/`
- **Configs**: `/etc/systemd/system/`, `/data/blockchain/nodes/reth/config/`
- **JWT Secrets**: `/data/blockchain/storage/*.hex`
- **Logs**: `journalctl -u [service]`, `/var/log/`

---

## 🎯 Best Practices

### Daily Operations:
1. **Health Checks**: Run `blockchain_node_monitor.py` every 12 hours
2. **Log Monitoring**: Check for errors and warnings
3. **Resource Monitoring**: Monitor CPU, memory, disk usage
4. **Backup Verification**: Ensure backup systems working

### Weekly Maintenance:
1. **System Updates**: Apply security patches
2. **Client Updates**: Check for new releases
3. **Storage Cleanup**: Remove old logs and cache
4. **Performance Review**: Analyze sync speeds and resource usage

### Monthly Tasks:
1. **Security Audit**: Review access controls
2. **Capacity Planning**: Check storage growth
3. **Disaster Recovery**: Test backup restore procedures
4. **Documentation Updates**: Update configurations

---

## 🔄 Integration with Existing Tools

This workflow integrates with your existing blockchain infrastructure:

- **MCP Tools**: EVM, ClickHouse, Python Executor
- **Agents**: blockchain-node-admin, blockchain-data-scientist
- **Commands**: /node_status, /manage_erigon, /unified_node_management
- **Hooks**: blockchain_status_check.py

---

*Generated by Blockchain Node Manager - 2025-10-23*
*Last Updated: Real-time node monitoring active*