#!/usr/bin/env bash
# Erigon snapshot format check: detects v1.0 vs v1.1 compatibility with Erigon v3.2+
# Exits 0 if OK (v1.1 or compatible), 1 if action needed (v1.0 or unknown)
# See: docs/guides/ERIGON_SNAPSHOT_REMEDIATION.md

set -euo pipefail

ERIGON_DATADIR="${ERIGON_DATADIR:-/data/blockchain/storage/erigon}"
ERIGON_BIN="${ERIGON_BIN:-/usr/local/bin/erigon}"
REMEDIATION_DOC="/data/blockchain/nodes/docs/guides/ERIGON_SNAPSHOT_REMEDIATION.md"

# Colors for output (optional)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; }

ACTION_NEEDED=0

# ---- 1. Check Erigon binary and version ----
check_erigon_version() {
    if [[ ! -x "$ERIGON_BIN" ]]; then
        log_fail "Erigon binary not found or not executable: $ERIGON_BIN"
        ACTION_NEEDED=1
        return
    fi

    local version_output
    version_output=$("$ERIGON_BIN" --version 2>&1 || true)
    echo "Erigon version: $version_output"

    # v3.2.0+ requires v1.1; v3.0.x supports v1.0
    if echo "$version_output" | grep -qE 'v3\.[2-9]|v3\.[0-9]{2}'; then
        log_warn "Erigon v3.2+ detected - requires v1.1 snapshot/receipt format"
        # Don't set ACTION_NEEDED yet - need to check actual data format
    elif echo "$version_output" | grep -qE 'v3\.0\.'; then
        log_info "Erigon v3.0.x - supports v1.0 format"
        # With v3.0.x, v1.0 is OK
        return
    fi
}

# ---- 2. Check snapshots directory and format indicators ----
check_snapshot_format() {
    local snap_dir="${ERIGON_DATADIR}/snapshots"
    local chaindata="${ERIGON_DATADIR}/chaindata"
    local kv_dir="${ERIGON_DATADIR}/kv"

    if [[ ! -d "$ERIGON_DATADIR" ]]; then
        log_warn "Erigon datadir not found: $ERIGON_DATADIR (no data yet)"
        # No data = OK to start fresh with v1.1
        return
    fi

    # E3 structure: snapshots/ (root has blocks: v1.1-*-bodies.seg, v1.1-*-headers.seg)
    # Also: snapshots/domain, snapshots/history, snapshots/idx, snapshots/accessor
    if [[ -d "$snap_dir" ]]; then
        # Check for v1.0 vs v1.1 in filenames (Erigon uses v1.0- or v1.1- prefix)
        local v10_count=0
        local v11_count=0
        local seg_count=0

        # Search snapshots root and all subdirs
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            local fname
            fname=$(basename "$f")
            ((seg_count++)) || true
            if [[ "$fname" == v1.1-* ]] || [[ "$fname" == *"-v1.1-"* ]]; then
                ((v11_count++)) || true
            elif [[ "$fname" == v1.0-* ]] || [[ "$fname" == *"-v1.0-"* ]]; then
                ((v10_count++)) || true
            fi
        done < <(find "$snap_dir" -maxdepth 2 -type f \( -name "*.seg" -o -name "*.idx" \) 2>/dev/null | head -50)

        if [[ $seg_count -eq 0 ]]; then
            log_warn "Snapshots dir exists but no segment files found (incomplete or empty)"
            # If chaindata exists with old db, likely v1.0
            if [[ -d "$chaindata" ]]; then
                log_warn "Existing chaindata present - likely v1.0 format from pre-v3.2 sync"
                ACTION_NEEDED=1
            fi
            return
        fi

        if [[ $v11_count -gt 0 ]] && [[ $v10_count -eq 0 ]]; then
            log_info "Snapshot format v1.1 (compatible with Erigon v3.2+)"
        elif [[ $v10_count -gt 0 ]]; then
            log_fail "Snapshot format v1.0 (incompatible with Erigon v3.2+)"
            ACTION_NEEDED=1
        else
            # Can't determine from filenames - check for receipt-adjustment hang evidence
            log_warn "Could not determine snapshot version from filenames (found $seg_count files)"
        fi
    fi

    # ---- 3. Check for receipt domain / startup hang evidence ----
    if systemctl list-unit-files erigon.service 2>/dev/null | grep -q erigon; then
        local last_logs
        last_logs=$(journalctl -u erigon.service -n 50 --no-pager 2>/dev/null || true)
        if echo "$last_logs" | grep -q "adjusting receipt current version to v1.1"; then
            log_fail "Logs show Erigon hanging at 'adjusting receipt current version to v1.1' (v1.0 data)"
            ACTION_NEEDED=1
        fi
        if echo "$last_logs" | grep -qE "persist\.receipt changed|inDB=false inConfig=true"; then
            log_warn "Receipt domain config mismatch detected (v1.0 -> v1.1 migration hang)"
            ACTION_NEEDED=1
        fi
    fi

    # If we have chaindata but no clear v1.1 indicators and erigon is v3.2+, assume action needed
    if [[ -d "$chaindata" ]] && [[ -d "$snap_dir" ]]; then
        local ver
        ver=$("$ERIGON_BIN" --version 2>&1 || true)
        if echo "$ver" | grep -qE 'v3\.[2-9]|v3\.[0-9]{2}' && [[ $v11_count -eq 0 ]] && [[ $v10_count -eq 0 ]] && [[ $seg_count -gt 0 ]]; then
            log_warn "Erigon v3.2+ with existing snapshots - cannot confirm v1.1. Run Erigon and check for hang."
            log_warn "If Erigon hangs at 'adjusting receipt...', remediation is required."
            ACTION_NEEDED=1
        fi
    fi
}

# ---- Main ----
main() {
    echo "=== Erigon Snapshot Format Check ==="
    echo "Datadir: $ERIGON_DATADIR"
    echo ""

    check_erigon_version
    check_snapshot_format

    echo ""
    if [[ $ACTION_NEEDED -eq 1 ]]; then
        log_fail "ACTION NEEDED: Erigon snapshot/receipt format may be v1.0 (incompatible with v3.2+)"
        echo "See: $REMEDIATION_DOC"
        echo "Options:"
        echo "  A) Re-download v1.1 snapshots (recommended)"
        echo "  B) Pin Erigon to v3.0.x (supports v1.0)"
        exit 1
    else
        log_info "Snapshot format OK (v1.1 or compatible / no data)"
        exit 0
    fi
}

main "$@"
