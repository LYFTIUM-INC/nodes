# Blockchain Node Management Guide
**Version**: 1.0
**Last Updated**: 2025-10-29
**Author**: Infrastructure Team

## 🎯 Overview

This guide provides comprehensive procedures for managing all blockchain nodes in the MEV Foundation Infrastructure. All nodes are running as systemd services with proper resource limits and monitoring.

---

## 📊 Node Status Summary

### ✅ All Nodes Operational

| Node | Service | Status | RPC Port | WS Port | Auth Port | P2P Port |
|------|---------|--------|----------|---------|-----------|----------|
| **Geth** | `geth.service` | ✅ Running | 8549 | 8550 | 8554 | 30309 |
| **Erigon** | `erigon.service` | ✅ Running | 8545 | 8546 | 8552 | 30303 |
| **Reth** | `reth.service` | ✅ Running | 8551 | 18657 | 8553 | 30308 |
| **Lighthouse** | `lighthouse-beacon.service` | ✅ Running | 5052 | - | - | 9000 |

---

## 🔧 Geth Management Procedures

### Service Information
- **Service Name**: `geth.service`
- **Data Directory**: `/data/blockchain/storage/geth`
- **User**: `lyftium`
- **JWT Secret**: `/data/blockchain/storage/jwt-secret-common.hex`

### Common Operations

#### Start/Stop/Restart
```bash
# Start Geth
sudo systemctl start geth.service

# Stop Geth
sudo systemctl stop geth.service

# Restart Geth
sudo systemctl restart geth.service

# Check status
sudo systemctl status geth.service
```

#### View Logs
```bash
# View recent logs
sudo journalctl -u geth.service -n 100 --no-pager

# Follow logs in real-time
sudo journalctl -u geth.service -f

# View logs from specific time
sudo journalctl -u geth.service --since "1 hour ago"
```

#### Check Sync Status
```bash
# Using geth attach
geth attach /data/blockchain/storage/geth/geth.ipc --exec "eth.syncing"

# Check peer count
geth attach /data/blockchain/storage/geth/geth.ipc --exec "net.peerCount"

# Check current block
geth attach /data/blockchain/storage/geth/geth.ipc --exec "eth.blockNumber"
```

### Troubleshooting

#### Permission Issues
```bash
# If you see "permission denied" errors on LOCK file:
sudo chown -R lyftium:lyftium /data/blockchain/storage/geth/
sudo chmod -R 755 /data/blockchain/storage/geth/
```

#### Port Conflicts
```bash
# Check if ports are in use
sudo netstat -tlnp | grep -E "8549|8550|8554|30309"

# Kill process using a port (if needed)
sudo lsof -ti:8549 | xargs kill -9
```

---

## 🔧 Erigon Management Procedures

### Service Information
- **Service Name**: `erigon.service`
- **Data Directory**: `/data/blockchain/storage/erigon`
- **User**: `erigon`
- **Management Script**: `/data/blockchain/nodes/scripts/deployment/manage_erigon.sh`

### Common Operations

#### Using Management Script
```bash
cd /data/blockchain/nodes/scripts/deployment

# Check status
sudo ./manage_erigon.sh status

# Monitor performance
sudo ./manage_erigon.sh monitor

# Run diagnostics
sudo ./manage_erigon.sh diagnostics

# View logs
sudo ./manage_erigon.sh logs
```

#### Manual Service Operations
```bash
# Start Erigon
sudo systemctl start erigon.service

# Stop Erigon
sudo systemctl stop erigon.service

# Restart Erigon
sudo systemctl restart erigon.service

# Check status
sudo systemctl status erigon.service
```

#### Check Sync Status
```bash
# Using curl (requires auth)
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8545

# Check block number
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545
```

### Troubleshooting

#### High Memory Usage
```bash
# Check current memory usage
ps aux | grep erigon | awk '{print $4}' | head -1

# Adjust cache size in config (if needed)
# Edit: /data/blockchain/nodes/erigon/config/erigon.toml
# Reduce: cache.db = "2GB" (from default)
```

#### Slow Sync
```bash
# Check peer count
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8545

# If low peers, check firewall
sudo ufw status | grep 30303
```

---

## 🔧 Reth Management Procedures

### Service Information
- **Service Name**: `reth.service`
- **Data Directory**: `/data/blockchain/nodes/reth/data`
- **User**: `lyftium`
- **Config File**: `/data/blockchain/nodes/reth/config/reth-simple.toml`

### Common Operations

#### Start/Stop/Restart
```bash
# Start Reth
sudo systemctl start reth.service

# Stop Reth
sudo systemctl stop reth.service

# Restart Reth
sudo systemctl restart reth.service

# Check status
sudo systemctl status reth.service
```

#### View Logs
```bash
# View recent logs
sudo journalctl -u reth.service -n 100 --no-pager

# Follow logs in real-time
sudo journalctl -u reth.service -f
```

#### Configuration Changes
```bash
# After modifying /data/blockchain/nodes/reth/config/reth-simple.toml
sudo systemctl daemon-reload
sudo systemctl restart reth.service
```

### Troubleshooting

#### Port Conflicts
```bash
# Check if port 30308 is available
sudo netstat -tlnp | grep 30308

# If conflicting, update service file:
# /etc/systemd/system/reth.service
# Add --port flag to ExecStart line
```

#### Database Issues
```bash
# Check database integrity
ls -lh /data/blockchain/nodes/reth/data/db/

# Clear corrupted database (CAUTION: full resync required)
sudo systemctl stop reth.service
sudo rm -rf /data/blockchain/nodes/reth/data/db/*
sudo systemctl start reth.service
```

---

## 🔧 Lighthouse Management Procedures

### Service Information
- **Service Name**: `lighthouse-beacon.service`
- **Data Directory**: `/data/blockchain/nodes/consensus/lighthouse`
- **User**: `lyftium`
- **JWT Secret**: `/data/blockchain/storage/jwt-common/jwt-secret.hex`

### Common Operations

#### Start/Stop/Restart
```bash
# Start Lighthouse
sudo systemctl start lighthouse-beacon.service

# Stop Lighthouse
sudo systemctl stop lighthouse-beacon.service

# Restart Lighthouse
sudo systemctl restart lighthouse-beacon.service

# Check status
sudo systemctl status lighthouse-beacon.service
```

#### View Logs
```bash
# System logs
sudo journalctl -u lighthouse-beacon.service -n 100 --no-pager

# Application logs
tail -f /data/blockchain/nodes/consensus/lighthouse/beacon/logs/beacon.log
```

#### Check Sync Status
```bash
# Using lighthouse API
curl -s http://127.0.0.1:5052/eth/v1/node/syncing | jq

# Check peers
curl -s http://127.0.0.1:5052/eth/v1/node/peer_count | jq
```

### Troubleshooting

#### Database Lock Issues
```bash
# If you see "Resource temporarily unavailable" on LOCK file:

# Find process holding the lock
sudo lsof /data/blockchain/nodes/consensus/lighthouse/beacon/blobs_db/LOCK

# Kill the orphan process
sudo kill -9 <PID>

# Restart service
sudo systemctl restart lighthouse-beacon.service
```

#### Sync Issues
```bash
# Check if execution endpoint is responding
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8552
```

---

## 🚨 Emergency Procedures

### All Nodes Down
```bash
# Start nodes in correct sequence
sudo systemctl start erigon.service
sleep 10
sudo systemctl start geth.service
sleep 10
sudo systemctl start lighthouse-beacon.service
sleep 10
sudo systemctl start reth.service

# Verify all services
sudo systemctl status geth.service lighthouse-beacon.service reth.service erigon.service
```

### Critical Disk Space
```bash
# Check disk usage
df -h /data/blockchain/

# Clean up old logs (if needed)
sudo journalctl --vacuum-time=7d

# Prune old Erigon data (CAUTION)
# See Erigon pruning documentation
```

### Network Connectivity Issues
```bash
# Check peer connections for all nodes
sudo netstat -an | grep ESTABLISHED | grep -E "30303|30308|30309|9000"

# Check firewall rules
sudo ufw status

# Test external connectivity
ping -c 3 8.8.8.8
```

---

## 📊 Monitoring & Health Checks

### Quick Health Check Script
```bash
#!/bin/bash
# Save as: /data/blockchain/nodes/scripts/health-check.sh

echo "=== Blockchain Nodes Health Check ==="
echo ""

# Check services
for service in geth erigon reth lighthouse-beacon; do
    if systemctl is-active --quiet ${service}.service; then
        echo "✅ ${service}: Running"
    else
        echo "❌ ${service}: NOT Running"
    fi
done

echo ""
echo "=== Port Status ==="
netstat -tlnp | grep -E "geth|erigon|reth|lighthouse" | awk '{print $4 " - " $7}'

echo ""
echo "=== Resource Usage ==="
ps aux | grep -E "geth|erigon|reth|lighthouse" | grep -v grep | awk '{print $11 " - CPU: " $3 "% MEM: " $4 "%"}'
```

### Automated Monitoring
```bash
# Enable monitoring timer (if configured)
sudo systemctl enable blockchain-node-monitoring.timer
sudo systemctl start blockchain-node-monitoring.timer
```

---

## 🔐 Security Best Practices

1. **JWT Secrets**: Never expose JWT secret files
   - Location: `/data/blockchain/storage/jwt-secret-common.hex`
   - Permissions: `600` (owner read/write only)

2. **RPC Endpoints**: Keep on localhost only
   - All RPC ports bound to `127.0.0.1`
   - Use reverse proxy (nginx) for external access

3. **Firewall Rules**: Only expose P2P ports
   - Allow: 30303, 30308, 30309, 9000, 5052
   - Block: All RPC/WS ports from external

4. **Regular Updates**: Keep nodes updated
   ```bash
   # Check versions
   geth version
   erigon --version
   reth --version
   lighthouse --version
   ```

---

## 📚 Additional Resources

- **Geth Documentation**: https://geth.ethereum.org/docs
- **Erigon Documentation**: https://github.com/ledgerwatch/erigon
- **Reth Documentation**: https://paradigmxyz.github.io/reth/
- **Lighthouse Documentation**: https://lighthouse-book.sigmaprime.io/

- **Management Scripts**: `/data/blockchain/nodes/scripts/deployment/`
- **Monitoring Scripts**: `/data/blockchain/nodes/scripts/monitoring/`
- **Logs Directory**: `/var/log/` and individual node data directories

---

**End of Document**
