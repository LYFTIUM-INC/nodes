#!/usr/bin/env bash
# Generates Prometheus metrics for systemd service restart detection (restart loops)
# Used by node_exporter textfile collector. Run via cron every 1-2 minutes.
# Best practice: Alert when systemd_service_starts_5m > 3 for 2 minutes
#
# Setup:
#   1. Ensure node_exporter has: --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
#   2. Cron: * * * * * /data/blockchain/nodes/scripts/monitoring/systemd-restart-metrics.sh
#   3. Or: systemd timer

set -euo pipefail

OUTPUT_DIR="${TEXTFILE_COLLECTOR_DIR:-/data/blockchain/nodes/var/node_exporter/textfile_collector}"
SERVICES=("erigon" "lighthouse-beacon" "mev-boost")
WINDOW_MINUTES=5

mkdir -p "$OUTPUT_DIR"
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" << 'EOF'
# HELP systemd_service_starts_5m Number of service starts in the last 5 minutes (restart loop detection)
# TYPE systemd_service_starts_5m gauge
EOF

for service in "${SERVICES[@]}"; do
    count=0
    if systemctl list-unit-files "${service}.service" &>/dev/null; then
        count=$(journalctl -u "${service}.service" --since "${WINDOW_MINUTES} minutes ago" --no-pager 2>/dev/null | grep -c "Started ${service}" || true)
    fi
    # Validate count is numeric
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    echo "systemd_service_starts_5m{service=\"${service}\"} ${count}" >> "$TMPFILE"
done

mv "$TMPFILE" "${OUTPUT_DIR}/systemd_restarts_mev.prom.$$"
mv "${OUTPUT_DIR}/systemd_restarts_mev.prom.$$" "${OUTPUT_DIR}/systemd_restarts_mev.prom"
