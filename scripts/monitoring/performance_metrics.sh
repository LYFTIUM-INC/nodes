#!/bin/bash
#
# Geth Performance Metrics Collection Script
# Collects real-time performance data for optimization analysis
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
GETH_PID_FILE="/tmp/geth_pid.tmp"
METRICS_FILE="/tmp/blockchain_logs/performance_metrics_$(date +%Y%m%d_%H%M%S).json"
ALERT_THRESHOLD_CPU=90
ALERT_THRESHOLD_MEMORY=85

# Functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

collect_cpu_memory() {
    local geth_pid
    geth_pid=$(pgrep geth | head -1)
    echo "$geth_pid" > "$GETH_PID_FILE"
    
    if [[ -n "$geth_pid" ]]; then
        local cpu=$(ps -p "$geth_pid" -o %cpu= | tr -d ' ')
        local mem=$(ps -p "$geth_pid" -o %mem= | tr -d ' ')
        local rss=$(ps -p "$geth_pid" -o rss= | tr -d ' ')
        
        echo "CPU: ${cpu}%"
        echo "Memory: ${mem}% (${rss}KB)"
    else
        echo "Geth not running"
    fi
}

collect_network_stats() {
    local rx_bytes=$(cat /proc/net/dev/statistics 2>/dev/null | grep eth0 | awk '/RxBytes/ {print $2}')
    local tx_bytes=$(cat /proc/net/dev/statistics 2>/dev/null | grep eth0 | awk '/TxBytes/ {print $2}')
    
    if [[ -n "$rx_bytes" && -n "$tx_bytes" ]]; then
        echo "Network: RX: $((rx_bytes/1048576))MB/s, TX: $((tx_bytes/1048576))MB/s"
    else
        echo "Network: No data"
    fi
}

collect_disk_io() {
    local disk_util=$(iostat -x 1 1 2>/dev/null | grep -E "(Device|sda|nvme)" | tail -n +1 | awk '{printf "%s: %s%% util", $1, $NF}' | head -1)
    echo "Disk I/O: $disk_util"
}

collect_peer_info() {
    local peer_count=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        "$GETH_RPC_URL" 2>/dev/null | jq -r '.result // "0x0"')
    
    if [[ -n "$peer_count" ]]; then
        local peer_dec=$((peer_count))
        echo "Peers: $peer_dec"
    else
        echo "Peers: 0"
    fi
}

get_sync_status() {
    local result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        "$GETH_RPC_URL" 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$result" ]]; then
        local sync_data=$(echo "$result" | jq -r '.result // false')
        
        if [[ "$sync_data" == "false" || "$sync_data" == "null" || "$sync_data" == "" ]]; then
            echo '{"status":"synced","progress":100}'
        else
            local current=$(echo "$sync_data" | jq -r '.currentBlock // "0x0"')
            local highest=$(echo "$sync_data" | jq -r '.highestBlock // "0x0"')
            local progress=$(echo "scale=2; $current * 100 / $highest" | bc -l 2>/dev/null || echo "0")
            
            echo '{"status":"syncing","current":'$current',"highest":'$highest',"progress":'$progress'}'
        fi
    else
        echo '{"status":"error","error":"RPC connection failed"}'
    fi
}

# Main monitoring loop
collect_metrics() {
    local timestamp=$(date -Iseconds)
    local cpu_usage=$(collect_cpu_memory)
    local network_stats=$(collect_network_stats)
    local disk_io=$(collect_disk_io)
    local peer_info=$(collect_peer_info)
    local sync_status=$(get_sync_status)
    
    echo "$timestamp,$cpu_usage,$network_stats,$disk_io,$peer_info,$sync_status" >> "$METRICS_FILE"
}

generate_performance_report() {
    local report_file="/tmp/blockchain_logs/performance_report_$(date +%Y%m%d_%H%M%S).json"
    local total_metrics=0
    
    # Skip header line
    if [[ -f "$METRICS_FILE" ]]; then
        total_metrics=$(tail -n +2 "$METRICS_FILE" | wc -l)
    fi
    
    if [[ $total_metrics -gt 0 ]]; then
        echo "Generating performance analysis..."
        
        # Calculate averages from collected metrics
        python3 << EOF
import json
import statistics

def analyze_performance_data(file_path):
    timestamps = []
    cpu_usage = []
    memory_usage = []
    network_rx = []
    network_tx = []
    disk_io = []
    peer_counts = []
    sync_progress = []
    
    with open(file_path, 'r') as f:
        next(f)  # Skip header
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            if len(parts) >= 7:
                timestamps.append(parts[0])
                cpu_usage.append(float(parts[1]))
                memory_usage.append(float(parts[2]))
                network_rx.append(float(parts[3]))
                network_tx.append(float(parts[4]))
                disk_io.append(float(parts[5]))
                peer_counts.append(int(parts[6]))
                sync_progress.append(json.loads(parts[7]))
            except:
                continue
    
    if not timestamps:
        return {}
    
    return {
        "monitoring_period": f"{timestamps[0]} to {timestamps[-1]}",
        "data_points": len(timestamps),
        "cpu_usage": {
            "average": statistics.mean(cpu_usage) if cpu_usage else 0,
            "max": max(cpu_usage) if cpu_usage else 0,
            "min": min(cpu_usage) if cpu_usage else 0
        },
        "memory_usage": {
            "average": statistics.mean(memory_usage) if memory_usage else 0,
            "max": max(memory_usage) if memory_usage else 0,
            "min": min(memory_usage) if memory_usage else 0
        },
        "network_usage": {
            "average_rx_mbps": statistics.mean(network_rx) if network_rx else 0,
            "average_tx_mbps": statistics.mean(network_tx) if network_tx else 0,
            "max_rx_mbps": max(network_rx) if network_rx else 0,
            "max_tx_mbps": max(network_tx) if network_tx else 0
        },
        "disk_io": {
            "average_util": statistics.mean(disk_io) if disk_io else 0,
            "max_util": max(disk_io) if disk_io else 0
        },
        "peer_connectivity": {
            "average_peers": statistics.mean(peer_counts) if peer_counts else 0,
            "max_peers": max(peer_counts) if peer_counts else 0,
            "min_peers": min(peer_counts) if peer_counts else 0
        },
        "sync_performance": {
            "average_progress": statistics.mean([s['progress'] for s in sync_progress if isinstance(s, dict)]),
            "final_progress": sync_progress[-1]['progress'] if sync_progress and sync_progress else 0,
            "progress_improvement": "0%"  # Would calculate this over time
        }
    }

if __name__ == "__main__":
    metrics_file = "$METRICS_FILE"
    report = analyze_performance_data(metrics_file)
    print(json.dumps(report, indent=2))
EOF
EOF
    } else
        echo "No metrics data available yet"
    fi
}

# Main execution
main() {
    echo "=== Geth Performance Metrics Collector ==="
    echo "Starting performance monitoring..."
    echo "Collecting data every 60 seconds..."
    echo "Press Ctrl+C to stop monitoring"
    echo
    
    # Create metrics file
    echo "timestamp,cpu_usage,network_rx_mbps,network_tx_mbps,disk_io_util,peer_count,sync_progress" > "$METRICS_FILE"
    
    # Create monitoring loop
    trap 'echo "Stopping monitoring..."; exit 0' INT TERM
    
    # Collect initial baseline
    collect_metrics
    
    # Monitoring loop
    while true; do
        sleep 60
        collect_metrics
        log "📊 Metrics collected ($(date '+%Y-%m-%d %H:%M:%S')) - Cache: $(tail -1 "$METRICS_FILE" | cut -d',' -f1)"
    done
}

# Start monitoring if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi