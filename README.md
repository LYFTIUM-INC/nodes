# MEV Foundation Infrastructure

## 📋 Overview

Production-grade MEV (Maximum Extractable Value) Foundation infrastructure featuring:
- **Execution Layer**: Reth (Rust Ethereum client)
- **Consensus Layer**: Lighthouse (PoS consensus client)  
- **MEV Stack**: MEV-Boost + RBuilder for maximum value extraction
- **Network**: Isolated Docker network with enterprise security

## 🏗️ Architecture

```
mev_foundation_network (Docker bridge)
├── reth-ethereum-mev      # RETH Execution Client
├── lighthouse-mev-foundation  # Lighthouse Consensus
├── mev-boost-foundation     # MEV Relay System
├── rbuilder-foundation     # Block Builder Engine
└── grafana-mev-foundation # Monitoring
```

## 📊 Service Status

| Service | Status | Port | Health Check |
|---------|--------|------|-------------|
| RETH | ✅ Operational | 28545 | `curl -s http://localhost:28545` |
| Lighthouse | ✅ Operational | 5052 | `curl -s http://localhost:5052/eth/v1/beacon/genesis` |
| MEV-Boost | ✅ Operational | 28550 | `curl -s http://localhost:28550/eth/v1/builder/status` |
| RBuilder | ✅ Operational | 18552 | `curl -s http://localhost:18552/api/status` |

## 🚀 Quick Start

### Health Check
```bash
# Check all services
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Test API connectivity
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:28545

# Test MEV status
curl -s http://localhost:28550/eth/v1/builder/status
```

### Monitoring
```bash
# Grafana dashboards
# Access via: http://localhost:3000 (if configured)

# System health
cd /data/blockchain/nodes/scripts/monitoring
./comprehensive-health-check.sh
```

## 📁 Directory Structure

```
/data/blockchain/nodes/
├── configs/              # Centralized configurations
│   ├── jwt/              # JWT secrets
│   ├── reth/             # RETH configs
│   ├── lighthouse/        # Lighthouse configs
│   ├── mev-boost/         # MEV-Boost configs
│   └── rbuilder/          # RBuilder configs
├── scripts/               # Organized scripts
│   ├── deployment/        # Deployment scripts
│   ├── monitoring/       # Health check scripts
│   ├── maintenance/      # Maintenance scripts
│   ├── testing/          # Test scripts
│   └── utils/           # Utility scripts
├── docs/                  # Documentation
│   ├── 00-README.md      # Main overview
│   ├── 01-README.md      # Quick start guide
│   ├── 02-ARCHITECTURE.md # System architecture
│   └── ORGANIZATION_STRUCTURE.md # Folder structure
├── environments/             # Environment configs
│   ├── dev/              # Development
│   ├── staging/           # Staging
│   └── prod/              # Production
├── infrastructure/          # Infrastructure components
│   ├── docker/           # Docker configurations
│   ├── systemd/          # Systemd services
│   └── monitoring/       # Monitoring configs
├── maintenance/             # Maintenance tools
│   ├── configs/         # Maintenance configs
│   ├── dashboards/      # Monitoring dashboards
│   ├── runbooks/        # Runbooks
│   └── scripts/        # Maintenance scripts
├── security/               # Security configurations
│   ├── secrets/         # Encrypted secrets
│   ├── api_keys/        # API keys
│   ├── certificates/     # SSL certificates
│   └── backups/         # Security backups
├── services/               # Running services
├── monitoring/             # Active monitoring
└── logs/                   # System logs
```

## 🔧 Operations

### Service Management
```bash
# Start all services
cd /data/blockchain/nodes/scripts/deployment
./start-mev-infrastructure.sh

# Stop all services
cd /data/blockchain/nodes/scripts/maintenance
./stop-all-services.sh

# Health monitoring
cd /data/blockchain/nodes/scripts/monitoring
./comprehensive-health-check.sh
```

### Backup Procedures
```bash
# Create backup
cd /data/blockchain/nodes/scripts/maintenance
./create-backup.sh

# Restore from backup
cd /data/blockchain/nodes/scripts/maintenance
./restore-from-backup.sh
```

## 🔒 Security

- JWT-based Engine API authentication
- Docker network isolation
- Encrypted secret management
- Regular security audits
- Access control and monitoring

## 📊 Performance Monitoring

- System resource utilization
- Network latency monitoring
- MEV profit tracking
- Block synchronization status
- Service health metrics

## 📞 Support

- **Documentation**: `/docs/`
- **Status**: Check with `/scripts/monitoring/comprehensive-health-check.sh`
- **Logs**: `/logs/`
- **Alerts**: Grafana dashboards

**Last Updated**: $(date)
**Version**: 2.0.0
**Status**: ✅ Production Ready
