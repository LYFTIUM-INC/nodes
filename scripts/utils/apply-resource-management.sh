#!/bin/bash
# Master script to apply comprehensive resource management for blockchain nodes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/resource-management.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        log "Error: This script must be run as root or with sudo"
        exit 1
    fi
}

# Backup existing configurations
backup_configs() {
    log "Creating configuration backups..."
    
    local backup_dir="${SCRIPT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup systemd files
    if [ -d "/etc/systemd/system" ]; then
        cp -r /etc/systemd/system/*.d "$backup_dir/" 2>/dev/null || true
    fi
    
    # Backup iptables rules
    iptables-save > "$backup_dir/iptables.rules" 2>/dev/null || true
    
    # Backup sysctl settings
    sysctl -a > "$backup_dir/sysctl.conf" 2>/dev/null || true
    
    log "Backups created in: $backup_dir"
}

# Apply CPU management
apply_cpu_management() {
    log "Applying CPU management configurations..."
    
    if [ -x "${SCRIPT_DIR}/scripts/cpu-management.sh" ]; then
        "${SCRIPT_DIR}/scripts/cpu-management.sh" >> "$LOG_FILE" 2>&1
        log "CPU management applied successfully"
    else
        log "Warning: CPU management script not found or not executable"
    fi
}

# Apply memory management
apply_memory_management() {
    log "Applying memory management configurations..."
    
    if [ -x "${SCRIPT_DIR}/scripts/memory-management.sh" ]; then
        "${SCRIPT_DIR}/scripts/memory-management.sh" >> "$LOG_FILE" 2>&1
        
        # Apply sysctl settings
        if [ -f "${SCRIPT_DIR}/configs/sysctl-memory.conf" ]; then
            cp "${SCRIPT_DIR}/configs/sysctl-memory.conf" /etc/sysctl.d/99-blockchain-memory.conf
            sysctl -p /etc/sysctl.d/99-blockchain-memory.conf >> "$LOG_FILE" 2>&1
        fi
        
        log "Memory management applied successfully"
    else
        log "Warning: Memory management script not found or not executable"
    fi
}

# Apply I/O management
apply_io_management() {
    log "Applying I/O management configurations..."
    
    if [ -x "${SCRIPT_DIR}/scripts/io-management.sh" ]; then
        "${SCRIPT_DIR}/scripts/io-management.sh" >> "$LOG_FILE" 2>&1
        log "I/O management applied successfully"
    else
        log "Warning: I/O management script not found or not executable"
    fi
}

# Apply network management
apply_network_management() {
    log "Applying network management configurations..."
    
    if [ -x "${SCRIPT_DIR}/scripts/network-management.sh" ]; then
        "${SCRIPT_DIR}/scripts/network-management.sh" >> "$LOG_FILE" 2>&1
        
        # Apply iptables rules persistently
        if [ -f "${SCRIPT_DIR}/configs/iptables-blockchain.rules" ]; then
            iptables-restore < "${SCRIPT_DIR}/configs/iptables-blockchain.rules" 2>/dev/null || \
                log "Warning: Failed to restore iptables rules"
        fi
        
        log "Network management applied successfully"
    else
        log "Warning: Network management script not found or not executable"
    fi
}

# Install systemd drop-ins
install_systemd_dropins() {
    log "Installing systemd drop-in configurations..."
    
    local dropin_dir="${SCRIPT_DIR}/systemd-dropins"
    if [ -d "$dropin_dir" ]; then
        for service_dir in "$dropin_dir"/*.d; do
            if [ -d "$service_dir" ]; then
                local service_name=$(basename "${service_dir%.d}")
                local target_dir="/etc/systemd/system/${service_name}.d"
                
                mkdir -p "$target_dir"
                cp -r "$service_dir"/* "$target_dir/" 2>/dev/null || \
                    log "Warning: Failed to copy drop-ins for $service_name"
                
                log "Installed drop-ins for $service_name"
            fi
        done
        
        # Reload systemd
        systemctl daemon-reload
        log "Systemd configuration reloaded"
    fi
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating resource monitoring dashboard..."
    
    cat > "${SCRIPT_DIR}/monitor-resources.sh" << 'EOF'
#!/bin/bash
# Real-time resource monitoring dashboard for blockchain nodes

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to get process stats
get_process_stats() {
    local service=$1
    local pid=$(systemctl show -p MainPID "$service" 2>/dev/null | cut -d= -f2)
    
    if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
        local cpu=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null || echo "0")
        local mem=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null || echo "0")
        local vsz=$(ps -p "$pid" -o vsz --no-headers 2>/dev/null || echo "0")
        local rss=$(ps -p "$pid" -o rss --no-headers 2>/dev/null || echo "0")
        
        printf "%-20s ${GREEN}%-8s${NC} CPU: %-6s%% MEM: %-6s%% VSZ: %-10s RSS: %-10s\n" \
            "$service" "RUNNING" "$cpu" "$mem" "${vsz}K" "${rss}K"
    else
        printf "%-20s ${RED}%-8s${NC} %-42s\n" "$service" "STOPPED" "-"
    fi
}

# Main monitoring loop
while true; do
    clear
    echo -e "${BLUE}Blockchain Node Resource Monitor - $(date)${NC}"
    echo "=================================================================="
    
    # System overview
    echo -e "\n${YELLOW}System Overview:${NC}"
    echo "CPU Cores: $(nproc)"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo "Memory: $(free -h | grep Mem | awk '{print "Total:", $2, "Used:", $3, "Free:", $4}')"
    echo "Swap: $(free -h | grep Swap | awk '{print "Total:", $2, "Used:", $3, "Free:", $4}')"
    
    # Node status
    echo -e "\n${YELLOW}Node Resource Usage:${NC}"
    printf "%-20s %-8s %-42s\n" "SERVICE" "STATUS" "RESOURCE USAGE"
    echo "------------------------------------------------------------------"
    
    for node in ethereum erigon polygon-bor polygon-heimdall optimism arbitrum base bsc avalanche solana; do
        for suffix in "" "-node" ".service"; do
            service="${node}${suffix}"
            if systemctl list-unit-files | grep -q "^${service}"; then
                get_process_stats "$service"
                break
            fi
        done
    done
    
    # Cgroup stats
    if [ -d "/sys/fs/cgroup/blockchain" ]; then
        echo -e "\n${YELLOW}Cgroup Resource Limits:${NC}"
        for node_dir in /sys/fs/cgroup/blockchain/*; do
            if [ -d "$node_dir" ]; then
                node=$(basename "$node_dir")
                mem_limit=$(cat "$node_dir/memory.max" 2>/dev/null || echo "unlimited")
                mem_current=$(cat "$node_dir/memory.current" 2>/dev/null || echo "0")
                cpu_weight=$(cat "$node_dir/cpu.weight" 2>/dev/null || echo "100")
                
                if [ "$mem_limit" != "unlimited" ] && [ "$mem_limit" != "max" ]; then
                    mem_limit_mb=$((mem_limit / 1024 / 1024))
                    mem_current_mb=$((mem_current / 1024 / 1024))
                    printf "%-20s Memory: %6dMB / %6dMB   CPU Weight: %s\n" \
                        "$node" "$mem_current_mb" "$mem_limit_mb" "$cpu_weight"
                fi
            fi
        done
    fi
    
    echo -e "\n${YELLOW}Press Ctrl+C to exit${NC}"
    sleep 5
done
EOF
    
    chmod +x "${SCRIPT_DIR}/monitor-resources.sh"
    log "Resource monitoring dashboard created"
}

# Create systemd service for resource management
create_systemd_service() {
    log "Creating systemd service for resource management..."
    
    cat > /etc/systemd/system/blockchain-resource-manager.service << EOF
[Unit]
Description=Blockchain Node Resource Manager
After=network.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/apply-resource-management.sh --update
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable blockchain-resource-manager.service
    log "Systemd service created and enabled"
}

# Update function for running resource management updates
update_resources() {
    log "Updating resource management configurations..."
    
    # Re-apply all configurations
    apply_cpu_management
    apply_memory_management
    apply_io_management
    apply_network_management
    
    log "Resource management update completed"
}

# Main execution
main() {
    log "Starting comprehensive resource management setup..."
    
    # Check permissions
    check_permissions
    
    # Check if this is an update
    if [[ "${1:-}" == "--update" ]]; then
        update_resources
        exit 0
    fi
    
    # Create backups
    backup_configs
    
    # Apply all resource management configurations
    apply_cpu_management
    apply_memory_management
    apply_io_management
    apply_network_management
    
    # Install systemd drop-ins
    install_systemd_dropins
    
    # Create monitoring dashboard
    create_monitoring_dashboard
    
    # Create systemd service
    create_systemd_service
    
    log "Resource management setup completed successfully!"
    log ""
    log "Next steps:"
    log "1. Review the configurations in: ${SCRIPT_DIR}"
    log "2. Restart blockchain services to apply systemd drop-ins:"
    log "   systemctl restart <service-name>"
    log "3. Monitor resources with: ${SCRIPT_DIR}/monitor-resources.sh"
    log "4. Check logs at: $LOG_FILE"
    log ""
    log "To update resource limits in the future, run:"
    log "   systemctl start blockchain-resource-manager.service"
}

# Run main function
main "$@"