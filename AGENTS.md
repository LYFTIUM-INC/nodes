# AGENTS.md - Autonomous Agent Development Guide

> **Last Updated**: 2026-01-31  
> **Repository**: LYFTIUM-INC/nodes  
> **Primary Languages**: Python 3.13, Go, Shell Scripts, TypeScript/JavaScript

## 📋 Overview

This document provides essential information for autonomous agents (AI coding assistants) working in this blockchain infrastructure repository.

---

## 🎯 Repository Purpose

**LYFTIUM MEV Lab** - Production blockchain infrastructure for MEV (Maximal Extractable Value) operations, Ethereum node management, and real-time analytics.

**Key Components:**
- Execution Layer Clients: Reth (primary), Erigon (archive/analytics)
- Consensus Layer: Lighthouse beacon nodes
- MEV Infrastructure: MEV-Boost, RBuilder, private mempool, arbitrage engines
- Analytics: ClickHouse with 22.5B+ blockchain data rows
- Monitoring: Prometheus, Grafana, AlertManager, PagerDuty integration

---

## 🔧 Development Commands

### Python Scripts
```bash
# Type checking
mypy --strict .            # Strict type checking for Python
mypy blockchain_node_monitor.py  # Type check specific file

# Linting and formatting
ruff check .               # Check code style
ruff check --fix .         # Auto-fix linting issues
ruff format .              # Format code

# Run all checks
make test-all              # Run full test suite (if Makefile exists)
```

### Go Code (mev-geth/)
```bash
# Build
cd mev-geth/
make geth                  # Build geth binary

# Test
go test ./...              # Run all tests
go test -race ./...        # Run tests with race detection

# Lint
go vet ./...               # Go vet for code issues
gofmt -l .                # Check formatting
gofmt -w .                # Format code
```

### Shell Scripts
```bash
# Linting
shellcheck scripts/*.sh    # Check shell script quality

# Run health checks
./blockchain_node_monitor.py
./mev-health-check.sh
```

### Infrastructure Services
```bash
# Start services
docker-compose -f environments/prod/docker-compose.yml up -d
docker-compose -f environments/dev/docker-compose.yml up -d

# Stop services
docker-compose -f environments/prod/docker-compose.yml down

# Check service status
systemctl status erigon.service
systemctl status lighthouse.service
```

---

## 📦 Project Structure

```
nodes/
├── blockchain_node_monitor.py    # Main monitoring script
├── mev-geth/                       # Go client implementation
├── reth/                           # Reth client configs and scripts
├── erigon-monitor/                 # Erigon monitoring tools
├── mev/                            # MEV infrastructure (strategies, analytics)
├── configs/                        # All configurations (jwt, lighthouse, mev-boost)
├── consensus/                      # Consensus layer (lighthouse)
├── environments/                   # Environment-specific docker-compose files
│   ├── dev/
│   ├── staging/
│   └── prod/
├── scripts/                        # Operational and deployment scripts
├── monitoring/                     # Prometheus, Grafana configs
└── docs/                           # Documentation
```

---

## 🧪 Testing

### Unit Tests
```bash
# Python tests (if pytest configured)
pytest tests/ --cov
pytest --cov=src --cov-report=html

# Go tests
cd mev-geth/
go test -v ./...
go test -race -v ./...
```

### Integration Tests
```bash
# Check service health
curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Verify Erigon sync
curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

---

## 🔐 Security Considerations

### **CRITICAL**: Never Commit
- Private keys, JWT secrets, API keys
- Chain data (chaindata/, snapshots/, nodes/)
- Environment files (.env)
- Database files (*.db, *.sqlite)

### Secrets Management
- JWT secrets: `/data/blockchain/storage/jwt-common/jwt-secret.hex`
- Use `.env.example` as template for environment variables
- All secrets must be referenced via environment variables in code

### Access Control
- Some services require authentication (JWT for Engine API)
- Port mappings documented in README.md
- Network segmentation configured for production

---

## 🚀 Deployment Workflow

### 1. Configuration
```bash
# Copy environment template
cp .env.example .env
# Edit .env with your values

# Verify JWT secret exists
test -f /data/blockchain/storage/jwt-common/jwt-secret.hex
```

### 2. Start Services
```bash
# Development
docker-compose -f environments/dev/docker-compose.yml up -d

# Production
sudo systemctl start erigon.service
sudo systemctl start lighthouse.service
```

### 3. Verify Health
```bash
# Check service status
systemctl status erigon.service --no-pager
journalctl -u erigon.service -n 50 --no-pager

# Run health check script
./blockchain_node_monitor.py
```

---

## 📝 Code Style Guidelines

### Python
- **Type hints**: Required for all functions (`from typing import Optional, Protocol`)
- **Docstrings**: Google style docstrings preferred
- **Formatting**: `ruff format` (replaces flake8/black)
- **Line length**: 100 characters (ruff default)
- **Imports**: Absolute imports only
- **String formatting**: f-strings only

### Go
- **Formatting**: `gofmt -w .`
- **Naming**: `CamelCase` for exports, `camelCase` for private
- **Comments**: Exported functions must have comments
- **Error handling**: Always check error returns

### Shell Scripts
- **Shebang**: `#!/usr/bin/env bash`
- **Error handling**: `set -euo pipefail`
- **Linting**: `shellcheck` must pass
- **Variables**: Use uppercase for constants, lowercase for locals

### TypeScript/JavaScript
- **Style**: Prettier (if configured)
- **No `any`**: Use `unknown` with type guards
- **Prefix**: Booleans with `is/has/should`

---

## 🎯 Common Tasks

### Add New Monitoring Check
1. Create script in `scripts/monitoring/`
2. Add to Prometheus config in `configs/prometheus/`
3. Update Grafana dashboard in `configs/grafana/`
4. Test with `./scripts/monitoring/your-check.sh`

### Update Service Configuration
1. Edit service file in `configs/systemd/` or `configs/{service}/`
2. Test locally: `docker-compose -f environments/dev/docker-compose.yml up -d`
3. Deploy to staging: `docker-compose -f environments/staging/docker-compose.yml up -d`
4. Deploy to production after validation

### Add New MEV Strategy
1. Create strategy directory in `mev/strategies/`
2. Implement with proper type hints and docstrings
3. Add tests in `mev/strategies/tests/`
4. Update monitoring and analytics integration

---

## ⚠️ Important Constraints

### Resource Limitations
- **Memory**: 16GB total (4 cores, AMD EPYC 7543)
- **Disk**: 2.6TB SSD for blockchain data
- **Network**: 1Gbps
- **Swap**: 40GB (monitor usage - heavy swap = memory pressure)

### Performance Considerations
- Erigon Snap Sync: ~45 hours from snapshot
- Lighthouse sync: ~6-7 days to merge point
- Memory pressure impacts sync speed significantly
- Monitor swap usage - if >50%, investigate

### Known Issues
- Erigon requires v1.1 snapshot format (currently has v1.0)
- Reth waits for Lighthouse sync before execution sync begins
- JWT authentication required for Engine API between execution and consensus layers

---

## 🔍 Debugging Tips

### Check Sync Status
```bash
# Erigon
curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq

# Lighthouse
curl -s http://127.0.0.1:5052/eth/v1/node/syncing
```

### View Logs
```bash
# Service logs
journalctl -u erigon.service -f
journalctl -u lighthouse.service -f

# Docker logs
docker-compose logs -f reth-ethereum-mev
docker-compose logs -f lighthouse-mev-foundation
```

### Memory Issues
```bash
# Check memory usage
free -h

# Check swap usage
swapon --show

# Monitor process memory
ps aux | grep erigon
```

---

## 📚 Additional Resources

### Documentation
- **README.md**: Architecture overview and quick start
- **CONTRIBUTING.md**: Contribution guidelines and code review process
- **VALIDATION_REPORT.md**: Professional validation and reorganization report
- **REORGANIZATION_REPORT.md**: Infrastructure reorganization summary

### External References
- [Erigon Documentation](https://erigon.xyz/docs/)
- [Reth GitHub](https://github.com/paradigmxyz/reth)
- [Lighthouse Book](https://lighthouse-book.sigmaprime.io/)
- [MEV-Boost Specs](https://github.com/flashbots/mev-boost)
- [Flashbots Docs](https://docs.flashbots.net/)

---

## 🤝 Agent-Specific Conventions

### When Making Changes
1. **Read existing code** before making changes to match patterns
2. **Run linting** before committing: `ruff check . && ruff format .`
3. **Type check** Python code: `mypy --strict .`
4. **Test locally** if possible (monitoring scripts can be run directly)
5. **Document** any new scripts or configurations

### Git Commit Conventions
Follow conventional commits:
- `feat(infra): add new monitoring check for Erigon sync`
- `fix(mev): resolve RBuilder connection timeout`
- `docs(readme): update architecture diagram`
- `refactor(scripts): consolidate health check logic`

### File Locations
- **Configs**: Always in `configs/` with subdirectories by service
- **Scripts**: Operational scripts in `scripts/`, monitoring in `scripts/monitoring/`
- **Documentation**: All docs in `docs/`, status reports in root
- **Tests**: Co-located with code being tested

---

## ⚡ Quick Reference

### Start Development
```bash
# 1. Set up environment
cp .env.example .env

# 2. Start development services
docker-compose -f environments/dev/docker-compose.yml up -d

# 3. Run linting
ruff check .
ruff format .

# 4. Type check
mypy --strict .

# 5. Check service status
./blockchain_node_monitor.py
```

### Validate Changes
```bash
# 1. Lint check
ruff check --fix .

# 2. Format code
ruff format .

# 3. Type check
mypy --strict .

# 4. Shell script check
find scripts/ -name "*.sh" -exec shellcheck {} \;

# 5. Docker compose validation
find . -name "docker-compose*.yml" -exec docker-compose -f {} config --quiet \;
```

### Deploy to Production
```bash
# 1. Update configs in configs/
# 2. Test in staging
docker-compose -f environments/staging/docker-compose.yml up -d

# 3. Restart production services
sudo systemctl restart erigon.service

# 4. Monitor logs
journalctl -u erigon.service -f
```

---

**Contact**: contact@lyftium.com  
**Issues**: https://github.com/LYFTIUM-INC/nodes/issues  
**Slack**: #lyftium-dev

---

*This document is maintained for autonomous agent development. Keep it updated as the codebase evolves.*
