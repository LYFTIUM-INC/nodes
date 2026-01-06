#\!/bin/bash
# MEV Alert Script - Run via cron every 5 minutes

LOG_FILE="/var/log/mev-alerts.log"
ALERT_THRESHOLD_BLOCKS=10

# Check if MEV-Boost is running
if \! systemctl is-active mev-boost >/dev/null 2>&1; then
    echo "[$(date)] CRITICAL: MEV-Boost is not running\!" >> "$LOG_FILE"
    # Send alert (implement your notification method here)
fi

# Check if we're missing blocks
CURRENT_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545  < /dev/null |  jq -r '.result' | xargs printf "%d\n" 2>/dev/null || echo "0")

if [ -f "/tmp/last_mev_block" ]; then
    LAST_BLOCK=$(cat /tmp/last_mev_block)
    BLOCKS_DIFF=$((CURRENT_BLOCK - LAST_BLOCK))
    
    if [ $BLOCKS_DIFF -gt $ALERT_THRESHOLD_BLOCKS ]; then
        echo "[$(date)] WARNING: Large block gap detected: $BLOCKS_DIFF blocks" >> "$LOG_FILE"
    fi
fi

echo "$CURRENT_BLOCK" > /tmp/last_mev_block
