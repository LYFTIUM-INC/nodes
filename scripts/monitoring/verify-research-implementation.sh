#!/usr/bin/env bash
# Research Implementation Quick Verification
# Validates key items from docs/checklists/RESEARCH_IMPLEMENTATION_STATUS.md
# Run from repo root: ./scripts/monitoring/verify-research-implementation.sh

set -euo pipefail
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "${REPO_ROOT}"

echo "=== Research Implementation Quick Verification ==="

# 1. MEV-Boost metrics reachable
echo ""
echo "[1] MEV-Boost metrics (port 18651)..."
if curl -sf --connect-timeout 2 "http://127.0.0.1:18651/metrics" 2>/dev/null | grep -q "mev_boost"; then
  echo "    OK: MEV-Boost metrics exposed (mev_boost_* present)"
else
  echo "    WARN: MEV-Boost metrics not reachable or no mev_boost_* metrics (service may be down)"
fi

# 2. Prometheus config valid
echo ""
echo "[2] Prometheus config validation..."
if command -v promtool &>/dev/null; then
  if promtool check config configs/monitoring/prometheus.yml 2>/dev/null; then
    echo "    OK: prometheus.yml valid"
  else
    # Fallback: full config may fail if /etc/prometheus/rules/* is unreadable (permission denied).
    # Validate using repo rules only (use absolute path since temp config is in /tmp).
    TMPCONF=$(mktemp)
    trap 'rm -f "$TMPCONF"' EXIT
    REPO_RULES="${REPO_ROOT}/configs/monitoring/rules/mev-alerts.yml"
    sed "s|/etc/prometheus/rules/\*\.yml|${REPO_RULES}|" \
      configs/monitoring/prometheus.yml > "$TMPCONF" 2>/dev/null
    if promtool check config "$TMPCONF" 2>/dev/null; then
      echo "    OK: prometheus.yml valid (repo rules; /etc/prometheus may be unreadable)"
    else
      echo "    FAIL: prometheus.yml invalid"
    fi
  fi
else
  echo "    SKIP: promtool not installed"
fi

# 3. MEV alerts file valid
echo ""
echo "[3] Prometheus rules (mev-alerts)..."
if command -v promtool &>/dev/null && [[ -f configs/monitoring/rules/mev-alerts.yml ]]; then
  if promtool check rules configs/monitoring/rules/mev-alerts.yml 2>/dev/null; then
    echo "    OK: mev-alerts.yml valid"
  else
    echo "    FAIL: mev-alerts.yml invalid"
  fi
else
  echo "    SKIP: promtool or mev-alerts.yml not found"
fi

# 4. JWT secret (full validation via validate-jwt-setup.sh)
echo ""
echo "[4] JWT secret..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if JWT_OUTPUT=$("${SCRIPT_DIR}/validate-jwt-setup.sh" 2>&1); then
  echo "    OK: JWT validation passed"
else
  echo "    FAIL: ${JWT_OUTPUT}"
fi

# 5. Engine API bound to localhost (Erigon)
echo ""
echo "[5] Engine API binding (port 8552)..."
if ss -tlnp 2>/dev/null | grep -q ":8552"; then
  echo "    OK: Port 8552 listening"
else
  echo "    INFO: Port 8552 not listening (Erigon may not be running)"
fi

# 6. Timing-games config present
echo ""
echo "[6] MEV-Boost timing-games config..."
if [[ -f configs/mev-boost/timing-games.yaml ]] && grep -q "timeout_get_header_ms: 950" configs/mev-boost/timing-games.yaml 2>/dev/null; then
  echo "    OK: timing-games.yaml with timeout_get_header_ms: 950"
else
  echo "    WARN: timing-games.yaml missing or timeout not 950"
fi

# 7. Lighthouse builder fallback in start script
echo ""
echo "[7] Lighthouse builder fallback..."
if grep -q "builder-fallback-epochs-since-finalization" consensus/lighthouse/start-lighthouse-beacon.sh 2>/dev/null; then
  echo "    OK: Builder fallback configured"
else
  echo "    WARN: Builder fallback not found in start script"
fi

echo ""
echo "=== Verification complete ==="
