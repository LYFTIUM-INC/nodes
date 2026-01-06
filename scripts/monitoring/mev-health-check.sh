#!/bin/bash
# MEV Infrastructure Health Check Script
# Critical for ensuring all blockchain nodes are operational

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== MEV Infrastructure Health Check ==="
echo "Time: $(date)"
echo ""

# Function to check service
check_service() {
    local service=$1
    local status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
    
    if [ "$status" = "active" ]; then
        echo -e "${GREEN}✓${NC} $service: Active"
        return 0
    else
        echo -e "${RED}✗${NC} $service: $status"
        return 1
    fi
}

# Function to check RPC endpoint
check_rpc() {
    local name=$1
    local url=$2
    local result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$url" 2>/dev/null | jq -r '.result // "ERROR"')
    
    if [ "$result" != "ERROR" ] && [ "$result" != "null" ]; then
        local block=$(printf "%d" 0x${result#0x})
        echo -e "${GREEN}✓${NC} $name RPC: Block $block"
        return 0
    else
        echo -e "${RED}✗${NC} $name RPC: Not responding"
        return 1
    fi
}

# Check all services
echo "=== Service Status ==="
services=(erigon haveged mev-boost mev-execution nginx)
failed_services=0

for service in "${services[@]}"; do
    check_service $service || ((failed_services++))
done

echo ""
echo "=== RPC Endpoint Status ==="
rpc_failed=0

# Check local RPC endpoints
check_rpc "Ethereum" "http://127.0.0.1:8545" || ((rpc_failed++))
check_rpc "Optimism" "http://127.0.0.1:8546" || ((rpc_failed++))
check_rpc "Arbitrum" "http://127.0.0.1:8547" || ((rpc_failed++))
check_rpc "Base" "http://127.0.0.1:8548" || ((rpc_failed++))
check_rpc "Polygon" "http://127.0.0.1:8549" || ((rpc_failed++))

echo ""
echo "=== Public Domain Endpoints ==="

# Check public endpoints
check_rpc "eth.rpc.lyftium.com" "https://eth.rpc.lyftium.com:8443/" || ((rpc_failed++))
check_rpc "arb.rpc.lyftium.com" "https://arb.rpc.lyftium.com:8443/" || ((rpc_failed++))

echo ""
echo "=== MEV Critical Services ==="

# Check MEV-specific services
if pgrep -f "mev-boost" > /dev/null; then
    echo -e "${GREEN}✓${NC} MEV-Boost: Running"
else
    echo -e "${YELLOW}⚠${NC} MEV-Boost: Not running"
fi

if pgrep -f "mev-infra" > /dev/null; then
    echo -e "${GREEN}✓${NC} MEV-Infra: Running"
else
    echo -e "${YELLOW}⚠${NC} MEV-Infra: Not running"
fi

# Check critical ports
echo ""
echo "=== Port Status ==="
critical_ports=(8545 8546 8547 8548 8549 8443)
for port in "${critical_ports[@]}"; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo -e "${GREEN}✓${NC} Port $port: Listening"
    else
        echo -e "${RED}✗${NC} Port $port: Not listening"
    fi
done

# Summary
echo ""
echo "=== Summary ==="
total_issues=$((failed_services + rpc_failed))

if [ $total_issues -eq 0 ]; then
    echo -e "${GREEN}✅ ALL SYSTEMS OPERATIONAL${NC}"
    echo "MEV infrastructure is ready for arbitrage operations"
    exit 0
else
    echo -e "${RED}❌ ISSUES DETECTED: $total_issues${NC}"
    echo "Failed services: $failed_services"
    echo "Failed RPC endpoints: $rpc_failed"
    echo ""
    echo "Action required for MEV operations!"
    exit 1
fi
