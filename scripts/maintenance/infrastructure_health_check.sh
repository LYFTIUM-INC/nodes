#!/bin/bash
# MEV Foundation Infrastructure Health Check
# Comprehensive monitoring script for all blockchain infrastructure components

set -euo pipefail

# Configuration
INFRASTRUCTURE_ROOT="/data/blockchain/nodes"
LOG_FILE="$INFRASTRUCTURE_ROOT/logs/current/health_check.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

# Health check functions
check_docker_service() {
    local service_name="$1"
    local description="$2"

    log "Checking $description..."

    if docker ps --format "table {{.Names}}" | grep -q "$service_name"; then
        echo -e "${GREEN}✅ $description is running${NC}"
        return 0
    else
        echo -e "${RED}❌ $description is not running${NC}"
        log "ERROR: $description ($service_name) is not running"
        return 1
    fi
}

check_api_endpoint() {
    local url="$1"
    local service_name="$2"
    local timeout="${3:-5}"

    log "Checking $service_name API endpoint: $url"

    if curl -s --max-time "$timeout" "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $service_name API is accessible${NC}"
        return 0
    else
        echo -e "${RED}❌ $service_name API is not accessible${NC}"
        log "ERROR: $service_name API endpoint $url is not accessible"
        return 1
    fi
}

check_sync_status() {
    local rpc_url="$1"
    local service_name="$2"

    log "Checking $service_name sync status..."

    local sync_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        "$rpc_url" 2>/dev/null || echo '{"error": "failed"}')

    if echo "$sync_result" | grep -q '"result":false'; then
        echo -e "${GREEN}✅ $service_name is synced${NC}"
        return 0
    elif echo "$sync_result" | grep -q '"result":true'; then
        echo -e "${YELLOW}⚠️  $service_name is syncing${NC}"
        log "INFO: $service_name is currently syncing"
        return 1
    else
        echo -e "${RED}❌ Unable to determine $service_name sync status${NC}"
        log "ERROR: Failed to check $service_name sync status"
        return 1
    fi
}

# Main health check function
main() {
    echo -e "${BLUE}=== MEV Foundation Infrastructure Health Check ===${NC}"
    echo -e "${BLUE}Timestamp: $TIMESTAMP${NC}"
    echo

    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"

    local failed_checks=0

    log "Starting comprehensive infrastructure health check..."

    # Check Docker services
    echo -e "\n${BLUE}--- Docker Services ---${NC}"
    check_docker_service "reth-ethereum-mev" "RETH Execution Client" || ((failed_checks++))
    check_docker_service "lighthouse-mev-foundation" "Lighthouse Consensus Client" || ((failed_checks++))
    check_docker_service "mev-boost-foundation" "MEV-Boost Service" || ((failed_checks++))
    check_docker_service "rbuilder-foundation" "RBuilder Service" || ((failed_checks++))

    # Check API endpoints
    echo -e "\n${BLUE}--- API Endpoints ---${NC}"
    check_api_endpoint "http://localhost:28545" "RETH RPC" 10 || ((failed_checks++))
    check_api_endpoint "http://localhost:5052/eth/v1/beacon/genesis" "Lighthouse Beacon API" 10 || ((failed_checks++))
    check_api_endpoint "http://localhost:28550/eth/v1/builder/status" "MEV-Boost API" 10 || ((failed_checks++))
    check_api_endpoint "http://localhost:18552/api/status" "RBuilder API" 10 || ((failed_checks++))

    # Check sync status
    echo -e "\n${BLUE}--- Sync Status ---${NC}"
    check_sync_status "http://localhost:28545" "RETH" || ((failed_checks++))

    # Summary
    echo -e "\n${BLUE}--- Health Check Summary ---${NC}"
    if [ "$failed_checks" -eq 0 ]; then
        echo -e "${GREEN}✅ All checks passed! Infrastructure is healthy.${NC}"
        log "SUCCESS: All health checks passed"
        exit 0
    else
        echo -e "${RED}❌ $failed_checks check(s) failed! Review the logs for details.${NC}"
        log "ERROR: $failed_checks health checks failed"
        exit 1
    fi
}

# Script execution
main "$@"
