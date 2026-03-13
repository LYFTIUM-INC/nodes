#!/usr/bin/env bash
# Lighthouse chain_db LevelDB integrity check (pre-restart validation)
# Read-only: does NOT modify any data.
# Exit 0 if OK, 1 if corrupted/missing.
# Used by ExecStartPre in lighthouse-beacon.service.d/db-check.conf
#
# Usage: ./lighthouse-db-integrity-check.sh [--skip-version-check]
#   --skip-version-check  Skip lighthouse db version verification (faster, file-only)
#
# See: docs/LIGHTHOUSE_DATABASE_CORRUPTION_FIX_2026-03-06.md

set -euo pipefail

LIGHTHOUSE_DATADIR="${LIGHTHOUSE_DATADIR:-/data/blockchain/nodes/consensus/lighthouse}"
CHAIN_DB="${LIGHTHOUSE_DATADIR}/beacon/chain_db"
CURRENT_FILE="${CHAIN_DB}/CURRENT"
SKIP_VERSION_CHECK=false

for arg in "$@"; do
    case "$arg" in
        --skip-version-check) SKIP_VERSION_CHECK=true ;;
        -h|--help)
            echo "Usage: $0 [--skip-version-check]"
            echo "  Checks LevelDB integrity before Lighthouse beacon start."
            echo "  Exit 0: OK, Exit 1: corrupted/missing"
            exit 0
            ;;
    esac
done

# 0. If chain_db doesn't exist (fresh start / post-corruption recovery), allow start
if [[ ! -d "${CHAIN_DB}" ]]; then
    exit 0
fi

# 1. Check chain_db/CURRENT exists and is non-empty
if [[ ! -f "${CURRENT_FILE}" ]]; then
    echo "lighthouse-db-integrity-check: chain_db/CURRENT missing at ${CURRENT_FILE}"
    exit 1
fi

if [[ ! -s "${CURRENT_FILE}" ]]; then
    echo "lighthouse-db-integrity-check: chain_db/CURRENT is empty"
    exit 1
fi

# 2. Optionally run lightweight LevelDB verification via lighthouse db version
#    (opens DB read-only and reads schema version - fails if corrupted)
if [[ "$SKIP_VERSION_CHECK" != "true" ]]; then
    if command -v lighthouse &>/dev/null; then
        if ! lighthouse database_manager version \
            --datadir "${LIGHTHOUSE_DATADIR}" \
            --network mainnet 2>/dev/null; then
            echo "lighthouse-db-integrity-check: lighthouse db version failed (possible corruption)"
            exit 1
        fi
    fi
    # If lighthouse not in PATH (e.g. container), file check is sufficient
fi

exit 0
