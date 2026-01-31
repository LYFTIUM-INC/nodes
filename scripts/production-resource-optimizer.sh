#!/bin/bash

# MEV Production Resource Optimizer
# Monitors and optimizes system resources for MEV operations

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Resource monitoring
check_memory() {
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    if (( $(echo "$mem_usage > 95" | bc -l) )); then
        warning "High memory usage: ${mem_usage}%"
        return 1
    else
        success "Memory usage: ${mem_usage}%"
        return 0
    fi
}

check_disk() {
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 92 ]; then
        warning "High disk usage: ${disk_usage}%"
        return 1
    else
        success "Disk usage: ${disk_usage}%"
        return 0
    fi
}

check_load() {
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    if (( $(echo "$load_avg > $((cpu_cores * 8))" | bc -l) )); then
        warning "High load average: $load_avg (cores: $cpu_cores)"
        return 1
    else
        success "Load average: $load_avg (cores: $cpu_cores)"
        return 0
    fi
}

# Cleanup functions
cleanup_logs() {
    log "Cleaning up old log files..."
    find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null || true
    find /tmp -name "mev-*" -mtime +1 -delete 2>/dev/null || true
    success "Log cleanup completed"
}

cleanup_temp() {
    log "Cleaning up temporary files..."
    rm -f /tmp/kafka-* 2>/dev/null || true
    rm -f /tmp/clickhouse-* 2>/dev/null || true
    success "Temp cleanup completed"
}

# Main execution
main() {
    log "🚀 MEV Production Resource Optimizer"
    echo "=================================="
    
    # Check resources
    check_memory
    check_disk
    check_load
    
    # Cleanup
    cleanup_logs
    cleanup_temp
    
    success "✅ Resource optimization completed"
}

# Run main function
main "$@"
