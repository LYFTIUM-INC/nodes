#!/usr/bin/env bash
# prepare-reth-migration.sh - Pre-flight checks for Erigon → Reth migration
# Exit 0 if ready, 1 with errors if not. Run before Phase 1/2 of RETH_MIGRATION_PLAN.md

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/data/blockchain/nodes}"
RETH_BINARY="${RETH_BINARY:-/usr/local/bin/reth}"
RETH_SERVICE="${RETH_SERVICE:-/data/blockchain/nodes/configs/systemd/reth.service}"
RETH_DATADIR="${RETH_DATADIR:-/data/blockchain/storage/reth}"
REQUIRED_DISK_GB=1100
JWT_PATH="/data/blockchain/storage/jwt-common/jwt-secret.hex"
LIGHTHOUSE_DATADIR="/data/blockchain/nodes/consensus/lighthouse"
ERRORS=0

echo "=== Reth Migration Pre-Flight Check ==="
echo ""

# --- Disk space ---
check_disk() {
    local mount
    mount=$(df -BG "${RETH_DATADIR}" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    # If datadir doesn't exist, check parent
    if [[ -z "${mount}" ]]; then
        mount=$(df -BG "$(dirname "${RETH_DATADIR}")" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    fi
    if [[ -z "${mount}" ]]; then
        mount=$(df -BG /data 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    fi
    if [[ -z "${mount}" ]] || [[ "${mount}" == "-" ]]; then
        echo "❌ Disk: Cannot determine free space for ${RETH_DATADIR}"
        ((ERRORS++)) || true
        return
    fi
    if [[ "${mount}" -lt "${REQUIRED_DISK_GB}" ]]; then
        echo "❌ Disk: Need ~${REQUIRED_DISK_GB} GB free for Reth full node. Available: ~${mount} GB"
        ((ERRORS++)) || true
    else
        echo "✅ Disk: ~${mount} GB free (need ≥ ${REQUIRED_DISK_GB} GB)"
    fi
}

# --- Reth binary ---
check_reth_binary() {
    if [[ ! -f "${RETH_BINARY}" ]]; then
        echo "❌ Reth binary: Not found at ${RETH_BINARY}"
        ((ERRORS++)) || true
    elif [[ ! -x "${RETH_BINARY}" ]]; then
        echo "❌ Reth binary: Exists but not executable at ${RETH_BINARY}"
        ((ERRORS++)) || true
    else
        local ver
        ver=$("${RETH_BINARY}" --version 2>/dev/null || echo "unknown")
        echo "✅ Reth binary: Found at ${RETH_BINARY} (${ver})"
    fi
}

# --- reth.service config ---
check_reth_service() {
    if [[ ! -f "${RETH_SERVICE}" ]]; then
        echo "❌ reth.service: Not found at ${RETH_SERVICE}"
        ((ERRORS++)) || true
        return
    fi

    local auth_ok=false metrics_ok=false
    if grep -qE 'auth\.addr.*127\.0\.0\.1' "${RETH_SERVICE}" 2>/dev/null; then
        auth_ok=true
    fi
    if grep -qE 'metrics\.(addr|port)' "${RETH_SERVICE}" 2>/dev/null; then
        metrics_ok=true
    fi

    if [[ "${auth_ok}" != "true" ]]; then
        echo "❌ reth.service: Missing or incorrect --auth.addr 127.0.0.1 (Engine API must be localhost)"
        ((ERRORS++)) || true
    else
        echo "✅ reth.service: auth.addr 127.0.0.1 present"
    fi
    if [[ "${metrics_ok}" != "true" ]]; then
        echo "❌ reth.service: Missing --metrics.addr/port"
        ((ERRORS++)) || true
    else
        echo "✅ reth.service: metrics config present"
    fi
}

# --- JWT secret ---
check_jwt() {
    if [[ ! -f "${JWT_PATH}" ]]; then
        echo "❌ JWT: Not found at ${JWT_PATH}"
        ((ERRORS++)) || true
    else
        echo "✅ JWT: Found at ${JWT_PATH}"
    fi
}

# Run checks
check_disk
check_reth_binary
check_reth_service
check_jwt

echo ""
echo "=== Pre-Flight Checklist (Manual) ==="
echo "  [ ] Backup JWT: cp ${JWT_PATH} /backup/jwt-secret.hex.\$(date +%Y%m%d)"
echo "  [ ] Backup Lighthouse checkpoint: ./scripts/backup-lighthouse-db.sh (or equivalent)"
echo "  [ ] Confirm Erigon is synced and healthy"
echo "  [ ] Review docs/guides/RETH_MIGRATION_PLAN.md"
echo ""

if [[ ${ERRORS} -gt 0 ]]; then
    echo "❌ Pre-flight failed with ${ERRORS} error(s). Fix issues before migration."
    exit 1
fi

echo "✅ Pre-flight passed. Ready for migration."
exit 0
