#!/usr/bin/env bash
# MEV Infrastructure Health Check Script
# Aligned with production stack: Erigon, Lighthouse, MEV-Boost, RBuilder
# Tests: Erigon 8545, Lighthouse 5052, MEV-Boost 18551, RBuilder 18552
# Exits 0 only if critical services pass (Erigon, Lighthouse, MEV-Boost); RBuilder optional if not deployed
# Set MEV_REQUIRE_RBUILDER=1 to require RBuilder for pass

set -euo pipefail

# Timeouts (seconds)
TIMEOUT_RPC=10
TIMEOUT_LIGHTHOUSE=10
TIMEOUT_MEV_BOOST=8
TIMEOUT_RBUILDER=8

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== MEV Infrastructure Health Check ==="
echo "Time: $(date)"
echo ""

# --- jq availability: use if present, else fallback to grep/sed ---
HAS_JQ=false
if command -v jq &>/dev/null; then
    HAS_JQ=true
fi

# Function to check service
check_service() {
    local service=$1
    local status
    status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")

    if [ "$status" = "active" ]; then
        echo -e "${GREEN}✓${NC} $service: Active"
        return 0
    else
        echo -e "${RED}✗${NC} $service: $status"
        return 1
    fi
}

# Function to check RPC endpoint (execution layer) - handles jq missing
check_rpc() {
    local name=$1
    local url=$2
    local raw
    raw=$(curl -s -m "$TIMEOUT_RPC" -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$url" 2>/dev/null || echo "")

    local result=""
    if $HAS_JQ; then
        result=$(echo "$raw" | jq -r '.result // "ERROR"' 2>/dev/null)
    else
        result=$(echo "$raw" | grep -oE '"result":"0x[0-9a-fA-F]+"' | head -1 | cut -d'"' -f4)
    fi

    if [ -n "$result" ] && [ "$result" != "ERROR" ] && [ "$result" != "null" ]; then
        local block
        block=$(printf "%d" "0x${result#0x}" 2>/dev/null || echo "?")
        echo -e "${GREEN}✓${NC} $name RPC (8545): Block $block"
        return 0
    else
        echo -e "${RED}✗${NC} $name RPC (8545): Not responding"
        return 1
    fi
}

# Function to check Lighthouse consensus API - handles jq missing
check_lighthouse() {
    local url="${1:-http://127.0.0.1:5052}"
    local raw
    raw=$(curl -s -m "$TIMEOUT_LIGHTHOUSE" "${url}/eth/v1/node/syncing" 2>/dev/null || echo "")

    local result=""
    if $HAS_JQ; then
        # Note: jq '//' treats false as null; use 'if .data then ...' to accept both true/false
        result=$(echo "$raw" | jq -r 'if .data then (.data.is_syncing | tostring) else "ERROR" end' 2>/dev/null)
    else
        result=$(echo "$raw" | grep -oE '"is_syncing":(true|false)' | head -1 | cut -d':' -f2)
    fi

    if [ -n "$result" ] && [ "$result" != "ERROR" ]; then
        echo -e "${GREEN}✓${NC} Lighthouse API (5052): is_syncing=$result"
        return 0
    else
        echo -e "${RED}✗${NC} Lighthouse API (5052): Not responding"
        return 1
    fi
}

# Function to check MEV-Boost (v1.9 returns {} on /, v1.12+ has /metrics)
check_mev_boost() {
    local url="${1:-http://127.0.0.1:18551}"
    local resp
    resp=$(curl -s -m "$TIMEOUT_MEV_BOOST" "${url}/" 2>/dev/null | head -1)
    if echo "$resp" | grep -qE '(html|OK|metrics|\{\})'; then
        echo -e "${GREEN}✓${NC} MEV-Boost (18551): Responding"
        return 0
    fi
    if curl -s -m "$TIMEOUT_MEV_BOOST" "${url}/metrics" 2>/dev/null | head -1 | grep -qE '^#'; then
        echo -e "${GREEN}✓${NC} MEV-Boost (18551): Metrics available"
        return 0
    fi
    # Empty or short response = MEV-Boost v1.9 root endpoint
    if [ -n "$resp" ] && [ ${#resp} -lt 100 ]; then
        echo -e "${GREEN}✓${NC} MEV-Boost (18551): Responding"
        return 0
    fi
    echo -e "${RED}✗${NC} MEV-Boost (18551): Not responding"
    return 1
}

# Function to check RBuilder (critical for MEV - builder endpoint)
check_rbuilder() {
    local url="${1:-http://127.0.0.1:18552}"
    if curl -s -m "$TIMEOUT_RBUILDER" "${url}/" 2>/dev/null | head -1 | grep -qE '(html|OK|metrics|builder)'; then
        echo -e "${GREEN}✓${NC} RBuilder (18552): Responding"
        return 0
    fi
    if curl -s -m "$TIMEOUT_RBUILDER" "${url}/metrics" 2>/dev/null | head -1 | grep -qE '^#'; then
        echo -e "${GREEN}✓${NC} RBuilder (18552): Metrics available"
        return 0
    fi
    echo -e "${RED}✗${NC} RBuilder (18552): Not responding"
    return 1
}

# Optional: warn if jq missing
if ! $HAS_JQ; then
    echo -e "${YELLOW}⚠${NC} jq not found - using grep fallback for JSON parsing"
fi

# Critical MEV services (production stack)
echo "=== Service Status (MEV Critical) ==="
MEV_SERVICES=(erigon lighthouse-beacon mev-boost)
failed_services=0

for service in "${MEV_SERVICES[@]}"; do
    check_service "${service}.service" || ((failed_services++))
done

echo ""
echo "=== Execution Layer (Erigon) - Port 8545 ==="
check_rpc "Ethereum" "http://127.0.0.1:8545" || ((failed_services++))

echo ""
echo "=== Consensus Layer (Lighthouse) - Port 5052 ==="
check_lighthouse "http://127.0.0.1:5052" || ((failed_services++))

echo ""
echo "=== MEV-Boost - Port 18551 ==="
check_mev_boost "http://127.0.0.1:18551" || ((failed_services++))

echo ""
echo "=== RBuilder - Port 18552 ==="
if [[ "${MEV_REQUIRE_RBUILDER:-0}" == "1" ]]; then
    check_rbuilder "http://127.0.0.1:18552" || ((failed_services++))
else
    if check_rbuilder "http://127.0.0.1:18552"; then
        :
    else
        echo -e "${YELLOW}⚠${NC} RBuilder not running (optional; set MEV_REQUIRE_RBUILDER=1 to require)"
    fi
fi

echo ""
echo "=== Critical Ports ==="
critical_ports=(8545 8546 8552 5052 18551 18552)
for port in "${critical_ports[@]}"; do
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
        echo -e "${GREEN}✓${NC} Port $port: Listening"
    else
        echo -e "${YELLOW}⚠${NC} Port $port: Not listening"
    fi
done

# Optional: public RPC endpoints (informational, don't fail)
echo ""
echo "=== Public Endpoints (Optional) ==="
if $HAS_JQ; then
    if curl -s -m 5 -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "https://eth.rpc.lyftium.com:8443/" 2>/dev/null | jq -e '.result' >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} eth.rpc.lyftium.com: Reachable"
    else
        echo -e "${YELLOW}⚠${NC} eth.rpc.lyftium.com: Unreachable (optional)"
    fi
else
    echo -e "${YELLOW}⚠${NC} Skipping public RPC check (jq required)"
fi

# Summary
echo ""
echo "=== Summary ==="
if [ "$failed_services" -eq 0 ]; then
    echo -e "${GREEN}✅ ALL MEV SYSTEMS OPERATIONAL${NC}"
    echo "Erigon (8545) + Lighthouse (5052) + MEV-Boost (18551) ready for MEV operations"
    exit 0
else
    echo -e "${RED}❌ ISSUES DETECTED: $failed_services critical failures${NC}"
    echo "Action required for MEV operations!"
    exit 1
fi
