#!/usr/bin/env bash
# switch-to-reth.sh - TEMPLATE/SKELETON for Erigon → Reth switchover
#
# ⚠️  WARNING: This script does NOT execute destructive commands.
# ⚠️  It is a template outlining the steps. Review and run commands manually.
#
# See: docs/guides/RETH_MIGRATION_PLAN.md

set -euo pipefail

echo "=== Reth Switchover Template ==="
echo "This script prints the steps. Run each command manually after review."
echo ""

# --- Step 1: Stop Erigon ---
echo "# Step 1: Stop Erigon"
echo "sudo systemctl stop erigon.service"
echo ""

# --- Step 2: Update Lighthouse execution endpoint ---
echo "# Step 2: Point Lighthouse to Reth Engine API (port 8553)"
echo "# Edit consensus/lighthouse/start-lighthouse-beacon.sh:"
echo "#   Change ERIGON_ENDPOINT=\"http://127.0.0.1:8552\""
echo "#   To:   RETH_ENDPOINT=\"http://127.0.0.1:8553\""
echo "#   And use RETH_ENDPOINT in --execution-endpoint"
echo "# OR if using systemd/lighthouse.toml, set execution-endpoint = \"http://127.0.0.1:8553\""
echo ""

# --- Step 3: Update MEV-Boost dependency ---
echo "# Step 3: Update configs/systemd/mev-boost.service"
echo "# Change: After=network-online.target erigon.service"
echo "# To:     After=network-online.target reth.service"
echo "# Then: sudo systemctl daemon-reload"
echo ""

# --- Step 4: Start Reth ---
echo "# Step 4: Start Reth"
echo "sudo systemctl start reth.service"
echo ""

# --- Step 5: Restart Lighthouse and MEV-Boost ---
echo "# Step 5: Restart Lighthouse and MEV-Boost"
echo "sudo systemctl restart lighthouse.service  # or your beacon service name"
echo "sudo systemctl restart mev-boost.service"
echo ""

# --- Step 6: Verify ---
echo "# Step 6: Verify"
echo "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://127.0.0.1:8557 | jq"
echo "curl -s http://127.0.0.1:5052/eth/v1/node/syncing | jq"
echo "curl -s http://127.0.0.1:18651/metrics | head -20"
echo ""
echo "=== End of switchover template ==="
