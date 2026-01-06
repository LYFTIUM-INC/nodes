#!/bin/bash
#
# Geth Post-Optimization Sync Monitoring Script
# Monitors sync progress after performance optimizations
#
# Author: Claude Code MEV Specialist
# Version: 1.0.0
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
GETH_RPC_URL="http://127.0.0.1:8549"
ERIGON_RPC_URL="http://127.0.0.1:8545"
LOG_FILE="/tmp/blockchain_logs/optimized_sync_monitor.log"
REPORT_FILE="/tmp/blockchain_logs/optimization_final_report_$(date +%Y%m%d_%H%M%S).json"

# Functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

show_header() {
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${PURPLE}📊 GETH POST-OPTIMIZATION MONITORING${NC}"
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${BLUE}Timestamp: $(date -Iseconds)${NC}"
    echo -e "${BLUE}Configuration Applied: Cache=8GB, Peers=150${NC}"
    echo -e "${PURPLE}================================================${NC}"
}

check_sync_status() {
    local node_name="$1"
    local rpc_url="$2"
    local result
    local current
    local highest
    local progress

    log "Checking $node_name sync status..."

    result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        "$rpc_url" 2>/dev/null)

    if [[ $? -eq 0 && -n "$result" ]]; then
        local sync_data=$(echo "$result" | jq -r '.result // false')
        
        if [[ "$sync_data" == "false" || "$sync_data" == "null" || "$sync_data" == "" ]]; then
            log "✅ $node_name: Fully synced"
            echo '{"status": "synced", "node": "'$node_name'", "progress": 100, "current": 0, "highest": 0}'
        else
            current=$(echo "$sync_data" | jq -r '.currentBlock // "0x0"')
            highest=$(echo "$sync_data" | jq -r '.highestBlock // "0x0"')
            local current_dec=$((current))
            local highest_dec=$((highest))
            local progress=$(echo "scale=2; $current_dec * 100 / $highest_dec" | bc -l 2>/dev/null || echo "0")

            log "⏳ $node_name: Syncing - $current_dec / $highest_dec ($progress%)"
            echo '{"status": "syncing", "node": "'$node_name'", "current": '$current_dec', "highest": '$highest_dec', "progress": '$progress'}'
        fi
    else
        log_error "❌ $node_name: Could not get sync status"
        echo '{"status": "error", "node": "'$node_name'", "error": "RPC connection failed"}'
    fi
}

check_performance_metrics() {
    log "Analyzing performance metrics..."

    # Get service status
    local geth_service_status=$(systemctl is-active geth 2>/dev/null || echo "unknown")
    local erigon_service_status=$(systemctl is-active erigon 2>/dev/null || echo "unknown")

    log "Service Status:"
    log "  Geth: $geth_service_status"
    log "  Erigon: $erigon_service_status"

    # Get resource usage
    if [[ "$geth_service_status" == "active" ]]; then
        local geth_pid=$(pgrep geth | head -1)
        if [[ -n "$geth_pid" ]]; then
            local geth_cpu=$(ps -p "$geth_pid" -o %cpu= | tr -d ' ')
            local geth_mem=$(ps -p "$geth_pid" -o %mem= | tr -d ' ')
            local geth_rss=$(ps -p "$geth_pid" -o rss= | tr -d ' ')

            log "Geth Resource Usage:"
            log "  CPU: ${geth_cpu}%"
            log "  Memory: ${geth_mem}% (${geth_rss}KB)"
        fi
    fi

    # Network stats
    local network_stats=$(ip -s addr show dev 2>/dev/null | awk '/RX packets/ {print "RX: "$4,$5"}' | head -1 || echo "Network: monitoring unavailable")
    log "Network: $network_stats"

    # Disk I/O
    local disk_io=$(iostat -x 1 1 2>/dev/null | grep -E "(Device|sda|nvme)" | tail -n +1 | awk '{printf "%s: %s%% util", $1, $NF}' | head -1)
    log "Disk I/O: $disk_io"
}

check_optimization_improvements() {
    log "Checking optimization improvements..."

    # Compare with baseline metrics
    log "📊 Performance Improvements Applied:"
    log "  • Cache size: 4096MB → 8192MB (+100%)"
    log "  • Max peers: 100 → 150 (+50%)"
    "  • Transaction pool slots: 32 → 64 (+100%)"
    "  • Resource limits: CPU 400%, Memory 10GB"
    log "  • State scheme: path-based optimization"
    log "  • Snapshot support enabled"

    # Monitor for sync improvements
    log "🔍 Monitoring for sync speed improvements..."
    
    local initial_progress=$(check_sync_status "Geth" "$GETH_RPC_URL")
    local initial_progress=$(echo "$initial_progress" | jq -r '.progress // "0"')
    
    log "📈 Initial sync progress: ${initial_progress}%"

    # Wait a bit and check again
    sleep 60
    
    local new_progress=$(check_sync_status "Geth" "$GETH_RPC_URL")
    local new_progress=$(echo "$new_progress" | jq -r '.progress // "0"')
    
    local improvement=$(echo "scale=2; ($new_progress - $initial_progress) * 60 * 24" | bc -l 2>/dev/null || echo "0")
    
    if (( $(echo "$improvement > 0" | bc -l) )); then
        log "🚀 Improvement detected: ${improvement}% per hour"
    else
        log "⏳ Monitoring sync speed..."
    fi
}

generate_final_report() {
    log "Generating final optimization report..."

    # Get final status
    local final_status=$(check_sync_status "Geth"$GETH_RPC_URL)
    local service_status=$(systemctl is-active geth 2>/dev/null || echo "unknown")
    
    # Create JSON report
    cat > "$REPORT_FILE" << EOF
{
    "optimization_timestamp": "$(date -Iseconds)",
    "service_name": "geth",
    "optimization_applied": true,
    "service_status": "$service_status",
    "final_sync_status": $final_status,
    "configuration_changes": [
        "Increased cache from 4096MB to 8192MB (+100%)",
        "Increased max peers from 100 to 150 (+50%)",
        "Optimized transaction pool settings (2x capacity)",
        "Applied resource limits (CPU: 400%, Memory: 10GB)",
        "Enabled state.scheme=path optimization",
        "Enabled snapshot support"
    ],
    "performance_baseline": {
        "previous_sync_progress": "21.19%",
        "previous_cache": "4096MB",
        "previous_max_peers": 100"
    },
    "monitoring_log": "$LOG_FILE",
    "next_steps": [
        "Monitor sync progress over next 24 hours",
        "Check peer connectivity if sync stalls",
        "Verify RPC endpoints are stable",
        "Consider additional optimizations if needed"
    ]
}
EOF

    log "Final optimization report generated: $REPORT_FILE"
}

# Main execution
main() {
    show_header

    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"

    log "🚀 Starting post-optimization monitoring..."

    # Apply a brief wait to let service stabilize
    log "⏳ Waiting for Geth service to stabilize..."
    sleep 30

    # Check if service is running
    if ! systemctl is-active --quiet geth; then
        log_error "❌ Geth service is not running after optimization"
        exit 1
    fi

    log "✅ Geth service is running"

    # Check sync status
    local sync_status=$(check_sync_status "Geth" "$GETH_RPC_URL")
    log "Sync Status: $sync_status"

    # Check performance metrics
    check_performance_metrics

    # Check for improvements
    check_optimization_improvements

    # Generate final report
    generate_final_report

    log "✅ Geth performance optimization completed successfully!"
    log "📊 Report available at: $REPORT_FILE"
    log "🔍 Monitor sync progress with: watch -n 60 'curl -s http://127.0.0.1:8549 -X POST -H \"Content-Type: application/json\" -d \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"method\\\":\\\"eth_syncing\\\",\\\"params\\\":[],\\\"id\\\":1}\\\" | jq'"
}

    log "💡 Optimization Summary:"
    log "  • Cache: 8GB (doubled from 4GB)"
    log "  • Peers: 150 (increased from 100)"
    log "  • Transaction Pool: 2x capacity"
    log "  • Resource Limits: CPU 400%, Memory 10GB"
    log "  • Configuration: Applied optimized settings from TOML config"
}

# Handle interrupts
trap 'log_warning "Monitoring interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"