#!/usr/bin/env bash
# Setup MEV critical monitoring (restart loop + EL-CL disconnect alerts)
# Run with: sudo ./scripts/maintenance/setup-mev-critical-monitoring.sh
# See: docs/research/BLOCKCHAIN_NODE_MANAGEMENT_BEST_PRACTICES_MEV_2026.md

set -euo pipefail

REPO_ROOT="/data/blockchain/nodes"
TEXTFILE_DIR="${TEXTFILE_COLLECTOR_DIR:-/data/blockchain/nodes/var/node_exporter/textfile_collector}"
CRON_USER="${CRON_USER:-root}"

echo "=== MEV Critical Monitoring Setup ==="

# 0. Deploy MEV-Boost systemd fix (After=erigon.service per best practices)
if [ -f /etc/systemd/system/mev-boost.service ]; then
    cp -f "$REPO_ROOT/configs/systemd/mev-boost.service" /etc/systemd/system/mev-boost.service
    systemctl daemon-reload
    echo "MEV-Boost service updated (After=erigon.service)"
fi

# 1. Create textfile collector directory
mkdir -p "$TEXTFILE_DIR"
chown "$CRON_USER" "$TEXTFILE_DIR" 2>/dev/null || true
echo "Textfile collector dir: $TEXTFILE_DIR"

# 2. Make scripts executable
chmod +x "$REPO_ROOT/scripts/monitoring/systemd-restart-metrics.sh"
chmod +x "$REPO_ROOT/scripts/monitoring/erigon-cl-health-check.sh"

# 3. Add cron jobs (replace existing if present)
# Uses repo-local path so metrics work without /var/lib permissions
CRON_RESTART="* * * * * TEXTFILE_COLLECTOR_DIR=$TEXTFILE_DIR $REPO_ROOT/scripts/monitoring/systemd-restart-metrics.sh"
CRON_CL="*/5 * * * * TEXTFILE_COLLECTOR_DIR=$TEXTFILE_DIR $REPO_ROOT/scripts/monitoring/erigon-cl-health-check.sh"

(crontab -u "$CRON_USER" -l 2>/dev/null | grep -v "systemd-restart-metrics.sh" | grep -v "erigon-cl-health-check.sh"; echo "$CRON_RESTART"; echo "$CRON_CL") | crontab -u "$CRON_USER" -
echo "Cron jobs installed for user $CRON_USER"

# 4. Run once immediately
TEXTFILE_COLLECTOR_DIR="$TEXTFILE_DIR" "$REPO_ROOT/scripts/monitoring/systemd-restart-metrics.sh"
TEXTFILE_COLLECTOR_DIR="$TEXTFILE_DIR" "$REPO_ROOT/scripts/monitoring/erigon-cl-health-check.sh"
echo "Initial metrics generated"

# 5. Node Exporter textfile collector
echo ""
echo "=== Node Exporter Configuration ==="
echo "Add to node_exporter: --collector.textfile.directory=$TEXTFILE_DIR"
echo "Or symlink: sudo ln -sfn $TEXTFILE_DIR /var/lib/node_exporter/textfile_collector"
echo ""

# 6. Prometheus rules
echo "=== Prometheus Rules ==="
RULES_SRC="$REPO_ROOT/configs/monitoring/rules/mev-alerts.yml"
if [ -d /etc/prometheus/rules ]; then
    cp -f "$RULES_SRC" /etc/prometheus/rules/mev-alerts.yml 2>/dev/null && echo "Rules copied to /etc/prometheus/rules/" || echo "Copy rules manually: cp $RULES_SRC /etc/prometheus/rules/"
else
    echo "Copy rules to your Prometheus: cp $RULES_SRC /etc/prometheus/rules/"
fi

echo ""
echo "=== Done ==="
echo "Restart loop and EL-CL disconnect alerts are configured."
echo "Verify: ls -la $TEXTFILE_DIR/*.prom"
