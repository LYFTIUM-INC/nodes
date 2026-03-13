#!/usr/bin/env bash
# Restart OpenClaw and ZeroClaw gateways with latest builds.
# Use after rebuilding OpenClaw (pnpm build) and ZeroClaw (cargo build).
# MEV-Lab integration: both gateways support transaction ledger, credential vault, etc.

set -euo pipefail

OPENCLAW_SOURCE="${OPENCLAW_SOURCE:-/home/lyftium/openclaw-source}"
ZEROCLAW_SOURCE="${ZEROCLAW_SOURCE:-/home/lyftium/zeroclaw}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
ZEROCLAW_PORT="${ZEROCLAW_PORT:-3002}"

echo "=== Restarting Claw Gateways (Latest Builds) ==="

# 1. Stop existing processes
echo "[1/4] Stopping existing OpenClaw..."
pkill -f "openclaw.*gateway" 2>/dev/null || pkill -f "openclaw-" 2>/dev/null || true
sleep 2

echo "[2/4] Stopping existing ZeroClaw..."
pkill -f "zeroclaw gateway" 2>/dev/null || pkill -f "zeroclaw" 2>/dev/null || true
sleep 2

# 2. Rebuild (optional - skip if already built)
if [[ "${REBUILD:-0}" == "1" ]]; then
  echo "[3/4] Rebuilding OpenClaw..."
  (cd "$OPENCLAW_SOURCE" && pnpm run build) || { echo "OpenClaw build failed"; exit 1; }
  echo "[3/4] Rebuilding ZeroClaw..."
  (cd "$ZEROCLAW_SOURCE" && cargo build) || { echo "ZeroClaw build failed"; exit 1; }
else
  echo "[3/4] Skip rebuild (set REBUILD=1 to rebuild first)"
fi

# 3. Start OpenClaw
echo "[4/4] Starting OpenClaw on port $OPENCLAW_PORT..."
(cd "$OPENCLAW_SOURCE" && OPENCLAW_SKIP_CHANNELS=1 node scripts/run-node.mjs gateway --port "$OPENCLAW_PORT" &)
sleep 5

# 4. Start ZeroClaw (different port to avoid conflict)
echo "[4/4] Starting ZeroClaw on port $ZEROCLAW_PORT..."
(cd "$ZEROCLAW_SOURCE" && ./target/debug/zeroclaw gateway --port "$ZEROCLAW_PORT" --host 127.0.0.1 &)
sleep 4

# 5. Verify
echo ""
echo "=== Health Check ==="
if curl -sf "http://127.0.0.1:$OPENCLAW_PORT/health" >/dev/null 2>&1; then
  echo "  OpenClaw (port $OPENCLAW_PORT): OK"
else
  echo "  OpenClaw (port $OPENCLAW_PORT): FAILED or not ready"
fi
if curl -sf "http://127.0.0.1:$ZEROCLAW_PORT/health" >/dev/null 2>&1; then
  echo "  ZeroClaw (port $ZEROCLAW_PORT): OK"
else
  echo "  ZeroClaw (port $ZEROCLAW_PORT): FAILED or not ready"
fi
echo ""
echo "Done. Gateways run in background. See docs/MEV_LAB_CLAW_INTEGRATION.md for MEV-Lab integration."
