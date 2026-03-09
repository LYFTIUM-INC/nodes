# Repository Structure Guide

> Canonical reference for LYFTIUM MEV Lab codebase organization. See also [README.md](../../README.md) and [AGENTS.md](../../AGENTS.md).

## Top-Level Layout

| Directory | Purpose |
|-----------|---------|
| `configs/` | All service configurations (systemd, Prometheus, Grafana, MEV-Boost, etc.) |
| `consensus/` | Consensus layer clients (Lighthouse beacon, start scripts) |
| `scripts/` | Operational scripts: `deployment/`, `monitoring/`, `maintenance/`, `utils/` |
| `docs/` | Documentation: guides, runbooks, reports, research, incidents |
| `environments/` | Docker Compose: `dev/`, `staging/`, `prod/` |
| `mev/` | MEV strategies, analytics, arbitrage engines, data pipeline |
| `mev-geth/` | Go MEV-Geth client (submodule) |
| `reth/` | Reth client configs and scripts |
| `clients/` | Alternative clients: BSC, Solana, Avalanche (configs only; source ignored) |

## Documentation Layout

| Path | Content |
|------|---------|
| `docs/guides/` | How-to guides (MEV-Boost upgrade, Erigon snapshot, etc.) |
| `docs/runbooks/` | Operational runbooks (DR drill, monitoring checks) |
| `docs/reports/` | Status reports, audits, roadmaps |
| `docs/research/` | Research, best practices, optimization proposals |
| `docs/incidents/` | Incident writeups and resolutions |
| `docs/checklists/` | Production readiness, compliance |

## Config Layout

| Path | Content |
|------|---------|
| `configs/systemd/` | systemd unit files (mev-boost, erigon, lighthouse, etc.) |
| `configs/mev-boost/` | MEV-Boost timing-games, boost.toml |
| `configs/monitoring/` | Prometheus, alert rules |
| `configs/grafana/` | Grafana dashboards |

## Conventions

- **Configs**: All configs live under `configs/`; no scattered `.conf` at root
- **Scripts**: Under `scripts/` with subdirs by function
- **Docs**: Under `docs/` with subdirs by type
- **Secrets**: Never committed; use `.env` and `/data/blockchain/storage/` paths

---

*Last updated: 2026-03-09*
