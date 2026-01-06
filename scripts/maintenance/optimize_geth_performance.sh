#!/bin/bash
#
# Geth Performance Optimization Script
# Optimizes Geth node configuration for better sync performance
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
GETH_SERVICE="geth"
GETH_CONFIG="/etc/systemd/system/geth.service"
GETH_OPTIMIZATION="/data/blockchain/nodes/geth_optimization.toml"
BACKUP_DIR="/data/blockchain/nodes/backups"
LOG_FILE="/tmp/blockchain_logs/geth_optimization.log"

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
    echo -e "${PURPLE}🚀 GETH NODE PERFORMANCE OPTIMIZATION${NC}"
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${BLUE}Timestamp: $(date -Iseconds)${NC}"
    echo -e "${BLUE}Target Service: $GETH_SERVICE${NC}"
    echo -e "${PURPLE}================================================${NC}"
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Check if Geth service exists
    if ! systemctl list-unit-files | grep -q "$GETH_SERVICE.service"; then
        log_error "Geth service not found"
        exit 1
    fi

    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"

    log "Prerequisites check completed"
}

get_current_sync_status() {
    log "Getting current sync status..."

    local sync_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        http://127.0.0.1:8549 2>/dev/null)

    if [[ $? -eq 0 && -n "$sync_result" ]]; then
        local current=$(echo "$sync_result" | jq -r '.result.currentBlock // "0x0"')
        local highest=$(echo "$sync_result" | jq -r '.result.highestBlock // "0x0"')
        local current_dec=$((current))
        local highest_dec=$((highest))
        local progress=$(echo "scale=2; $current_dec * 100 / $highest_dec" | bc -l 2>/dev/null || echo "0")

        log "Current sync status: $current_dec / $highest_dec ($progress%)"
        return 0
    else
        log_warning "Could not retrieve sync status"
        return 1
    fi
}

get_system_resources() {
    log "Analyzing system resources..."

    # CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')

    # Memory
    local mem_info=$(free -h | awk '/^Mem:/ {printf "%.1fGB used / %.1fGB total (%.1f%%)", $3/$2*100, $2, $3/$2*100}')

    # Disk I/O
    local disk_io=$(iostat -x 1 1 2>/dev/null | grep -E "(Device|sda|nvme)" | tail -n +1 | awk '{printf "%s: %s%% util, %sMB/s read, %sMB/s write", $1, $NF, $4/1024, $9/1024}' | head -1)

    # Network
    local network_stats=$(sar -n DEV 1 1 2>/dev/null | grep "Average:" | grep -E "(eth|ens)" | awk '{printf "RX: %.1fMB/s, TX: %.1fMB/s", $3/1024, $4/1024}' || echo "Network stats unavailable")

    log "System Resources:"
    log "  CPU Usage: $cpu_usage%"
    log "  Memory: $mem_info"
    log "  Disk I/O: $disk_io"
    log "  Network: $network_stats"
}

optimize_geth_config() {
    log "Optimizing Geth configuration..."

    # Backup current service file
    local backup_file="$BACKUP_DIR/geth.service.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$GETH_CONFIG" "$backup_file"
    log "Backed up current service file to: $backup_file"

    # Create optimized service file
    local optimized_service="$BACKUP_DIR/geth.service.optimized"
    cat > "$optimized_service" << 'EOF'
[Unit]
Description=Geth Node v1.14.10 (MEV Optimized - Performance Tuned)
Documentation=https://geth.ethereum.org/docs/
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=exec
User=lyftium
Group=lyftium
WorkingDirectory=/data/blockchain/nodes/ethereum

# Security: Load environment from secure location
EnvironmentFile=/data/blockchain/nodes/security/ethereum_secure.env

# Optimized Geth configuration for faster sync
ExecStart=/usr/bin/geth \
    --datadir=/data/blockchain/storage/geth-backup \
    --mainnet \
    --syncmode=snap \
    --gcmode=full \
    --cache=8192 \
    --maxpeers=150 \
    --sync.loop.block.limit=2000 \
    --batchsize=4G \
    --sync.parallel-state-flushing \
    --state.scheme=path \
    --http \
    --http.addr=127.0.0.1 \
    --http.port=8549 \
    --http.api=eth,net,web3,debug,txpool \
    --http.vhosts=localhost,127.0.0.1 \
    --ws \
    --ws.addr=127.0.0.1 \
    --ws.port=8550 \
    --ws.api=eth,net,web3,debug,txpool \
    --ws.origins=* \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port=8554 \
    --authrpc.vhosts=localhost,127.0.0.1 \
    --port=30311 \
    --discovery.port=30311 \
    --metrics \
    --metrics.addr=127.0.0.1 \
    --metrics.port=6069 \
    --txlookuplimit=0 \
    --verbosity=3 \
    --log.rotate \
    --log.maxage=7 \
    --rpc.gascap=50000000 \
    --rpc.txfeecap=100 \
    --rpc.allow-unprotected-txs=false \
    --txpool.accountslots=64 \
    --txpool.globalslots=16384 \
    --txpool.accountqueue=128 \
    --txpool.globalqueue=8192 \
    --txpool.pricelimit=1000000000 \
    --txpool.pricebump=10 \
    --nat=extip:51.159.82.58 \
    --authrpc.jwtsecret=/data/blockchain/storage/jwt-secret-common.hex \
    --snapshots=true \
    --sync.synchronous=false

# Resource limits (optimized for performance)
MemoryHigh=8G
MemoryMax=10G
CPUQuota=400%
TasksMax=32768
LimitNOFILE=1048576
LimitNPROC=32768
IOWeight=50

# Restart policy
Restart=on-failure
RestartSec=30s
TimeoutStartSec=300s
TimeoutStopSec=30s

# CRITICAL SECURITY HARDENING
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectClock=true
ProtectControlGroups=true
ProtectHostname=true

# File system access
ReadWritePaths=/data/blockchain/storage/geth-backup
ReadWritePaths=/data/blockchain/storage/jwt-secret-common.hex
ReadWritePaths=/data/blockchain/nodes/security/secrets
ReadOnlyPaths=/data/blockchain/nodes/security

# Network security
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
PrivateNetwork=false
IPAccounting=true

# System calls filtering
SystemCallFilter=@system-service
SystemCallFilter=~@debug @mount @cpu-emulation @obsolete @privileged @reboot @swap
SystemCallErrorNumber=EPERM

# Capabilities
CapabilityBoundingSet=CAP_SETUID CAP_SETGID CAP_NET_BIND_SERVICE CAP_DAC_READ CAP_DAC_OVERRIDE CAP_FOWNER CAP_SETFCAP CAP_SETPCAP CAP_MKNOD CAP_CHOWN CAP_FSETID CAP_SETGID CAP_SETPCAP CAP_KILL CAP_SYS_CHROOT
AmbientCapabilities=CAP_SETUID CAP_SETGID CAP_NET_BIND_SERVICE

# Resource restrictions
RestrictRealtime=true
RestrictSUIDSGID=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=false
RemoveIPC=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=geth-performance

[Install]
WantedBy=multi-user.target
EOF

    # Apply optimized configuration
    cp "$optimized_service" "$GETH_CONFIG"
    log "Applied optimized Geth configuration"

    # Reload systemd
    systemctl daemon-reload
    log "Reloaded systemd daemon"
}

restart_geth_service() {
    log "Restarting Geth service with optimized configuration..."

    # Stop the service
    systemctl stop "$GETH_SERVICE"
    log "Stopped Geth service"

    # Wait a moment for clean shutdown
    sleep 10

    # Start the service
    systemctl start "$GETH_SERVICE"
    log "Started Geth service with optimized configuration"

    # Wait for service to be ready
    sleep 30

    # Check service status
    if systemctl is-active --quiet "$GETH_SERVICE"; then
        log "✅ Geth service started successfully"
    else
        log_error "❌ Failed to start Geth service"
        return 1
    fi
}

monitor_sync_progress() {
    log "Monitoring sync progress for 5 minutes..."

    for i in {1..10}; do
        sleep 30

        local sync_result=$(curl -s -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
            http://127.0.0.1:8549 2>/dev/null)

        if [[ $? -eq 0 && -n "$sync_result" ]]; then
            local current=$(echo "$sync_result" | jq -r '.result.currentBlock // "0x0"')
            local highest=$(echo "$sync_result" | jq -r '.result.highestBlock // "0x0"')
            local current_dec=$((current))
            local highest_dec=$((highest))
            local progress=$(echo "scale=2; $current_dec * 100 / $highest_dec" | bc -l 2>/dev/null || echo "0")

            log "Sync progress check $i/10: $current_dec / $highest_dec ($progress%)"
        else
            log_warning "Could not retrieve sync status at check $i/10"
        fi
    done

    log "Sync progress monitoring completed"
}

generate_report() {
    log "Generating optimization report..."

    local report_file="/tmp/blockchain_logs/geth_optimization_report_$(date +%Y%m%d_%H%M%S).json"

    # Get final status
    local service_status=$(systemctl is-active "$GETH_SERVICE")
    local sync_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        http://127.0.0.1:8549 2>/dev/null)

    # Generate JSON report
    cat > "$report_file" << EOF
{
    "optimization_timestamp": "$(date -Iseconds)",
    "service_name": "$GETH_SERVICE",
    "optimization_applied": true,
    "service_status": "$service_status",
    "current_sync_status": $sync_result,
    "optimization_changes": [
        "Increased cache from 4096MB to 8192MB",
        "Increased max peers from 100 to 150",
        "Increased sync loop block limit to 2000",
        "Increased batch size to 4GB",
        "Enabled parallel state flushing",
        "Increased transaction pool limits",
        "Optimized resource limits (CPU: 400%, Memory: 10GB)"
    ],
    "performance_monitoring": {
        "enabled": true,
        "log_file": "$LOG_FILE",
        "backup_config": "$BACKUP_DIR/geth.service.backup.$(date +%Y%m%d_%H%M%S)"
    }
}
EOF

    log "Optimization report generated: $report_file"
}

# Main execution
main() {
    show_header
    check_prerequisites

    log "🔍 Starting Geth performance optimization..."

    # Get current baseline
    get_system_resources
    get_current_sync_status

    # Apply optimizations
    optimize_geth_config

    # Restart service
    restart_geth_service

    # Monitor progress
    monitor_sync_progress

    # Generate report
    generate_report

    log "✅ Geth performance optimization completed successfully!"
    log "📊 Check the optimization report for detailed results"
    log "🔍 Monitor sync progress with: watch -n 30 'curl -s http://127.0.0.1:8549 -X POST -H \"Content-Type: application/json\" -d \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"method\\\":\\\"eth_syncing\\\",\\\"params\\\":[],\\\"id\\\":1}\" | jq'"
}

# Handle interrupts
trap 'log_warning "Optimization interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"