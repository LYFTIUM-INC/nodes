#!/bin/bash
# Memory Optimization Script for Blockchain Nodes
# Automatically optimizes memory usage when thresholds are exceeded

set -euo pipefail

# Configuration
LOG_FILE="/data/blockchain/nodes/logs/memory-optimization.log"
MEMORY_THRESHOLD=85
SWAP_THRESHOLD=50
CACHE_CLEAR_THRESHOLD=90

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Get memory statistics
get_memory_stats() {
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    local used_mem=$(free -m | awk 'NR==2{print $3}')
    local free_mem=$(free -m | awk 'NR==2{print $4}')
    local available_mem=$(free -m | awk 'NR==2{print $7}')
    local cached_mem=$(free -m | awk 'NR==2{print $6}')
    local buffer_mem=$(free -m | awk 'NR==2{print $5}')
    
    local memory_percent=$((used_mem * 100 / total_mem))
    
    echo "$total_mem $used_mem $free_mem $available_mem $cached_mem $buffer_mem $memory_percent"
}

# Get swap statistics
get_swap_stats() {
    local swap_line=$(free -m | grep Swap)
    if [ -n "$swap_line" ]; then
        local total_swap=$(echo "$swap_line" | awk '{print $2}')
        local used_swap=$(echo "$swap_line" | awk '{print $3}')
        local free_swap=$(echo "$swap_line" | awk '{print $4}')
        
        if [ "$total_swap" -gt 0 ]; then
            local swap_percent=$((used_swap * 100 / total_swap))
            echo "$total_swap $used_swap $free_swap $swap_percent"
        else
            echo "0 0 0 0"
        fi
    else
        echo "0 0 0 0"
    fi
}

# Get container memory usage
get_container_memory() {
    docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}" | tail -n +2 | while read -r line; do
        local container=$(echo "$line" | awk '{print $1}')
        local mem_usage=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
        local mem_percent=$(echo "$line" | awk '{print $3}' | sed 's/%//')
        
        # Convert memory usage to MB
        if [[ "$mem_usage" == *"GiB" ]]; then
            mem_usage=$(echo "$mem_usage" | sed 's/GiB//' | awk '{print $1 * 1024}')
        elif [[ "$mem_usage" == *"MiB" ]]; then
            mem_usage=$(echo "$mem_usage" | sed 's/MiB//')
        elif [[ "$mem_usage" == *"KiB" ]]; then
            mem_usage=$(echo "$mem_usage" | sed 's/KiB//' | awk '{print $1 / 1024}')
        fi
        
        echo "$container $mem_usage $mem_percent"
    done | sort -k3 -nr
}

# Clear system caches
clear_system_caches() {
    log "INFO" "Clearing system caches"
    
    # Drop caches
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || {
        log "WARN" "Could not clear system caches (insufficient permissions)"
        return 1
    }
    
    # Clear temporary files
    find /tmp -type f -atime +1 -delete 2>/dev/null || true
    find /var/tmp -type f -atime +1 -delete 2>/dev/null || true
    
    log "INFO" "System caches cleared"
}

# Optimize container memory
optimize_container_memory() {
    local container=$1
    
    log "INFO" "Optimizing memory for container: $container"
    
    # Get container process info
    local pid=$(docker inspect --format '{{.State.Pid}}' "$container" 2>/dev/null)
    if [ -z "$pid" ] || [ "$pid" = "0" ]; then
        log "WARN" "Could not get PID for container $container"
        return 1
    fi
    
    # Clear container-specific caches if possible
    case "$container" in
        "ethereum-light"|"ethereum-erigon")
            # For Ethereum nodes, we can restart with optimized memory settings
            log "INFO" "Applying Ethereum-specific memory optimizations"
            docker exec "$container" sh -c 'kill -USR1 1' 2>/dev/null || true
            ;;
        "solana-dev")
            # For Solana, trigger garbage collection
            log "INFO" "Triggering Solana garbage collection"
            docker exec "$container" sh -c 'pkill -USR1 solana-test-validator' 2>/dev/null || true
            ;;
        "arbitrum-node"|"optimism-node"|"base-mainnet")
            # For L2 nodes, clear cache via RPC if available
            log "INFO" "Applying L2 node memory optimizations"
            docker exec "$container" sh -c 'kill -USR1 1' 2>/dev/null || true
            ;;
    esac
    
    # Force garbage collection in container if Java/Node.js based
    docker exec "$container" sh -c 'pgrep java | xargs -r kill -USR1' 2>/dev/null || true
    docker exec "$container" sh -c 'pgrep node | xargs -r kill -USR1' 2>/dev/null || true
    
    log "INFO" "Memory optimization completed for $container"
}

# Resize container memory limits
resize_container_memory() {
    local container=$1
    local new_limit=$2
    
    log "INFO" "Attempting to resize memory limit for $container to $new_limit"
    
    # Update memory limit (requires docker with cgroup v2 support)
    docker update --memory="$new_limit" "$container" 2>/dev/null || {
        log "WARN" "Could not update memory limit for $container"
        return 1
    }
    
    log "INFO" "Memory limit updated for $container"
}

# Restart memory-intensive containers
restart_heavy_containers() {
    local threshold=${1:-80}
    
    log "INFO" "Checking for containers using more than ${threshold}% memory"
    
    get_container_memory | while read -r container mem_usage mem_percent; do
        if [ "$mem_percent" -gt "$threshold" ]; then
            log "WARN" "Container $container using ${mem_percent}% memory (${mem_usage}MB)"
            
            # Check if container is critical (blockchain nodes)
            case "$container" in
                *ethereum*|*solana*|*arbitrum*|*optimism*|*base*)
                    log "INFO" "Attempting graceful optimization for critical container $container"
                    optimize_container_memory "$container"
                    ;;
                *)
                    log "INFO" "Restarting non-critical container $container"
                    docker restart "$container" || {
                        log "ERROR" "Failed to restart container $container"
                    }
                    ;;
            esac
        fi
    done
}

# Enable or increase swap
manage_swap() {
    local swap_stats=($(get_swap_stats))
    local total_swap=${swap_stats[0]}
    local used_swap=${swap_stats[1]}
    local swap_percent=${swap_stats[3]}
    
    if [ "$total_swap" -eq 0 ]; then
        log "INFO" "No swap detected, creating swap file"
        create_swap_file
    elif [ "$swap_percent" -gt "$SWAP_THRESHOLD" ]; then
        log "WARN" "Swap usage high: ${swap_percent}%"
        
        # Clear swap if possible
        if command -v swapoff >/dev/null 2>&1 && command -v swapon >/dev/null 2>&1; then
            log "INFO" "Refreshing swap space"
            swapoff -a && swapon -a || {
                log "WARN" "Could not refresh swap space"
            }
        fi
    fi
}

# Create swap file
create_swap_file() {
    local swap_size="2G"
    local swap_file="/swapfile"
    
    if [ -f "$swap_file" ]; then
        log "INFO" "Swap file already exists"
        return 0
    fi
    
    log "INFO" "Creating ${swap_size} swap file"
    
    # Check available disk space
    local available_space=$(df /data | tail -1 | awk '{print $4}')
    local required_space=$((2 * 1024 * 1024))  # 2GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        log "WARN" "Insufficient disk space for swap file"
        return 1
    fi
    
    # Create swap file
    dd if=/dev/zero of="$swap_file" bs=1M count=2048 2>/dev/null || {
        log "ERROR" "Failed to create swap file"
        return 1
    }
    
    chmod 600 "$swap_file"
    mkswap "$swap_file" >/dev/null 2>&1 || {
        log "ERROR" "Failed to format swap file"
        rm -f "$swap_file"
        return 1
    }
    
    swapon "$swap_file" || {
        log "ERROR" "Failed to enable swap file"
        rm -f "$swap_file"
        return 1
    }
    
    # Add to fstab for persistence
    if ! grep -q "$swap_file" /etc/fstab; then
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
    fi
    
    log "INFO" "Swap file created and enabled"
}

# Monitor memory usage and apply optimizations
monitor_and_optimize() {
    local stats=($(get_memory_stats))
    local total_mem=${stats[0]}
    local used_mem=${stats[1]}
    local available_mem=${stats[3]}
    local memory_percent=${stats[6]}
    
    log "INFO" "Memory usage: ${memory_percent}% (${used_mem}MB/${total_mem}MB used, ${available_mem}MB available)"
    
    if [ "$memory_percent" -ge "$CACHE_CLEAR_THRESHOLD" ]; then
        log "WARN" "Critical memory usage: ${memory_percent}%"
        clear_system_caches
        restart_heavy_containers 70
        manage_swap
        
        # Wait and check again
        sleep 30
        stats=($(get_memory_stats))
        memory_percent=${stats[6]}
        log "INFO" "Memory usage after optimization: ${memory_percent}%"
        
    elif [ "$memory_percent" -ge "$MEMORY_THRESHOLD" ]; then
        log "WARN" "High memory usage: ${memory_percent}%"
        optimize_containers
        clear_system_caches
        
    else
        log "INFO" "Memory usage within normal range"
    fi
}

# Optimize all containers
optimize_containers() {
    log "INFO" "Optimizing memory usage for all containers"
    
    # Get list of running blockchain containers
    local blockchain_containers=$(docker ps --format "{{.Names}}" | grep -E "(ethereum|solana|arbitrum|optimism|base)" || true)
    
    if [ -n "$blockchain_containers" ]; then
        echo "$blockchain_containers" | while read -r container; do
            optimize_container_memory "$container"
            sleep 5  # Brief delay between optimizations
        done
    else
        log "INFO" "No blockchain containers found to optimize"
    fi
}

# Generate memory report
generate_memory_report() {
    local report_file="/data/blockchain/nodes/logs/memory-report.txt"
    
    {
        echo "=== Memory Optimization Report ==="
        echo "Generated: $(date)"
        echo ""
        
        echo "System Memory:"
        free -h
        echo ""
        
        echo "Container Memory Usage:"
        get_container_memory
        echo ""
        
        echo "Top Memory Processes:"
        ps aux --sort=-%mem | head -10
        echo ""
        
        echo "Memory Configuration:"
        echo "Memory Threshold: ${MEMORY_THRESHOLD}%"
        echo "Cache Clear Threshold: ${CACHE_CLEAR_THRESHOLD}%"
        echo "Swap Threshold: ${SWAP_THRESHOLD}%"
        
    } > "$report_file"
    
    log "INFO" "Memory report generated: $report_file"
}

# Send notification
send_notification() {
    local action=$1
    local status=$2
    local details=$3
    
    # Send to monitoring system
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys
sys.path.append('/data/blockchain/nodes/monitoring')
from alert_system import AlertManager, Alert
from datetime import datetime

alert_manager = AlertManager()
alert = Alert(
    id='memory_opt_$(date +%s)',
    severity='info' if '$status' == 'success' else 'warning',
    source='memory_optimizer',
    message='Memory optimization $action: $details',
    timestamp=datetime.now()
)
alert_manager.process_alerts([alert])
" 2>/dev/null || log "WARN" "Could not send notification to monitoring system"
    fi
}

# Main execution
main() {
    local action="${1:-monitor}"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "INFO" "Memory optimization script started. Action: $action"
    
    case "$action" in
        "monitor")
            monitor_and_optimize
            send_notification "monitoring" "success" "Memory monitoring and optimization completed"
            ;;
        "clear-cache")
            clear_system_caches
            send_notification "cache_clear" "success" "System caches cleared"
            ;;
        "optimize-containers")
            optimize_containers
            send_notification "container_optimization" "success" "Container memory optimization completed"
            ;;
        "manage-swap")
            manage_swap
            send_notification "swap_management" "success" "Swap management completed"
            ;;
        "report")
            generate_memory_report
            send_notification "report_generation" "success" "Memory report generated"
            ;;
        "emergency")
            log "WARN" "Emergency memory optimization triggered"
            clear_system_caches
            restart_heavy_containers 60
            manage_swap
            send_notification "emergency_optimization" "success" "Emergency memory optimization completed"
            ;;
        *)
            echo "Usage: $0 [monitor|clear-cache|optimize-containers|manage-swap|report|emergency]"
            echo "  monitor: Monitor and optimize memory usage (default)"
            echo "  clear-cache: Clear system caches"
            echo "  optimize-containers: Optimize container memory usage"
            echo "  manage-swap: Manage swap space"
            echo "  report: Generate memory usage report"
            echo "  emergency: Emergency memory optimization"
            exit 1
            ;;
    esac
    
    log "INFO" "Memory optimization script completed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi