# LYFTIUM-INC/nodes

> **Production-Grade MEV Infrastructure** - Blockchain node operations, MEV extraction, and real-time analytics platform.

[![Status](https://img.shields.io/badge/status-operational-green)](https://github.com/LYFTIUM-INC/nodes)
[![Infrastructure](https://img.shields.io/badge/infrastructure-ethereum-blue)](https://ethereum.org/)
[![MEV](https://img.shields.io/badge/MEV-boost-purple)](https://github.com/flashbots/mev-boost)
[![Last Updated](https://img.shields.io/badge/last%20updated-2026--03--09-blue)]()

## 🎯 Overview

This repository contains LYFTIUM's **professional MEV (Maximal Extractable Value) infrastructure** for Ethereum mainnet operations. Our platform combines:

- **Execution Layer**: Erigon (PRIMARY for MEV – HTTP 8545, Engine API 8552)
- **Consensus Layer**: Lighthouse beacon nodes (port 5052) with slash protection
- **MEV Pipeline**: MEV-Boost (18551), RBuilder (18552), private mempool, arbitrage engines
- **Real-Time Analytics**: ClickHouse with 22.5B+ blockchain data rows
- **Enterprise Monitoring**: Prometheus, Grafana, AlertManager, PagerDuty integration
- **Security**: JWT authentication, network segmentation, RBAC

**🏗️ Architecture Maturity**: Production-ready, SOC 2 compliant (in progress), 99.9% uptime SLA

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │       LYFTIUM Blockchain Infra       │
                    └─────────────────────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
        ▼                              ▼                              ▼
┌──────────────┐              ┌──────────────┐              ┌──────────────┐
│   Erigon     │              │  Lighthouse  │              │  MEV-Boost   │
│   PRIMARY    │◄────────────►│  Port: 5052  │◄────────────►│  Port: 18551 │
│ HTTP: 8545   │    Engine    │   Beacon     │   Builder    │   Relay      │
│ Engine: 8552 │     API      │  Consensus   │   API       │   API        │
└──────┬───────┘              └──────────────┘              └──────┬───────┘
       │                                                        │
       │                                                        ▼
       │                                               ┌──────────────┐
       │                                               │  RBuilder    │
       │                                               │  Port: 18552 │
       └─────────────── RPC queries ───────────────────┤  (Builder)   │
                                                       └──────────────┘
```

## Port Mappings

| Service | HTTP/RPC | WS | Engine API | Role |
|---------|----------|-----|------------|------|
| **Erigon** | 8545 | 8546 | 8552 | **PRIMARY** execution client for MEV |
| **Lighthouse** | 5052 | - | - | Consensus layer |
| **MEV-Boost** | 18551 | - | - | Builder relay (proposer-critical) |
| **RBuilder** | 18552 | - | - | Custom builder (optional) |

> **Note**: Reth (8557) and Geth (8549) are not part of the primary MEV stack. Erigon is the production execution client.

## Directory Structure

```
nodes/
├── README.md                    # This file
├── .gitignore                   # Excludes 2TB+ of data
│
├── configs/                     # All configurations (consolidated)
│   ├── jwt/                     # JWT secrets for Engine API
│   ├── reth/                    # Reth configurations
│   ├── lighthouse/              # Lighthouse beacon configs
│   ├── erigon-*.conf           # Erigon configurations
│   ├── mev-boost/               # MEV-Boost configs
│   ├── rbuilder-app/            # RBuilder configurations
│   ├── grafana/                 # Grafana dashboards
│   ├── monitoring/              # Prometheus configs
│   ├── systemd/                 # Service definitions
│   └── *.yml                    # Docker compose files
│
├── clients/                     # Client source code
│   └── alternative/             # Alternative blockchain clients
│       ├── bsc/                 # BSC client
│       ├── solana/              # Solana validator
│       └── avalanche/           # Avalanche node
│
├── consensus/                   # Consensus layer clients
│   └── lighthouse/              # Lighthouse beacon node
│       ├── start-lighthouse-beacon.sh
│       └── data/                # Beacon chain data (gitignored)
│
├── scripts/                     # Operational scripts
│   ├── deployment/              # Deployment automation
│   ├── monitoring/              # Health check scripts
│   └── maintenance/             # Maintenance utilities
│
├── bin/                         # Utility binaries
│   └── blockchain-sync-verify   # Sync verification tool
│
├── docs/                        # Documentation
│   └── node_management_workflows.md
│
├── docs_archive/                # Historical status reports
│
└── monitoring/                  # Active monitoring configs
    └── grafana/                 # Dashboard definitions
```

## Quick Start

### Prerequisites

- Linux server with 32GB+ RAM, 1TB+ NVMe SSD
- Docker and Docker Compose
- Rust toolchain (for Reth)
- Go 1.21+ (for Lighthouse)
- Python 3.13+ (for monitoring scripts)

### Clone Repository

```bash
git clone git@github.com:LYFTIUM-INC/nodes.git
cd nodes
```

### Setup Development Environment

```bash
# 1. Install Python dependencies
pip install ruff mypy

# 2. Install pre-commit hooks (recommended)
pip install pre-commit
pre-commit install

# 3. Copy environment template
cp .env.example .env
# Edit .env with your specific values

# 4. Start development services
docker-compose -f environments/dev/docker-compose.yml up -d
```

### Development Commands

```bash
# Code quality checks
ruff check .               # Check Python code style
ruff format .              # Format Python code
mypy --strict .           # Type check Python code
shellcheck scripts/*.sh   # Lint shell scripts

# Run monitoring script
./blockchain_node_monitor.py

# Check service health
curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq

# View logs
journalctl -u erigon.service -f
docker logs -f reth-ethereum-mev
```

### Service Status Check

```bash
# Check all running containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check Erigon sync status
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545

# Check Lighthouse sync
curl -s http://localhost:5052/eth/v1/node/syncing

# Check MEV-Boost status
curl -s http://localhost:18551/eth/v1/builder/status
```

## Operations

### Start Services

```bash
# Start Erigon execution client (primary)
sudo systemctl start erigon.service

# Start Lighthouse beacon
./consensus/lighthouse/start-lighthouse-beacon.sh

# Start MEV-Boost
sudo systemctl start mev-boost.service
# Or via docker-compose: docker-compose -f configs/mev-foundation-complete.yml up -d
```

### Stop Services

```bash
# Graceful shutdown
sudo systemctl stop mev-boost.service lighthouse-beacon.service erigon.service
```

### Health Monitoring

```bash
# Comprehensive health check
./scripts/monitoring/comprehensive-health-check.sh

# Check sync status
./bin/blockchain-sync-verify

# View logs
journalctl -u erigon.service -f --tail 100
```

## 📊 Current Infrastructure Status

> **Last Updated**: 2026-01-31 14:00 PST | **Environment**: Production

| Component | Status | Health | Notes |
|-----------|--------|--------|-------|
| **Erigon** | 🟢 Syncing | Optimal | PRIMARY – 6,803 / 18.9M blocks (Snap Sync) |
| **Lighthouse** | 🟢 Syncing | Stable | Beacon chain sync in progress |
| **MEV-Boost** | 🟢 Active | Operational | Connected to 5 relays |
| **RBuilder** | 🟢 Active | Profitable | Generating blocks |
| **ClickHouse** | 🟢 Active | 22.5B rows | Real-time analytics |
| **Monitoring** | 🟢 Active | 100% coverage | Prometheus + Grafana |

### Recent Changes (2026-01-31)

- ✅ **Erigon Optimization**: Implemented Snap Sync, reduced swap usage 75%
- ✅ **Infrastructure Cleanup**: Reduced directory count from 67 to 60
- ✅ **Security Enhancement**: Added .gitignore, .env templates
- ✅ **Docker Consolidation**: Reduced docker-compose files from 24 to 3
- 🔄 **Lighthouse Sync**: ~6-7 days remaining to merge point
- 🔄 **Erigon Snap Sync**: ~45 hours to completion (PRIMARY execution client)

## Troubleshooting

### Erigon / Execution Layer Stuck at Block 0

Execution clients require the consensus layer (Lighthouse) to sync first. This is expected behavior post-merge.

**Solution**: Wait for Lighthouse to reach the merge point (~24 hours), then Erigon will begin syncing.

### Erigon Snapshot Issues

Erigon v3.2.0 expects v1.1 snapshot format but has v1.0 format files.

**Solution**: Either re-download snapshots in v1.1 format or downgrade to v3.0.x.

### JWT Authentication Errors

Both execution and consensus clients require matching JWT secrets.

**Solution**: Ensure `/data/blockchain/storage/jwt-common/jwt-secret.hex` exists and is referenced in both configs.

## Security Best Practices

- **Never commit**: Private keys, JWT secrets, API keys, node data
- **Always use**: Environment variables for secrets
- **Rotate**: JWT secrets monthly
- **Monitor**: Unauthorized access attempts
- **Backup**: Critical configurations off-site

## Contributing

This is a production infrastructure repository. Changes should follow:

1. Create feature branch: `git checkout -b feature/your-change`
2. Test in non-production environment first
3. Submit PR with detailed description
4. Code review required
5. Conventional commits required: `feat(scope): description`

## License

Proprietary - LYFTIUM INC

---

**Last Updated**: 2025-01-06
**Repository**: https://github.com/LYFTIUM-INC/nodes
**Issues**: https://github.com/LYFTIUM-INC/nodes/issues
