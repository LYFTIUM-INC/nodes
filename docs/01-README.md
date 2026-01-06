# Blockchain Nodes Infrastructure - MEV Operations

## 🚀 Professional MEV Node Management

### Node Status Summary

#### ✅ Erigon Node (Primary MEV Engine)
- **Status**: 🟢 Active and Syncing (99.1% complete)
- **Current Block**: 23,453,143 / 23,473,567
- **RPC Endpoint**: `http://127.0.0.1:8545`
- **WebSocket**: `ws://127.0.0.1:8546`
- **Peers**: 13 active connections
- **Memory**: 13.9GB / 16GB allocated
- **Performance**: 1.8 blocks/sec, 359 tx/sec

#### ✅ Geth Node (Secondary Validation)
- **Status**: 🟢 Active and Fully Synced
- **Current Block**: 5,007,542 (100% synced)
- **RPC Endpoint**: `http://127.0.0.1:8549`
- **WebSocket**: `ws://127.0.0.1:8550`
- **Auth RPC**: `http://127.0.0.1:8554`
- **Peers**: 60 active connections
- **Memory**: 1.3GB / 10GB allocated

### 📡 MEV Data Extraction Capabilities

#### RPC APIs Available
- **Core APIs**: `eth, net, web3, debug, txpool`
- **Erigon Enhanced**: `erigon` (proprietary MEV APIs)
- **Real-time Data**: WebSocket streams for mempool monitoring
- **Historical Analysis**: Full blockchain state access

#### Network Configuration
- **External IP**: 51.159.82.58
- **P2P Ports**: Erigon (30303), Geth (30312)
- **Bootnodes**: Optimized for fast peer discovery
- **Rate Limiting**: MEV-optimized for high-frequency requests

### 🏗️ Professional Directory Structure

```
/data/blockchain/nodes/
├── ethereum/
│   ├── erigon/              # Erigon configurations and data links
│   └── geth/                # Geth configurations and data links
├── ethereum-clients/         # Client binaries and version management
├── security/                # JWT secrets, SSL certificates
├── monitoring/              # Health checks and performance metrics
├── scripts/                 # Automation and management tools
└── configs/                 # Configuration templates and backups
```

### ⚙️ Service Management

#### Systemd Services Status
```bash
# Check both services
sudo systemctl status erigon.service   # ✅ Active (running)
sudo systemctl status geth.service     # ✅ Active (running)

# Monitor logs
sudo journalctl -u erigon.service -f   # Sync progress logs
sudo journalctl -u geth.service -f     # Geth operational logs
```

#### Resource Allocation
- **Erigon**: 16GB RAM, 4TB storage, 400% CPU quota
- **Geth**: 10GB RAM, optimized for fast sync
- **Network**: High-performance networking with MEV optimization

### 📊 Performance Metrics

#### Sync Progress Monitoring
```bash
# Erigon sync status
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq .

# Geth sync status (should return false = synced)
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8549 | jq .
```

#### Network Health
```bash
# Peer connections
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8545  # Erigon: 13 peers

curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8549  # Geth: 60 peers
```

### 🔒 Security Configuration

#### Authentication
- **JWT Secrets**: Located in `/data/blockchain/storage/jwt-secret-common.hex`
- **RPC Auth**: Auth RPC endpoints enabled on both nodes
- **IP Restrictions**: Localhost access with secure proxy configuration
- **SSL/TLS**: Configured for external access through VPN

#### Access Control
- **Services**: Security-hardened systemd configurations
- **File Permissions**: Restricted access to sensitive data
- **Network**: Firewall rules for all P2P and RPC ports
- **Monitoring**: Comprehensive audit logging

### 📈 MEV Operations Support

#### Real-time Data Extraction
```bash
# WebSocket subscription to new blocks
wscat -c ws://127.0.0.1:8546 -x '{
  "jsonrpc":"2.0","id":1,
  "method":"eth_subscribe",
  "params":["newHeads"]
}'

# Mempool monitoring
wscat -c ws://127.0.0.1:8546 -x '{
  "jsonrpc":"2.0","id":1,
  "method":"eth_subscribe",
  "params":["pendingTransactions"]
}'
```

#### Transaction Pool Analysis
```bash
# Get pending transactions
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' \
  http://127.0.0.1:8545

# Get transaction pool content
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"txpool_content","params":[],"id":1}' \
  http://127.0.0.1:8545
```

### 🛠️ Management Commands

#### Quick Health Check
```bash
# Comprehensive status
./scripts/quick-status.sh

# MEV-specific health check
./mev-health-check.sh

# Service resource usage
./scripts/memory-monitor-blockchain.sh
```

#### Performance Optimization
```bash
# Resource optimization
./scripts/maintenance/optimize-erigon.sh

# Memory management
./scripts/utilities/auto_memory_manager.sh

# Performance monitoring
./scripts/monitoring/performance-dashboard-optimized.py
```

### 🚨 Troubleshooting

#### Common Issues & Solutions

**RPC Timeout Issues**
```bash
# Check service health
sudo systemctl status erigon geth

# Verify port accessibility
sudo netstat -tlnp | grep -E "(8545|8546|8549|8550)"

# Test local connectivity
curl -m 5 http://127.0.0.1:8545
```

**Sync Performance**
```bash
# Monitor sync progress
sudo journalctl -u erigon -f | grep "blk="

# Check peer connectivity
curl -s http://127.0.0.1:8545 -X POST \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Resource utilization
htop | grep -E "(erigon|geth)"
```

### 📞 Operational Support

#### Monitoring & Alerts
- **System Metrics**: Resource usage, disk I/O, network traffic
- **Node Health**: Sync progress, peer connectivity, API response times
- **MEV Opportunities**: Real-time monitoring dashboards
- **Security Events**: Access logging, authentication failures

#### Maintenance Schedule
- **Daily**: Health checks, log rotation, performance monitoring
- **Weekly**: Resource optimization, security updates, backup verification
- **Monthly**: Capacity planning, performance tuning, security audits

---

**Status**: 🟢 OPERATIONAL - Ready for MEV Operations
**Last Updated**: 2025-10-16 17:10 PDT
**Next Maintenance**: Scheduled check at 02:00 UTC

---

**🚀 MEV Infrastructure is fully operational and ready for high-frequency trading operations!**