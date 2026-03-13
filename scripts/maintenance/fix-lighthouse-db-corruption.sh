#!/usr/bin/env bash
# Fix Lighthouse chain_db corruption (missing .ldb files)
# Run with: sudo bash fix-lighthouse-db-corruption.sh
# See: docs/LIGHTHOUSE_DATABASE_CORRUPTION_FIX_2026-03-06.md

set -euo pipefail

BEACON_DIR="/data/blockchain/nodes/consensus/lighthouse/beacon"
TS=$(date +%Y%m%d_%H%M%S)
SERVICE="lighthouse-beacon.service"

echo "=== Lighthouse DB corruption fix ==="
echo "1. Stopping ${SERVICE}..."
systemctl stop "${SERVICE}" || true
sleep 3

echo "2. Backing up corrupted databases..."
cd "${BEACON_DIR}"
[[ -d chain_db ]] && mv chain_db "chain_db.corrupted.backup.${TS}"
[[ -d blobs_db ]] && mv blobs_db "blobs_db.corrupted.backup.${TS}"
[[ -d freezer_db ]] && mv freezer_db "freezer_db.corrupted.backup.${TS}"
echo "   Backed up to *.corrupted.backup.${TS}"

echo "3. Starting ${SERVICE} (checkpoint sync will run)..."
systemctl start "${SERVICE}"

echo "4. Waiting 10s for startup..."
sleep 10
systemctl status "${SERVICE}" --no-pager | head -15
echo ""
echo "Done. Lighthouse will checkpoint sync from https://sync.invis.tools/"
echo "Monitor: journalctl -u ${SERVICE} -f"
