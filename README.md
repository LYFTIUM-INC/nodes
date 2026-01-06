# LYFTIUM-INC/nodes

> Production blockchain infrastructure for MEV operations, analytics, and node services.

[![Status](https://img.shields.io/badge/status-production--ready-green)](https://github.com/LYFTIUM-INC/nodes)
[![Infrastructure](https://img.shields.io/badge/infrastructure-ethereum-blue)](https://ethereum.org/)
[![MEV](https://img.shields.io/badge/MEV-boost-purple)](https://github.com/flashbots/mev-boost)

## Overview

This repository contains the configuration and orchestration for LYFTIUM's blockchain node infrastructure. We operate:

- **Execution Layer**: Reth (primary), Erigon (backup/archive)
- **Consensus Layer**: Lighthouse beacon nodes
- **MEV Infrastructure**: MEV-Boost, RBuilder, relay connections
- **Analytics**: ClickHouse with 22.5B+ rows of blockchain data
- **Monitoring**: Prometheus, Grafana, custom health checks

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
│   Reth       │              │   Erigon     │              │  Lighthouse  │
│  Port: 8557  │◄────────────►│  Port: 8550  │              │  Port: 5052  │
│  Exec + API  │    Engine    │  Archive     │              │   Beacon     │
└──────────────┘     API       └──────────────┘              └──────┬───────┘
        │                                                   │
        ▼                                                   ▼
┌──────────────┐                                  ┌──────────────┐
│  MEV-Boost   │◄─────────────────────────────────│  Consensus   │
│  Port: 18550 │          Validator Updates        │    Layer     │
└──────┬───────┘                                  └──────────────┘
       │
       ▼
┌──────────────┐
│  RBuilder    │
│  Port: 18552 │
└──────────────┘
```

## Port Mappings

| Service | HTTP | WS | Metrics | Engine API |
|---------|------|-----|---------|------------|
| **Reth** | 8557 | 8558 | - | 8553 |
| **Erigon** | 8550 | 8551 | 6060 | 8552 |
| **Lighthouse** | 5052 | - | 5054 | - |
| **MEV-Boost** | 18550 | - | - | - |
| **RBuilder** | 18552 | - | - | - |

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

### Clone Repository

```bash
git clone git@github.com:LYFTIUM-INC/nodes.git
cd nodes
```

### Service Status Check

```bash
# Check all running containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check Reth sync status
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8557

# Check Lighthouse sync
curl -s http://localhost:5052/eth/v1/node/syncing

# Check MEV-Boost status
curl -s http://localhost:18550/eth/v1/builder/status
```

## Operations

### Start Services

```bash
# Start Reth execution client
docker start reth-ethereum-mev

# Start Lighthouse beacon
./consensus/lighthouse/start-lighthouse-beacon.sh

# Start MEV infrastructure
docker-compose -f configs/mev-foundation-complete.yml up -d
```

### Stop Services

```bash
# Graceful shutdown
docker stop reth-ethereum-mev lighthouse-mev-foundation
docker-compose -f configs/mev-foundation-complete.yml down
```

### Health Monitoring

```bash
# Comprehensive health check
./scripts/monitoring/comprehensive-health-check.sh

# Check sync status
./bin/blockchain-sync-verify

# View logs
docker logs -f reth-ethereum-mev --tail 100
```

## Current Infrastructure Status

| Component | Status | Notes |
|-----------|--------|-------|
| **Reth** | ⏸️ Stalled | Waiting for Lighthouse sync |
| **Erigon** | ❌ Inactive | Snapshot format incompatibility |
| **Lighthouse** | 🔄 Syncing | Slot ~298k / 13.1M (~6-7 days remaining) |

## Troubleshooting

### Reth Stuck at Block 0

Reth requires the consensus layer (Lighthouse) to sync first. This is expected behavior post-merge.

**Solution**: Wait for Lighthouse to reach the merge point (~24 hours), then Reth will begin syncing.

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
