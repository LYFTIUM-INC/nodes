#\!/bin/bash
# Automated Health Monitor for Blockchain Infrastructure
LOG_FILE="/data/blockchain/nodes/logs/health-monitor.log"

check_ethereum_progress() {
    local current_block=$(journalctl -u ethereum -n 1  < /dev/null |  grep "blk=" | tail -1 | grep -o "blk=[0-9]*" | cut -d'=' -f2)
    local block_rate=$(journalctl -u ethereum -n 1 | grep "blk/s" | grep -o "blk/s=[0-9.]*" | cut -d'=' -f2)
    echo "$(date): Ethereum at block $current_block, rate: ${block_rate} blk/s" >> $LOG_FILE
    
    if [[ "$block_rate" == "0.0" ]]; then
        echo "$(date): WARNING - Ethereum sync stalled" >> $LOG_FILE
    fi
}

check_arbitrum_proxy() {
    local response=$(curl -s -X POST http://127.0.0.1:8590 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
    if [[ $? -eq 0 ]]; then
        echo "$(date): Arbitrum proxy operational" >> $LOG_FILE
    else
        echo "$(date): ERROR - Arbitrum proxy failed" >> $LOG_FILE
    fi
}

check_memory_pressure() {
    local mem_percent=$(free | awk '/^Mem:/ {printf "%.1f", ($3/$2)*100}')
    echo "$(date): Memory usage: ${mem_percent}%" >> $LOG_FILE
    
    if (( $(echo "$mem_percent > 85" | bc -l) )); then
        echo "$(date): WARNING - High memory pressure: ${mem_percent}%" >> $LOG_FILE
    fi
}

# Run checks
check_ethereum_progress
check_arbitrum_proxy  
check_memory_pressure
