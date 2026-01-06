#!/bin/bash

# Polygon Health Check Script
# Comprehensive monitoring for MEV operations

set -e

# Configuration
BOR_RPC_URL="http://localhost:8548"
BOR_WS_URL="ws://localhost:8550"
HEIMDALL_API_URL="http://localhost:1317"
METRICS_URL="http://localhost:6061/metrics"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Status tracking
OVERALL_STATUS="healthy"
ISSUES=()

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    ISSUES+=("WARNING: $1")
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ISSUES+=("ERROR: $1")
    OVERALL_STATUS="unhealthy"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Test HTTP endpoint
test_http() {
    local url=$1
    local timeout=${2:-10}
    
    if curl -s --max-time "$timeout" "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Test JSON-RPC endpoint
test_jsonrpc() {
    local url=$1
    local method=$2
    local params=${3:-"[]"}
    local timeout=${4:-10}
    
    local response=$(curl -s --max-time "$timeout" -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$url" 2>/dev/null)
    
    if [ -n "$response" ] && echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        echo "$response" | jq -r '.result'
        return 0
    else
        return 1
    fi
}

# Check service status
check_service_status() {
    log_info "Checking service status..."
    
    # Check systemd services
    for service in polygon-heimdall polygon-bor; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is running"
        else
            log_error "$service is not running"
        fi
    done
}

# Check process status
check_process_status() {
    log_info "Checking process status..."
    
    # Check Heimdall process
    if pgrep -f "heimdall" >/dev/null; then
        local heimdall_pid=$(pgrep -f "heimdall" | head -1)
        local heimdall_mem=$(ps -o rss= -p "$heimdall_pid" 2>/dev/null | tr -d ' ')
        local heimdall_mem_mb=$((heimdall_mem / 1024))
        log_success "Heimdall process running (PID: $heimdall_pid, Memory: ${heimdall_mem_mb}MB)"
    else
        log_error "Heimdall process not found"
    fi
    
    # Check Bor process
    if pgrep -f "bor" >/dev/null; then
        local bor_pid=$(pgrep -f "bor" | head -1)
        local bor_mem=$(ps -o rss= -p "$bor_pid" 2>/dev/null | tr -d ' ')
        local bor_mem_mb=$((bor_mem / 1024))
        log_success "Bor process running (PID: $bor_pid, Memory: ${bor_mem_mb}MB)"
    else
        log_error "Bor process not found"
    fi
}

# Check network connectivity
check_network() {
    log_info "Checking network connectivity..."
    
    # Check if ports are listening
    local ports=("8548" "8550" "1317" "6061" "26657" "30305")
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            log_success "Port $port is listening"
        else
            log_warning "Port $port is not listening"
        fi
    done
}

# Check Heimdall health
check_heimdall() {
    log_info "Checking Heimdall health..."
    
    # Test API endpoint
    if test_http "$HEIMDALL_API_URL/status"; then
        log_success "Heimdall API is responding"
        
        # Get detailed status
        local status_response=$(curl -s "$HEIMDALL_API_URL/status")
        
        if [ -n "$status_response" ]; then
            local catching_up=$(echo "$status_response" | jq -r '.result.sync_info.catching_up' 2>/dev/null)
            local latest_block_height=$(echo "$status_response" | jq -r '.result.sync_info.latest_block_height' 2>/dev/null)
            local latest_block_time=$(echo "$status_response" | jq -r '.result.sync_info.latest_block_time' 2>/dev/null)
            
            if [ "$catching_up" = "false" ]; then
                log_success "Heimdall is fully synced (Block: $latest_block_height)"
            elif [ "$catching_up" = "true" ]; then
                log_warning "Heimdall is still syncing (Block: $latest_block_height)"
            else
                log_warning "Unable to determine Heimdall sync status"
            fi
            
            # Check if block time is recent (within last 10 minutes)
            if [ -n "$latest_block_time" ]; then
                local block_timestamp=$(date -d "$latest_block_time" +%s 2>/dev/null || echo 0)
                local current_timestamp=$(date +%s)
                local time_diff=$((current_timestamp - block_timestamp))
                
                if [ $time_diff -lt 600 ]; then  # 10 minutes
                    log_success "Heimdall block time is recent (${time_diff}s ago)"
                else
                    log_warning "Heimdall block time is old (${time_diff}s ago)"
                fi
            fi
        fi
    else
        log_error "Heimdall API is not responding"
    fi
}

# Check Bor health
check_bor() {
    log_info "Checking Bor health..."
    
    # Test RPC endpoint
    if test_http "$BOR_RPC_URL"; then
        log_success "Bor RPC is responding"
        
        # Check network ID
        local network_id=$(test_jsonrpc "$BOR_RPC_URL" "net_version")
        if [ "$network_id" = "137" ]; then
            log_success "Connected to Polygon Mainnet (Chain ID: $network_id)"
        else
            log_warning "Unexpected network ID: $network_id"
        fi
        
        # Check current block number
        local block_number_hex=$(test_jsonrpc "$BOR_RPC_URL" "eth_blockNumber")
        if [ -n "$block_number_hex" ]; then
            local block_number=$((block_number_hex))
            log_success "Current block number: $block_number"
            
            # Check if we're syncing
            local sync_status=$(test_jsonrpc "$BOR_RPC_URL" "eth_syncing")
            if [ "$sync_status" = "false" ]; then
                log_success "Bor is fully synced"
            else
                log_warning "Bor is still syncing"
            fi
        else
            log_error "Unable to get current block number"
        fi
        
        # Check peer count
        local peer_count_hex=$(test_jsonrpc "$BOR_RPC_URL" "net_peerCount")
        if [ -n "$peer_count_hex" ]; then
            local peer_count=$((peer_count_hex))
            if [ $peer_count -gt 0 ]; then
                log_success "Connected to $peer_count peers"
            else
                log_warning "No peers connected"
            fi
        else
            log_warning "Unable to get peer count"
        fi
        
        # Check if mining (should be false for our setup)
        local mining=$(test_jsonrpc "$BOR_RPC_URL" "eth_mining")
        if [ "$mining" = "false" ]; then
            log_success "Mining is disabled (as expected)"
        elif [ "$mining" = "true" ]; then
            log_warning "Mining is enabled (unexpected for MEV node)"
        fi
        
        # Test transaction pool
        local txpool_status=$(test_jsonrpc "$BOR_RPC_URL" "txpool_status")
        if [ -n "$txpool_status" ]; then
            log_success "Transaction pool is accessible"
        else
            log_warning "Unable to access transaction pool"
        fi
        
    else
        log_error "Bor RPC is not responding"
    fi
    
    # Test WebSocket endpoint
    if command_exists websocat; then
        echo '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' | \
        timeout 5 websocat "$BOR_WS_URL" >/dev/null 2>&1 && \
        log_success "Bor WebSocket is responding" || \
        log_warning "Bor WebSocket is not responding or websocat not available"
    else
        log_info "Skipping WebSocket test (websocat not installed)"
    fi
}

# Check disk space
check_disk_space() {
    log_info "Checking disk space..."
    
    local data_dir="/data/blockchain/nodes/polygon"
    
    if [ -d "$data_dir" ]; then
        local available_space=$(df -BG "$data_dir" | tail -1 | awk '{print $4}' | sed 's/G//')
        local used_space=$(df -BG "$data_dir" | tail -1 | awk '{print $3}' | sed 's/G//')
        local total_space=$(df -BG "$data_dir" | tail -1 | awk '{print $2}' | sed 's/G//')
        local usage_pct=$(df "$data_dir" | tail -1 | awk '{print $5}' | sed 's/%//')
        
        log_success "Disk usage: ${used_space}GB / ${total_space}GB (${usage_pct}%) - Available: ${available_space}GB"
        
        if [ $usage_pct -gt 90 ]; then
            log_error "Disk usage is critical (${usage_pct}%)"
        elif [ $usage_pct -gt 80 ]; then
            log_warning "Disk usage is high (${usage_pct}%)"
        fi
        
        if [ $available_space -lt 50 ]; then
            log_warning "Low disk space available (${available_space}GB)"
        fi
    else
        log_error "Data directory not found: $data_dir"
    fi
}

# Check memory usage
check_memory() {
    log_info "Checking memory usage..."
    
    local total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local available_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local used_mem=$((total_mem - available_mem))
    local usage_pct=$((used_mem * 100 / total_mem))
    
    local total_gb=$((total_mem / 1024 / 1024))
    local used_gb=$((used_mem / 1024 / 1024))
    local available_gb=$((available_mem / 1024 / 1024))
    
    log_success "Memory usage: ${used_gb}GB / ${total_gb}GB (${usage_pct}%) - Available: ${available_gb}GB"
    
    if [ $usage_pct -gt 90 ]; then
        log_error "Memory usage is critical (${usage_pct}%)"
    elif [ $usage_pct -gt 80 ]; then
        log_warning "Memory usage is high (${usage_pct}%)"
    fi
}

# Check metrics endpoint
check_metrics() {
    log_info "Checking metrics endpoint..."
    
    if test_http "$METRICS_URL"; then
        log_success "Metrics endpoint is responding"
        
        # Get some basic metrics
        local metrics_response=$(curl -s "$METRICS_URL" 2>/dev/null)
        if [ -n "$metrics_response" ]; then
            local metric_count=$(echo "$metrics_response" | grep -c "^[a-zA-Z]" || echo 0)
            log_success "Metrics available: $metric_count metrics"
        fi
    else
        log_warning "Metrics endpoint is not responding"
    fi
}

# Generate summary report
generate_summary() {
    echo ""
    echo -e "${BLUE}=== HEALTH CHECK SUMMARY ===${NC}"
    echo "Timestamp: $(date)"
    echo "Overall Status: $OVERALL_STATUS"
    
    if [ ${#ISSUES[@]} -eq 0 ]; then
        echo -e "Status: ${GREEN}All systems operational${NC}"
    else
        echo -e "Status: ${RED}Issues detected${NC}"
        echo ""
        echo "Issues found:"
        for issue in "${ISSUES[@]}"; do
            echo "  - $issue"
        done
    fi
    
    echo ""
    echo -e "${BLUE}=== QUICK REFERENCE ===${NC}"
    echo "Bor RPC: $BOR_RPC_URL"
    echo "Bor WebSocket: $BOR_WS_URL"
    echo "Heimdall API: $HEIMDALL_API_URL"
    echo "Metrics: $METRICS_URL"
    echo ""
    echo "Service management:"
    echo "  sudo systemctl status polygon-heimdall polygon-bor"
    echo "  sudo systemctl restart polygon-heimdall polygon-bor"
    echo "  sudo journalctl -f -u polygon-bor"
}

# Main execution
main() {
    echo -e "${BLUE}=== POLYGON NODE HEALTH CHECK ===${NC}"
    echo "Starting comprehensive health check..."
    echo ""
    
    check_service_status
    echo ""
    
    check_process_status
    echo ""
    
    check_network
    echo ""
    
    check_memory
    echo ""
    
    check_disk_space
    echo ""
    
    check_heimdall
    echo ""
    
    check_bor
    echo ""
    
    check_metrics
    
    generate_summary
    
    # Exit with appropriate code
    if [ "$OVERALL_STATUS" = "healthy" ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"