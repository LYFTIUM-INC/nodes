#!/usr/bin/env bash
# Verify Monitoring Stack - Prometheus, Alertmanager, node_exporter, MEV-Boost metrics
# Exit 0 if all reachable, 1 with error messages if any down
# Run from repo root or any directory (uses 127.0.0.1)
# See: docs/guides/MONITORING_DEPLOYMENT.md, docs/checklists/RESEARCH_IMPLEMENTATION_STATUS.md

set -euo pipefail

FAILED=0

echo "=== Monitoring Stack Verification ==="

# 1. Prometheus
if curl -sf --connect-timeout 3 "http://127.0.0.1:9090/-/healthy" >/dev/null 2>&1; then
  echo "OK: Prometheus (127.0.0.1:9090/-/healthy)"
else
  echo "FAIL: Prometheus (127.0.0.1:9090/-/healthy not reachable)"
  FAILED=1
fi

# 2. Alertmanager (optional - may not be deployed)
if curl -sf --connect-timeout 3 "http://127.0.0.1:9093/-/healthy" >/dev/null 2>&1; then
  echo "OK: Alertmanager (127.0.0.1:9093/-/healthy)"
else
  echo "SKIP: Alertmanager (127.0.0.1:9093 not running - optional)"
fi

# 3. node_exporter
if curl -sf --connect-timeout 3 "http://127.0.0.1:9100/metrics" >/dev/null 2>&1; then
  echo "OK: node_exporter (127.0.0.1:9100/metrics)"
else
  echo "FAIL: node_exporter (127.0.0.1:9100/metrics not reachable)"
  FAILED=1
fi

# 4. MEV-Boost metrics (port 18651)
if curl -sf --connect-timeout 3 "http://127.0.0.1:18651/metrics" 2>/dev/null | grep -q "mev_boost"; then
  echo "OK: MEV-Boost metrics (127.0.0.1:18651/metrics)"
else
  echo "FAIL: MEV-Boost metrics (127.0.0.1:18651/metrics not reachable or no mev_boost_* metrics)"
  FAILED=1
fi

echo "=== Done ==="
exit $FAILED
