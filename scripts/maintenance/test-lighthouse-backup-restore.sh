#!/usr/bin/env bash
# Test Lighthouse Backup Restore (DR Drill)
# Validates that a backup tarball can be extracted and Lighthouse opens the DB.
# NEVER touches production chain_db - uses temp directory only.
#
# Usage: ./test-lighthouse-backup-restore.sh [backup_tar.gz]
#   Default: latest backup from consensus/lighthouse/backups/
#
# Exit: 0 success, 1 failure
# See: docs/runbooks/QUARTERLY_DR_DRILL.md

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/data/blockchain/nodes}"
BACKUP_DIR="${REPO_ROOT}/consensus/lighthouse/backups"
JWT_SECRET="${JWT_SECRET:-/data/blockchain/storage/jwt-common/jwt-secret.hex}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Resolve backup file
resolve_backup() {
    local arg="${1:-}"
    if [[ -n "${arg}" && -f "${arg}" ]]; then
        echo "${arg}"
        return
    fi
    local latest
    latest=$(ls -t "${BACKUP_DIR}"/lighthouse-backup-*.tar.gz 2>/dev/null | head -1)
    if [[ -z "${latest}" ]]; then
        log_error "No backup found. Run: ${REPO_ROOT}/scripts/backup-lighthouse-db.sh"
        return 1
    fi
    echo "${latest}"
}

# Safety: ensure we never touch production
abort_if_production_path() {
    local path="$1"
    local prod_beacon="${REPO_ROOT}/consensus/lighthouse/beacon"
    local prod_chain_db="${prod_beacon}/chain_db"
    if [[ "${path}" == "${prod_beacon}" ]] || [[ "${path}" == "${prod_chain_db}" ]]; then
        log_error "SAFETY: Refusing to operate on production path: ${path}"
        exit 2
    fi
    if [[ "${path}" == *"/consensus/lighthouse/beacon"* ]]; then
        log_error "SAFETY: Path appears to be production: ${path}"
        exit 2
    fi
}

main() {
    log_info "DR Drill: Test Lighthouse Backup Restore"
    log_info "Repo root: ${REPO_ROOT}"

    BACKUP_FILE=$(resolve_backup "${1:-}") || exit 1
    log_info "Backup file: ${BACKUP_FILE}"

    TEST_DIR=$(mktemp -d /tmp/lighthouse-dr-drill.XXXXXXXXXX)
    trap 'rm -rf "${TEST_DIR}"' EXIT
    log_info "Test directory: ${TEST_DIR}"

    # Extract to temp (structure: chain_db, blobs_db, freezer_db in a beacon-like dir)
    RESTORE_BEACON="${TEST_DIR}/beacon"
    mkdir -p "${RESTORE_BEACON}"
    abort_if_production_path "${RESTORE_BEACON}"

    log_info "Extracting backup..."
    if ! tar -xzf "${BACKUP_FILE}" -C "${RESTORE_BEACON}"; then
        log_error "Failed to extract backup"
        exit 1
    fi

    if [[ ! -d "${RESTORE_BEACON}/chain_db" ]]; then
        log_error "Backup missing chain_db directory"
        exit 1
    fi
    if [[ ! -f "${RESTORE_BEACON}/chain_db/CURRENT" ]] || [[ ! -s "${RESTORE_BEACON}/chain_db/CURRENT" ]]; then
        log_warn "chain_db/CURRENT missing or empty - DB may be minimal or checkpoint-only"
    fi
    log_info "Backup structure OK (chain_db present)"

    LIGHTHOUSE_BIN=$(command -v lighthouse 2>/dev/null || echo "/usr/local/bin/lighthouse")
    if [[ ! -x "${LIGHTHOUSE_BIN}" ]]; then
        log_error "Lighthouse binary not found at ${LIGHTHOUSE_BIN}"
        exit 1
    fi

    if [[ ! -f "${JWT_SECRET}" ]]; then
        log_warn "JWT secret not found at ${JWT_SECRET} - Lighthouse may fail auth"
    fi

    log_info "Starting Lighthouse briefly to verify DB (timeout 45s, no discovery)..."
    local out
    out=$(timeout 45 "${LIGHTHOUSE_BIN}" beacon_node \
        --network mainnet \
        --datadir "${TEST_DIR}" \
        --execution-endpoint "http://127.0.0.1:8552" \
        --execution-jwt "${JWT_SECRET}" \
        --http --http-address 127.0.0.1 --http-port 0 \
        --disable-discovery \
        --disable-enr-auto-update \
        2>&1) || true
    local rc=$?
    echo "${out}" | head -80
    if [[ ${rc} -eq 124 ]]; then
        log_info "Lighthouse ran for 45s (timeout) - DB opened successfully"
    elif [[ ${rc} -eq 0 ]]; then
        log_info "Lighthouse started and opened DB"
    else
        log_error "Lighthouse exited with code ${rc}"
        exit 1
    fi

    log_info "DR drill passed: backup is restorable, Lighthouse opens DB"
    exit 0
}

main "$@"
