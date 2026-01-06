#!/bin/bash
# MEV Foundation Health Monitoring Script
# Provides comprehensive health checks for all services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOG_FILE="/data/blockchain/nodes/logs/health-monitor.log"
ALERT_THRESHOLD=3  # Number of consecutive failures before alert

# Service endpoints
RETH_HTTP="http://localhost:38545"
RETH_WS="ws://localhost:38546"
LIGHTHOUSE_BEACON="http://localhost:5052"
MEV_BOOST="http://localhost:28550"
RBUILDER="http://localhost:18552"

# Initialize log
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE")

# Health check functions
check_reth() {
    echo -e "${BLUE}🔍 Checking RETH...${NC}"
    
    # HTTP API check
    if curl -s -X POST -H "Content-Type: application/json" \
       -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
       "$RETH_HTTP" | grep -q "result"; then
        echo -e "  ${GREEN}✅ RETH HTTP API accessible${NC}"
        
        # Check sync status
        sync_result=$(curl -s -X POST -H "Content-Type: application/json" \
                          -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
                          "$RETH_HTTP" | jq -r '.result')
        
        if [ "$sync_result" = "false" ]; then
            echo -e "  ${GREEN}✅ RETH synced${NC}"
            
            # Get latest block
            block_number=$(curl -s -X POST -H "Content-Type: application/json" \
                              -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                              "$RETH_HTTP" | jq -r '.result')
            block_decimal=$((block_number))
            echo -e "  ${GREEN}📊 Latest block: $block_decimal${NC}"
        else
            echo -e "  ${YELLOW}⏳ RETH syncing...${NC}"
        fi
    else
        echo -e "  ${RED}❌ RETH HTTP API not accessible${NC}"
        return 1
    fi
    
    return 0
}

check_lighthouse() {
    echo -e "${BLUE}🔍 Checking Lighthouse...${NC}"
    
    # Beacon API check
    if curl -s -H "Content-Type: application/json" \
       "$LIGHTHOUSE_BEACON/eth/v1/beacon/genesis" | grep -q "genesis_time"; then
        echo -e "  ${GREEN}✅ Lighthouse Beacon API accessible${NC}"
        
        # Check sync status
        sync_status=$(curl -s -H "Content-Type: application/json" \
                        "$LIGHTHOUSE_BEACON/eth/v1/node/syncing" | jq -r '.data.is_syncing')
        
        if [ "$sync_status" = "false" ]; then
            echo -e "  ${GREEN}✅ Lighthouse synced${NC}"
        else
            echo -e "  ${YELLOW}⏳ Lighthouse syncing...${NC}"
        fi
        
        # Get validator status
        validator_count=$(curl -s -H "Content-Type: application/json" \
                           "$LIGHTHOUSE_BEACON/eth/v1/beacon/validators" | jq '.data | length')
        echo -e "  ${GREEN}📊 Active validators: $validator_count${NC}"
    else
        echo -e "  ${RED}❌ Lighthouse Beacon API not accessible${NC}"
        return 1
    fi
    
    return 0
}

check_mev_boost() {
    echo -e "${BLUE}🔍 Checking MEV-Boost...${NC}"
    
    if curl -s "$MEV_BOOST/eth/v1/builder/status" | grep -q "relays"; then
        echo -e "  ${GREEN}✅ MEV-Boost API accessible${NC}"
        
        # Check relay connections
        relay_count=$(curl -s "$MEV_BOOST/eth/v1/builder/status" | jq '.relays | length')
        echo -e "  ${GREEN}📊 Active relays: $relay_count${NC}"
    else
        echo -e "  ${RED}❌ MEV-Boost API not accessible${NC}"
        return 1
    fi
    
    return 0
}

check_rbuilder() {
    echo -e "${BLUE}🔍 Checking RBuilder...${NC}"
    
    if curl -s "$RBUILDER/api/status" | grep -q "healthy"; then
        echo -e "  ${GREEN}✅ RBuilder API accessible${NC}"
        
        # Get builder info
        builder_status=$(curl -s "$RBUILDER/api/status" | jq -r '.status')
        echo -e "  ${GREEN}📊 Builder status: $builder_status${NC}"
    else
        echo -e "  ${RED}❌ RBuilder API not accessible${NC}"
        return 1
    fi
    
    return 0
}

check_docker_containers() {
    echo -e "${BLUE}🔍 Checking Docker containers...${NC}"
    
    containers=("reth-ethereum-mev" "lighthouse-mev-foundation" "mev-boost-foundation" "rbuilder-foundation")
    all_running=true
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "$container"; then
            status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | awk '{print $2,$3,$4}')
            echo -e "  ${GREEN}✅ $container: $status${NC}"
        else
            echo -e "  ${RED}❌ $container: not running${NC}"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        return 1
    fi
    
    return 0
}

check_disk_space() {
    echo -e "${BLUE}🔍 Checking disk space...${NC}"
    
    # Check blockchain data directory
    if [ -d "/data/blockchain" ]; then
        usage=$(du -sh /data/blockchain | cut -f1)
        echo -e "  ${GREEN}📊 Blockchain data usage: $usage${NC}"
    fi
    
    # Check available disk space
    available=$(df -h /data | tail -1 | awk '{print $4}')
    echo -e "  ${GREEN}📊 Available space: $available${NC}"
    
    # Check if disk space is low (<10GB)
    available_kb=$(df -k /data | tail -1 | awk '{print $4}')
    if [ "$available_kb" -lt 10485760 ]; then  # 10GB in KB
        echo -e "  ${RED}⚠️  Low disk space!${NC}"
        return 1
    fi
    
    return 0
}

check_network() {
    echo -e "${BLUE}🔍 Checking network connectivity...${NC}"
    
    # Check Docker network
    if docker network ls | grep -q "mev_foundation_network"; then
        echo -e "  ${GREEN}✅ MEV Foundation network exists${NC}"
    else
        echo -e "  ${RED}❌ MEV Foundation network missing${NC}"
        return 1
    fi
    
    # Check port availability
    ports=("38545" "38546" "38551" "5052" "28550" "18552")
    
    for port in "${ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            echo -e "  ${GREEN}✅ Port $port: listening${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Port $port: not listening${NC}"
        fi
    done
    
    return 0
}

generate_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file="/data/blockchain/nodes/reports/health-report-$(date '+%Y%m%d-%H%M%S').json"
    
    mkdir -p "$(dirname "$report_file")"
    
    # Create JSON report
    jq -n \
      --arg timestamp "$timestamp" \
      --arg reth_status "$(check_reth >/dev/null 2>&1 && echo "healthy" || echo "unhealthy")" \
      --arg lighthouse_status "$(check_lighthouse >/dev/null 2>&1 && echo "healthy" || echo "unhealthy")" \
      --arg mev_boost_status "$(check_mev_boost >/dev/null 2>&1 && echo "healthy" || echo "unhealthy")" \
      --arg rbuilder_status "$(check_rbuilder >/dev/null 2>&1 && echo "healthy" || echo "unhealthy")" \
      '{
        timestamp: $timestamp,
        services: {
          reth: { status: $reth_status },
          lighthouse: { status: $lighthouse_status },
          mev_boost: { status: $mev_boost_status },
          rbuilder: { status: $rbuilder_status }
        }
      }' > "$report_file"
    
    echo -e "${GREEN}📊 Health report saved to: $report_file${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}🏥 MEV Foundation Health Monitor${NC}"
    echo -e "${BLUE}=============================${NC}"
    echo ""
    
    local exit_code=0
    
    # Run all health checks
    check_docker_containers || exit_code=1
    check_network || exit_code=1
    check_reth || exit_code=1
    check_lighthouse || exit_code=1
    check_mev_boost || exit_code=1
    check_rbuilder || exit_code=1
    check_disk_space || exit_code=1
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ All systems healthy!${NC}"
    else
        echo -e "${RED}❌ Some systems require attention!${NC}"
    fi
    
    # Generate report
    generate_report
    
    echo ""
    echo -e "${BLUE}📋 Health check completed at $(date)${NC}"
    
    return $exit_code
}

# Handle command line arguments
case "${1:-full}" in
    "reth")
        check_reth
        ;;
    "lighthouse")
        check_lighthouse
        ;;
    "mev-boost")
        check_mev_boost
        ;;
    "rbuilder")
        check_rbuilder
        ;;
    "containers")
        check_docker_containers
        ;;
    "disk")
        check_disk_space
        ;;
    "network")
        check_network
        ;;
    "report")
        generate_report
        ;;
    "full"|*)
        main
        ;;
esac
