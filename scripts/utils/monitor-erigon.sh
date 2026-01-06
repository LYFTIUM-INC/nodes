#!/bin/bash
# Erigon Health Monitor for MEV Operations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Erigon Health Check for MEV Operations"
echo "=========================================="
echo ""

# Check if service is running
if systemctl is-active --quiet erigon-fixed.service; then
    echo -e "${GREEN}✓ Service Status: RUNNING${NC}"
else
    echo -e "${RED}✗ Service Status: NOT RUNNING${NC}"
    echo "  Run: sudo systemctl start erigon-fixed.service"
    exit 1
fi

# Check RPC endpoint
echo -n "Checking RPC endpoint (8545)... "
if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
    http://localhost:8545 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Available${NC}"
else
    echo -e "${RED}✗ Not responding${NC}"
fi

# Check WebSocket endpoint
echo -n "Checking WebSocket endpoint (8547)... "
if timeout 2 bash -c 'exec 3<>/dev/tcp/localhost/8547' 2>/dev/null; then
    echo -e "${GREEN}✓ Available${NC}"
else
    echo -e "${YELLOW}⚠ Not available yet${NC}"
fi

# Check Engine API for MEV
echo -n "Checking Engine API (8551)... "
if timeout 2 bash -c 'exec 3<>/dev/tcp/localhost/8551' 2>/dev/null; then
    echo -e "${GREEN}✓ Available${NC}"
else
    echo -e "${YELLOW}⚠ Not available yet${NC}"
fi

# Check sync status
echo ""
echo "Sync Status:"
SYNC_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null)

if [ -n "$SYNC_STATUS" ]; then
    if echo "$SYNC_STATUS" | grep -q "false"; then
        echo -e "${GREEN}✓ Fully synced${NC}"
    else
        echo -e "${YELLOW}⚠ Syncing in progress${NC}"
        echo "$SYNC_STATUS" | jq -r '.result | "  Current Block: \(.currentBlock // "N/A")\n  Highest Block: \(.highestBlock // "N/A")"' 2>/dev/null || echo "  Unable to parse sync status"
    fi
else
    echo -e "${YELLOW}⚠ Unable to check sync status${NC}"
fi

# Check for lock file issues
echo ""
echo "Lock Files:"
if [ -f /data/blockchain/storage/erigon/LOCK ]; then
    echo -e "${GREEN}✓ Database lock present (normal)${NC}"
else
    echo -e "${YELLOW}⚠ No database lock file${NC}"
fi

# Check disk space
echo ""
echo "Disk Space:"
DISK_USAGE=$(df -h /data/blockchain/storage/erigon | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "${GREEN}✓ Disk usage: ${DISK_USAGE}%${NC}"
elif [ "$DISK_USAGE" -lt 90 ]; then
    echo -e "${YELLOW}⚠ Disk usage: ${DISK_USAGE}% (getting full)${NC}"
else
    echo -e "${RED}✗ Disk usage: ${DISK_USAGE}% (critical)${NC}"
fi

# Check recent logs for errors
echo ""
echo "Recent Log Activity:"
ERROR_COUNT=$(tail -n 100 /var/log/erigon/erigon.log 2>/dev/null | grep -c "EROR\|ERROR" || echo 0)
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ No recent errors${NC}"
else
    echo -e "${YELLOW}⚠ Found $ERROR_COUNT errors in recent logs${NC}"
    echo "  Recent errors:"
    tail -n 100 /var/log/erigon/erigon.log 2>/dev/null | grep -E "EROR|ERROR" | tail -3 | sed 's/^/  /'
fi

echo ""
echo "=========================================="
echo "MEV Readiness:"
if systemctl is-active --quiet erigon-fixed.service && \
   curl -s http://localhost:8545 > /dev/null 2>&1 && \
   timeout 2 bash -c 'exec 3<>/dev/tcp/localhost/8551' 2>/dev/null; then
    echo -e "${GREEN}✓ Erigon is ready for MEV operations${NC}"
else
    echo -e "${YELLOW}⚠ Erigon is starting up, please wait...${NC}"
fi
echo "=========================================="