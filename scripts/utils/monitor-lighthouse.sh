#!/bin/bash

# Lighthouse Beacon Node Monitoring Script
# Real-time monitoring of sync status, peers, and performance

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# API endpoints
BEACON_API="http://localhost:5052"
METRICS_API="http://localhost:5053/metrics"
ERIGON_API="http://localhost:8545"

# Clear screen function
clear_screen() {
    printf "\033[2J\033[H"
}

# Get beacon node status
get_beacon_status() {
    local health=$(docker exec lighthouse-beacon curl -s ${BEACON_API}/eth/v1/node/health 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "Healthy"
    else
        echo "Unhealthy"
    fi
}

# Get sync status
get_sync_status() {
    local sync_data=$(docker exec lighthouse-beacon curl -s ${BEACON_API}/eth/v1/node/syncing 2>/dev/null)
    if [ -z "$sync_data" ]; then
        echo "Unknown|0|0|0"
        return
    fi
    
    local is_syncing=$(echo "$sync_data" | jq -r '.data.is_syncing // true')
    local head_slot=$(echo "$sync_data" | jq -r '.data.head_slot // 0')
    local sync_distance=$(echo "$sync_data" | jq -r '.data.sync_distance // 0')
    local current_slot=$(echo "$sync_data" | jq -r '.data.current_slot // 0')
    
    if [ "$is_syncing" = "false" ]; then
        echo "Synced|$head_slot|$sync_distance|$current_slot"
    else
        echo "Syncing|$head_slot|$sync_distance|$current_slot"
    fi
}

# Get peer information
get_peer_info() {
    local peer_data=$(docker exec lighthouse-beacon curl -s ${BEACON_API}/eth/v1/node/peer_count 2>/dev/null)
    if [ -z "$peer_data" ]; then
        echo "0|0|0|0"
        return
    fi
    
    local connected=$(echo "$peer_data" | jq -r '.data.connected // 0')
    local connecting=$(echo "$peer_data" | jq -r '.data.connecting // 0')
    local disconnected=$(echo "$peer_data" | jq -r '.data.disconnected // 0')
    local disconnecting=$(echo "$peer_data" | jq -r '.data.disconnecting // 0')
    
    echo "$connected|$connecting|$disconnected|$disconnecting"
}

# Get version info
get_version_info() {
    local version_data=$(docker exec lighthouse-beacon curl -s ${BEACON_API}/eth/v1/node/version 2>/dev/null)
    if [ -z "$version_data" ]; then
        echo "Unknown"
        return
    fi
    
    echo "$version_data" | jq -r '.data.version // "Unknown"' | cut -d'/' -f2
}

# Get finality checkpoints
get_finality_checkpoints() {
    local finality_data=$(docker exec lighthouse-beacon curl -s ${BEACON_API}/eth/v1/beacon/states/head/finality_checkpoints 2>/dev/null)
    if [ -z "$finality_data" ]; then
        echo "0|0|0"
        return
    fi
    
    local current_justified=$(echo "$finality_data" | jq -r '.data.current_justified.epoch // 0')
    local finalized=$(echo "$finality_data" | jq -r '.data.finalized.epoch // 0')
    local previous_justified=$(echo "$finality_data" | jq -r '.data.previous_justified.epoch // 0')
    
    echo "$current_justified|$finalized|$previous_justified"
}

# Get resource usage
get_resource_usage() {
    local stats=$(docker stats lighthouse-beacon --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}" 2>/dev/null | head -n1)
    if [ -z "$stats" ]; then
        echo "0%|0/0|0/0"
        return
    fi
    echo "$stats"
}

# Get execution client status
get_execution_status() {
    local block_number=$(docker exec erigon curl -s -X POST ${ERIGON_API} \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
        jq -r '.result // "0x0"' | xargs printf "%d\n" 2>/dev/null || echo "0")
    
    local syncing=$(docker exec erigon curl -s -X POST ${ERIGON_API} \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null | \
        jq -r '.result')
    
    if [ "$syncing" = "false" ] || [ "$syncing" = "null" ]; then
        echo "Synced|$block_number"
    else
        local current_block=$(echo "$syncing" | jq -r '.currentBlock // "0x0"' | xargs printf "%d\n" 2>/dev/null || echo "0")
        local highest_block=$(echo "$syncing" | jq -r '.highestBlock // "0x0"' | xargs printf "%d\n" 2>/dev/null || echo "0")
        echo "Syncing|$current_block/$highest_block"
    fi
}

# Format slot time
format_slot_time() {
    local slots=$1
    local seconds=$((slots * 12))
    local minutes=$((seconds / 60))
    local hours=$((minutes / 60))
    local days=$((hours / 24))
    
    if [ $days -gt 0 ]; then
        echo "${days}d ${hours%24}h"
    elif [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes%60}m"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m"
    else
        echo "${seconds}s"
    fi
}

# Main monitoring loop
monitor_loop() {
    while true; do
        clear_screen
        
        # Header
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           LIGHTHOUSE BEACON NODE MONITORING DASHBOARD            ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo
        
        # Version and Status
        local version=$(get_version_info)
        local beacon_status=$(get_beacon_status)
        local status_color=$GREEN
        if [ "$beacon_status" != "Healthy" ]; then
            status_color=$RED
        fi
        
        echo -e "${BLUE}Node Information:${NC}"
        echo -e "  Version: ${YELLOW}Lighthouse $version${NC}"
        echo -e "  Status:  ${status_color}$beacon_status${NC}"
        echo
        
        # Sync Status
        IFS='|' read -r sync_status head_slot sync_distance current_slot <<< "$(get_sync_status)"
        local sync_color=$GREEN
        if [ "$sync_status" = "Syncing" ]; then
            sync_color=$YELLOW
        fi
        
        echo -e "${BLUE}Sync Status:${NC}"
        echo -e "  State:          ${sync_color}$sync_status${NC}"
        echo -e "  Current Slot:   $current_slot"
        echo -e "  Head Slot:      $head_slot"
        if [ "$sync_distance" -gt 0 ]; then
            local time_behind=$(format_slot_time $sync_distance)
            echo -e "  Sync Distance:  ${YELLOW}$sync_distance slots ($time_behind behind)${NC}"
            
            # Calculate sync progress
            if [ "$current_slot" -gt 0 ] && [ "$head_slot" -gt 0 ]; then
                local progress=$(awk "BEGIN {printf \"%.2f\", ($head_slot / $current_slot) * 100}")
                echo -e "  Sync Progress:  ${YELLOW}$progress%${NC}"
            fi
        fi
        echo
        
        # Finality Checkpoints
        IFS='|' read -r current_justified finalized previous_justified <<< "$(get_finality_checkpoints)"
        echo -e "${BLUE}Finality Checkpoints:${NC}"
        echo -e "  Finalized Epoch:         $finalized"
        echo -e "  Current Justified Epoch: $current_justified"
        echo -e "  Previous Justified Epoch: $previous_justified"
        echo
        
        # Peer Information
        IFS='|' read -r connected connecting disconnected disconnecting <<< "$(get_peer_info)"
        local peer_color=$GREEN
        if [ "$connected" -lt 10 ]; then
            peer_color=$YELLOW
        elif [ "$connected" -lt 5 ]; then
            peer_color=$RED
        fi
        
        echo -e "${BLUE}Network Peers:${NC}"
        echo -e "  Connected:     ${peer_color}$connected${NC}"
        echo -e "  Connecting:    $connecting"
        echo -e "  Disconnected:  $disconnected"
        echo -e "  Disconnecting: $disconnecting"
        echo
        
        # Execution Client Status
        IFS='|' read -r exec_status exec_info <<< "$(get_execution_status)"
        local exec_color=$GREEN
        if [ "$exec_status" = "Syncing" ]; then
            exec_color=$YELLOW
        fi
        
        echo -e "${BLUE}Execution Client (Erigon):${NC}"
        echo -e "  Status: ${exec_color}$exec_status${NC}"
        echo -e "  Block:  $exec_info"
        echo
        
        # Resource Usage
        IFS='|' read -r cpu_usage mem_usage net_io <<< "$(get_resource_usage)"
        echo -e "${BLUE}Resource Usage:${NC}"
        echo -e "  CPU:     $cpu_usage"
        echo -e "  Memory:  $mem_usage"
        echo -e "  Network: $net_io"
        echo
        
        # Footer
        echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
        echo -e "Press ${YELLOW}Ctrl+C${NC} to exit | Refreshing every 5 seconds..."
        
        sleep 5
    done
}

# Check if containers are running
check_containers() {
    if ! docker ps | grep -q lighthouse-beacon; then
        echo -e "${RED}Error: Lighthouse beacon container is not running${NC}"
        echo "Please run deploy-lighthouse.sh first"
        exit 1
    fi
    
    if ! docker ps | grep -q erigon; then
        echo -e "${YELLOW}Warning: Erigon container is not running${NC}"
        echo "Some metrics may be unavailable"
    fi
}

# Main execution
main() {
    check_containers
    
    # Trap Ctrl+C
    trap 'echo -e "\n${GREEN}Monitoring stopped${NC}"; exit 0' INT
    
    # Start monitoring
    monitor_loop
}

# Run main function
main "$@"