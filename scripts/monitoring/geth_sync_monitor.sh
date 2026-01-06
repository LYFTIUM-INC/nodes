#!/bin/bash
#
# Geth Sync Monitoring and Optimization Script
# Monitors Geth sync progress and suggests optimizations
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
LOG_FILE="/tmp/blockchain_logs/geth_monitor.log"
REPORT_FILE="/tmp/blockchain_logs/geth_sync_report_$(date +%Y%m%d_%H%M%S).json"

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
    echo -e "${PURPLE}🔍 GETH NODE MONITORING & OPTIMIZATION${NC}"
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${BLUE}Timestamp: $(date -Iseconds)${NC}"
    echo -e "${BLUE}Geth RPC: $GETH_RPC_URL${NC}"
    echo -e "${BLUE}Erigon RPC: $ERIGON_RPC_URL${NC}"
    echo -e "${PURPLE}================================================${NC}"
}

check_rpc_connectivity() {
    log "Checking RPC connectivity..."

    # Check Geth RPC
    local geth_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$GETH_RPC_URL" 2>/dev/null)

    if [[ $? -eq 0 && -n "$geth_result" ]]; then
        local geth_block=$(echo "$geth_result" | jq -r '.result // "0x0"')
        local geth_block_dec=$((geth_block))
        log "✅ Geth RPC connected - Block: $geth_block_dec"
    else
        log_error "❌ Geth RPC not responding"
        return 1
    fi

    # Check Erigon RPC
    local erigon_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$ERIGON_RPC_URL" 2>/dev/null)

    if [[ $? -eq 0 && -n "$erigon_result" ]]; then
        local erigon_block=$(echo "$erigon_result" | jq -r '.result // "0x0"')
        local erigon_block_dec=$((erigon_block))
        log "✅ Erigon RPC connected - Block: $erigon_block_dec"
    else
        log_error "❌ Erigon RPC not responding"
        return 1
    fi

    return 0
}

get_sync_status() {
    local rpc_url="$1"
    local node_name="$2"

    local sync_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        "$rpc_url" 2>/dev/null)

    if [[ $? -eq 0 && -n "$sync_result" ]]; then
        local sync_data=$(echo "$sync_result" | jq -r '.result // empty')

        if [[ "$sync_data" == "false" || "$sync_data" == "null" || "$sync_data" == "" ]]; then
            log "✅ $node_name: Fully synced"
            echo '{"status": "synced", "node": "'$node_name'", "progress": 100}'
        else
            local current=$(echo "$sync_data" | jq -r '.currentBlock // "0x0"')
            local highest=$(echo "$sync_data" | jq -r '.highestBlock // "0x0"')
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

analyze_sync_performance() {
    log "Analyzing sync performance..."

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

    if [[ "$erigon_service_status" == "active" ]]; then
        local erigon_pid=$(pgrep erigon | head -1)
        if [[ -n "$erigon_pid" ]]; then
            local erigon_cpu=$(ps -p "$erigon_pid" -o %cpu= | tr -d ' ')
            local erigon_mem=$(ps -p "$erigon_pid" -o %mem= | tr -d ' ')
            local erigon_rss=$(ps -p "$erigon_pid" -o rss= | tr -d ' ')

            log "Erigon Resource Usage:"
            log "  CPU: ${erigon_cpu}%"
            log "  Memory: ${erigon_mem}% (${erigon_rss}KB)"
        fi
    fi

    # Get disk I/O
    local disk_io=$(iostat -x 1 1 2>/dev/null | grep -E "(Device|sda|nvme)" | tail -n +1 | awk '{printf "%s: %s%% util", $1, $NF}' | head -1)
    log "Disk I/O: $disk_io"

    # Get network stats
    local network_stats=$(sar -n DEV 1 1 2>/dev/null | grep "Average:" | grep -E "(eth|ens)" | awk '{printf "RX: %.1fMB/s, TX: %.1fMB/s", $3/1024, $4/1024}' | head -1 || echo "Network: monitoring unavailable")
    log "Network: $network_stats"
}

check_sync_health() {
    log "Checking sync health indicators..."

    local issues=()
    local recommendations=()

    # Check if Geth is syncing
    local geth_sync=$(get_sync_status "$GETH_RPC_URL" "Geth")
    local geth_status=$(echo "$geth_sync" | jq -r '.status // "unknown"')
    local geth_progress=$(echo "$geth_sync" | jq -r '.progress // 0')

    # Check if Erigon is syncing
    local erigon_sync=$(get_sync_status "$ERIGON_RPC_URL" "Erigon")
    local erigon_status=$(echo "$erigon_sync" | jq -r '.status // "unknown"')
    local erigon_progress=$(echo "$erigon_sync" | jq -r '.progress // 0')

    # Health checks
    if [[ "$geth_status" == "syncing" ]]; then
        if (( $(echo "$geth_progress < 10" | bc -l) )); then
            issues+=("Geth sync progress is very low ($geth_progress%)")
            recommendations+=("Consider checkpoint sync or fast sync for Geth")
        elif (( $(echo "$geth_progress < 50" | bc -l) )); then
            issues+=("Geth sync progress is moderate ($geth_progress%)")
            recommendations+=("Monitor Geth sync, consider increasing cache size")
        fi
    fi

    if [[ "$erigon_status" == "syncing" ]]; then
        if (( $(echo "$erigon_progress < 10" | bc -l) )); then
            issues+=("Erigon sync progress is very low ($erigon_progress%)")
            recommendations+=("Check Erigon configuration and disk I/O")
        fi
    fi

    # Report issues and recommendations
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_warning "⚠️  Sync Issues Detected:"
        for issue in "${issues[@]}"; do
            log_warning "   • $issue"
        done

        log "💡 Recommendations:"
        for recommendation in "${recommendations[@]}"; do
            log "   • $recommendation"
        done
    else
        log "✅ No sync issues detected"
    fi
}

generate_optimization_commands() {
    log "Generating optimization commands..."

    cat << 'EOF'

🔧 OPTIMIZATION COMMANDS:

1. Increase Geth cache size (requires root):
   sudo systemctl edit geth
   # Add: ExecStart=
   # Add: ExecStart=/usr/bin/geth ... --cache=8192 ...

2. Monitor sync progress in real-time:
   watch -n 30 'curl -s http://127.0.0.1:8549 -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}" | jq'

3. Check peer connectivity:
   curl -s http://127.0.0.1:8549 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq

4. Monitor resource usage:
   watch -n 5 'ps aux | grep -E "(geth|erigon)" | grep -v grep'

5. Check logs for issues:
   sudo journalctl -u geth -f --no-pager
   sudo journalctl -u erigon -f --no-pager

6. Test RPC endpoints:
   curl -s http://127.0.0.1:8549 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq
   curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq

EOF
}

generate_report() {
    log "Generating monitoring report..."

    mkdir -p "$(dirname "$REPORT_FILE")"

    # Get current data
    local geth_sync=$(get_sync_status "$GETH_RPC_URL" "Geth")
    local erigon_sync=$(get_sync_status "$ERIGON_RPC_URL" "Erigon")
    local geth_service_status=$(systemctl is-active geth 2>/dev/null || echo "unknown")
    local erigon_service_status=$(systemctl is-active erigon 2>/dev/null || echo "unknown")

    # Create JSON report
    cat > "$REPORT_FILE" << EOF
{
    "report_timestamp": "$(date -Iseconds)",
    "node_status": {
        "geth": {
            "service_status": "$geth_service_status",
            "sync_status": $geth_sync,
            "rpc_endpoint": "$GETH_RPC_URL"
        },
        "erigon": {
            "service_status": "$erigon_service_status",
            "sync_status": $erigon_sync,
            "rpc_endpoint": "$ERIGON_RPC_URL"
        }
    },
    "monitoring_log": "$LOG_FILE",
    "recommendations": [
        "Monitor sync progress regularly",
        "Consider increasing cache size if sync is slow",
        "Ensure adequate network bandwidth and disk I/O",
        "Check peer connectivity if sync stalls"
    ]
}
EOF

    log "Report generated: $REPORT_FILE"
}

# Main execution
main() {
    show_header

    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"

    log "🔍 Starting Geth monitoring and analysis..."

    # Check connectivity
    if ! check_rpc_connectivity; then
        log_error "RPC connectivity check failed"
        exit 1
    fi

    # Get sync status
    get_sync_status "$GETH_RPC_URL" "Geth"
    get_sync_status "$ERIGON_RPC_URL" "Erigon"

    # Analyze performance
    analyze_sync_performance

    # Check health
    check_sync_health

    # Generate optimization commands
    generate_optimization_commands

    # Generate report
    generate_report

    log "✅ Geth monitoring and analysis completed!"
    log "📊 Report saved to: $REPORT_FILE"
    log "🔍 Check logs at: $LOG_FILE"
}

# Handle interrupts
trap 'log_warning "Monitoring interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"