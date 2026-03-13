#!/bin/bash
# Lighthouse Health Monitoring Script
# Checks sync status, service health, and resource usage
# Usage: ./monitor-lighthouse-health.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
API_URL="http://localhost:5052"
SERVICE_NAME="lighthouse-beacon.service"

# Functions
print_header() {
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  LIGHTHOUSE BEACON NODE HEALTH CHECK${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
}

check_service() {
    echo -e "${YELLOW}[1/5] Service Status${NC}"
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "  Status: ${GREEN}✅ Running${NC}"
        UPTIME=$(systemctl show ${SERVICE_NAME} --property=ActiveEnterTimestamp | cut -d= -f2)
        echo -e "  Uptime: ${UPTIME}"
    else
        echo -e "  Status: ${RED}❌ Stopped${NC}"
        return 1
    fi
    echo ""
}

check_sync_status() {
    echo -e "${YELLOW}[2/5] Sync Status${NC}"
    
    SYNC_DATA=$(curl -s ${API_URL}/eth/v1/node/syncing 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$SYNC_DATA" ]]; then
        IS_SYNCING=$(echo "$SYNC_DATA" | jq -r '.data.is_syncing')
        HEAD_SLOT=$(echo "$SYNC_DATA" | jq -r '.data.head_slot')
        SYNC_DISTANCE=$(echo "$SYNC_DATA" | jq -r '.data.sync_distance')
        IS_OPTIMISTIC=$(echo "$SYNC_DATA" | jq -r '.data.is_optimistic')
        EL_OFFLINE=$(echo "$SYNC_DATA" | jq -r '.data.el_offline')
        
        echo -e "  Syncing: $([ "$IS_SYNCING" == "true" ] && echo "${YELLOW}Yes${NC}" || echo "${GREEN}No (Synced)${NC}")"
        echo -e "  Head Slot: ${GREEN}${HEAD_SLOT}${NC}"
        echo -e "  Slots Behind: $([ ${SYNC_DISTANCE:-999} -lt 10 ] && echo "${GREEN}${SYNC_DISTANCE}${NC}" || ([ ${SYNC_DISTANCE:-999} -lt 100 ] && echo "${YELLOW}${SYNC_DISTANCE}${NC}" || echo "${RED}${SYNC_DISTANCE}${NC}"))"
        echo -e "  Optimistic: $([ "$IS_OPTIMISTIC" == "true" ] && echo "${YELLOW}Yes${NC}" || echo "${GREEN}No${NC}")"
        echo -e "  EL Connected: $([ "$EL_OFFLINE" == "true" ] && echo "${RED}No${NC}" || echo "${GREEN}Yes${NC}")"
    else
        echo -e "  ${RED}❌ API not responding${NC}"
        return 1
    fi
    echo ""
}

check_peers() {
    echo -e "${YELLOW}[3/5] Peer Connectivity${NC}"
    
    PEER_COUNT=$(curl -s ${API_URL}/eth/v1/node/peer_count 2>/dev/null | jq -r '.data.connected' 2>/dev/null)
    
    if [[ -n "$PEER_COUNT" ]] && [[ "$PEER_COUNT" != "null" ]]; then
        echo -e "  Connected Peers: $([ ${PEER_COUNT:-0} -gt 50 ] && echo "${GREEN}${PEER_COUNT}${NC}" || ([ ${PEER_COUNT:-0} -gt 20 ] && echo "${YELLOW}${PEER_COUNT}${NC}" || echo "${RED}${PEER_COUNT}${NC}"))"
    else
        echo -e "  ${YELLOW}⚠️  Unable to fetch peer count${NC}"
    fi
    echo ""
}

check_resources() {
    echo -e "${YELLOW}[4/5] Resource Usage${NC}"
    
    # Get Lighthouse process info
    LIGHTHOUSE_PID=$(pgrep -f "lighthouse beacon_node" | head -1)
    
    if [[ -n "$LIGHTHOUSE_PID" ]]; then
        CPU_MEM=$(ps -p ${LIGHTHOUSE_PID} -o %cpu,%mem --no-headers)
        CPU=$(echo $CPU_MEM | awk '{print $1}')
        MEM=$(echo $CPU_MEM | awk '{print $2}')
        RSS=$(ps -p ${LIGHTHOUSE_PID} -o rss --no-headers)
        RSS_GB=$(echo "scale=2; ${RSS}/1024/1024" | bc)
        
        echo -e "  CPU: $([ $(echo "${CPU} < 100" | bc) -eq 1 ] && echo "${GREEN}${CPU}%${NC}" || echo "${YELLOW}${CPU}%${NC}")"
        echo -e "  Memory: $([ $(echo "${MEM} < 8" | bc) -eq 1 ] && echo "${GREEN}${MEM}%${NC}" || ([ $(echo "${MEM} < 12" | bc) -eq 1 ] && echo "${YELLOW}${MEM}%${NC}" || echo "${RED}${MEM}%${NC}"))"
        echo -e "  RSS: ${RSS_GB} GB"
    else
        echo -e "  ${RED}❌ Process not found${NC}"
    fi
    echo ""
}

check_database() {
    echo -e "${YELLOW}[5/5] Database Status${NC}"
    
    DB_PATH="/data/blockchain/nodes/consensus/lighthouse/beacon"
    
    if [[ -d "${DB_PATH}/chain_db" ]]; then
        DB_SIZE=$(du -sh ${DB_PATH} 2>/dev/null | awk '{print $1}')
        FILE_COUNT=$(find ${DB_PATH}/chain_db -name "*.ldb" 2>/dev/null | wc -l)
        
        echo -e "  Database Size: ${DB_SIZE}"
        echo -e "  Database Files: ${FILE_COUNT}"
        
        # Check for corruption indicators
        if ls ${DB_PATH}/chain_db/*.ldb 1>/dev/null 2>&1; then
            echo -e "  Status: ${GREEN}✅ Healthy${NC}"
        else
            echo -e "  Status: ${RED}❌ Possible corruption${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  Database not found (checkpoint sync in progress?)${NC}"
    fi
    echo ""
}

check_restart_loops() {
    echo -e "${YELLOW}[BONUS] Service Restarts${NC}"
    
    RESTART_COUNT=$(systemctl show ${SERVICE_NAME} --property=NRestarts | cut -d= -f2)
    
    if [[ ${RESTART_COUNT:-0} -eq 0 ]]; then
        echo -e "  Restarts: ${GREEN}0${NC} ✅"
    elif [[ ${RESTART_COUNT:-0} -lt 5 ]]; then
        echo -e "  Restarts: ${YELLOW}${RESTART_COUNT}${NC} ⚠️"
    else
        echo -e "  Restarts: ${RED}${RESTART_COUNT}${NC} ❌ (Check logs!)"
    fi
    echo ""
}

# Main execution
print_header
check_service
check_sync_status
check_peers
check_resources
check_database
check_restart_loops

echo -e "${GREEN}✅ Health check complete${NC}"
echo ""
