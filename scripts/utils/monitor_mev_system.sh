#!/bin/bash

# MEV System Monitoring Script
# Checks status of all MEV components

PID_DIR="/data/blockchain/nodes/pids"
LOG_FILE="/data/blockchain/nodes/logs/mev_system_status.log"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_component() {
    local name="$1"
    local pid_file="$2"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}✅ $name (PID: $pid)${NC}"
            return 0
        else
            echo -e "${RED}❌ $name (Dead)${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ $name (Not started)${NC}"
        return 1
    fi
}

main() {
    echo "MEV System Status Check - $(date)"
    echo "=================================="
    
    local total=0
    local running=0
    
    components=(
        "Cross-Chain MEV Engine:$PID_DIR/crosschain_mev.pid"
        "Bridge Monitor:$PID_DIR/bridge_monitor.pid"
        "Mempool Monitor:$PID_DIR/mempool_monitor.pid"
        "Strategy Engine:$PID_DIR/mev_strategies.pid"
        "MEV Backend:$PID_DIR/mev_backend.pid"
        "Analytics:$PID_DIR/mev_analytics.pid"
    )
    
    for component in "${components[@]}"; do
        IFS=':' read -r name pid_file <<< "$component"
        total=$((total + 1))
        if check_component "$name" "$pid_file"; then
            running=$((running + 1))
        fi
    done
    
    echo "=================================="
    echo -e "System Status: $running/$total components running"
    
    if [ $running -eq $total ]; then
        echo -e "${GREEN}🎉 All MEV components operational${NC}"
    elif [ $running -gt 0 ]; then
        echo -e "${YELLOW}⚠️ Partial system operation${NC}"
    else
        echo -e "${RED}🚨 System completely down${NC}"
    fi
    
    # Check Redis
    if pgrep redis-server > /dev/null; then
        echo -e "${GREEN}✅ Redis Server${NC}"
    else
        echo -e "${RED}❌ Redis Server${NC}"
    fi
    
    # Check disk space
    DISK_USAGE=$(df /data 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -lt 80 ]; then
        echo -e "${GREEN}✅ Disk Space (${DISK_USAGE}% used)${NC}"
    else
        echo -e "${YELLOW}⚠️ Disk Space (${DISK_USAGE}% used)${NC}"
    fi
    
    echo ""
}

if [ "$1" = "--watch" ]; then
    while true; do
        clear
        main
        sleep 10
    done
else
    main
fi
