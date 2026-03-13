# Reth Migration Scripts

Scripts supporting the Erigon → Reth execution layer migration. See [docs/guides/RETH_MIGRATION_PLAN.md](../../docs/guides/RETH_MIGRATION_PLAN.md) for the full migration plan.

---

## Order of Execution

| Order | Script                   | When to Run                           |
|-------|--------------------------|---------------------------------------|
| 1     | `prepare-reth-migration.sh` | Before Phase 1 (Preparation)       |
| 2     | —                        | Phase 2: Sync Reth in parallel (manual) |
| 3     | `switch-to-reth.sh`      | Phase 3: Use as step outline before switchover |

---

## Scripts

### prepare-reth-migration.sh

**Purpose**: Pre-flight checks before migration.

**Checks**:
- Disk space (≥ 1.1 TB for Reth full node)
- Reth binary at `/usr/local/bin/reth`
- `reth.service` config (auth on 127.0.0.1, metrics port)
- JWT secret presence

**Usage**:
```bash
./scripts/migration/prepare-reth-migration.sh
```

**Exit codes**:
- `0` — All checks passed, ready to proceed
- `1` — One or more checks failed

**Example**:
```bash
cd /data/blockchain/nodes
./scripts/migration/prepare-reth-migration.sh
```

---

### switch-to-reth.sh

**Purpose**: Template/skeleton listing the switchover steps.

**Behavior**: Prints the commands for Phase 3 (stop Erigon, point Lighthouse to Reth, start Reth, restart MEV-Boost, verify). It does **not** execute any commands.

**Usage**:
```bash
./scripts/migration/switch-to-reth.sh
```

Review the output and run each command manually when ready.

---

## Migration Workflow Summary

1. **Prepare**: Run `prepare-reth-migration.sh`. Fix any failures.
2. **Sync**: Start Reth and let it sync (see migration plan for port config).
3. **Switch**: Follow steps printed by `switch-to-reth.sh` during your maintenance window.
4. **Optional**: Repurpose Erigon for archive/ClickHouse (Phase 4 in migration plan).

---

## References

- [RETH_MIGRATION_PLAN.md](../../docs/guides/RETH_MIGRATION_PLAN.md)
- [ERIGON_VS_RETH_MEV_2026.md](../../docs/research/ERIGON_VS_RETH_MEV_2026.md)
