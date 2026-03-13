#!/usr/bin/env bash
# Detects Erigon "no CL requests to engine-api" condition (consensus layer disconnected)
# Generates Prometheus metric for alerting. Run via cron every 5 minutes.
# Best practice: Alert when erigon_cl_requests_absent > 0 for 30 minutes
#
# Setup:
#   1. Ensure node_exporter textfile collector is configured
#   2. Cron: */5 * * * * /data/blockchain/nodes/scripts/monitoring/erigon-cl-health-check.sh

set -euo pipefail

OUTPUT_DIR="${TEXTFILE_COLLECTOR_DIR:-/data/blockchain/nodes/var/node_exporter/textfile_collector}"
WINDOW_MINUTES=30
ERIGON_SERVICE="erigon.service"

mkdir -p "$OUTPUT_DIR"
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

# Check if "no CL requests" appears in recent Erigon logs (indicates Lighthouse/CL disconnect)
absent=0
if systemctl list-unit-files "${ERIGON_SERVICE}" &>/dev/null; then
    if journalctl -u "${ERIGON_SERVICE}" --since "${WINDOW_MINUTES} minutes ago" --no-pager 2>/dev/null | grep -q "no CL requests to engine-api"; then
        absent=1
    fi
fi

cat > "$TMPFILE" << EOF
# HELP erigon_cl_requests_absent Erigon has not received consensus layer requests (1=CL likely disconnected)
# TYPE erigon_cl_requests_absent gauge
erigon_cl_requests_absent{service="erigon"} ${absent}
EOF

mv "$TMPFILE" "${OUTPUT_DIR}/erigon_cl_health.prom.$$"
mv "${OUTPUT_DIR}/erigon_cl_health.prom.$$" "${OUTPUT_DIR}/erigon_cl_health.prom"
