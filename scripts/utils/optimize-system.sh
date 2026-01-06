#!/bin/bash

# System Optimization Script for Erigon MEV Operations
# Optimizes system parameters for maximum sync performance and MEV operations

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== System Optimization for Erigon MEV Operations ===${NC}"

# Check if running as root for system optimizations
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Warning: Some optimizations require root privileges${NC}"
    echo "Run with sudo for full optimization"
fi

# Function to optimize kernel parameters
optimize_kernel_parameters() {
    echo -e "${BLUE}Optimizing kernel parameters...${NC}"
    
    if [ "$EUID" -eq 0 ]; then
        # Network optimizations
        cat >> /etc/sysctl.conf << EOF

# Erigon MEV Optimizations
# Network optimizations
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
net.ipv4.tcp_rmem = 4096 16384 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.netdev_max_backlog = 30000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# File system optimizations
fs.file-max = 2097152
vm.max_map_count = 262144
vm.swappiness = 1
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Memory optimizations
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
EOF
        
        # Apply immediately
        sysctl -p
        echo "Kernel parameters optimized"
    else
        echo "Skipping kernel parameter optimization (requires root)"
    fi
}

# Function to optimize file descriptors
optimize_file_descriptors() {
    echo -e "${BLUE}Optimizing file descriptors...${NC}"
    
    if [ "$EUID" -eq 0 ]; then
        # Increase file descriptor limits
        cat >> /etc/security/limits.conf << EOF

# Erigon MEV Optimizations
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
EOF
        
        # For systemd services
        mkdir -p /etc/systemd/system.conf.d
        cat > /etc/systemd/system.conf.d/erigon-limits.conf << EOF
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
EOF
        
        echo "File descriptor limits optimized"
    else
        echo "Skipping file descriptor optimization (requires root)"
    fi
}

# Function to optimize I/O scheduler
optimize_io_scheduler() {
    echo -e "${BLUE}Optimizing I/O scheduler...${NC}"
    
    if [ "$EUID" -eq 0 ]; then
        # Find storage devices
        for device in $(lsblk -nd -o NAME | grep -E '^(sd|nvme|vd)'); do
            # Set I/O scheduler to deadline or mq-deadline for better performance
            if [ -f "/sys/block/$device/queue/scheduler" ]; then
                # For NVMe drives, use none or mq-deadline
                if [[ $device == nvme* ]]; then
                    echo "none" > "/sys/block/$device/queue/scheduler" 2>/dev/null || \
                    echo "mq-deadline" > "/sys/block/$device/queue/scheduler" 2>/dev/null || \
                    echo "Warning: Could not set scheduler for $device"
                else
                    echo "mq-deadline" > "/sys/block/$device/queue/scheduler" 2>/dev/null || \
                    echo "deadline" > "/sys/block/$device/queue/scheduler" 2>/dev/null || \
                    echo "Warning: Could not set scheduler for $device"
                fi
                
                # Optimize queue depth
                echo "2048" > "/sys/block/$device/queue/nr_requests" 2>/dev/null || true
                
                # Optimize read-ahead
                echo "4096" > "/sys/block/$device/queue/read_ahead_kb" 2>/dev/null || true
                
                echo "Optimized I/O scheduler for $device"
            fi
        done
    else
        echo "Skipping I/O scheduler optimization (requires root)"
    fi
}

# Function to optimize CPU governor
optimize_cpu_governor() {
    echo -e "${BLUE}Optimizing CPU governor...${NC}"
    
    if [ "$EUID" -eq 0 ]; then
        # Set CPU governor to performance
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            if [ -f "$cpu" ]; then
                echo "performance" > "$cpu" 2>/dev/null || true
            fi
        done
        echo "CPU governor set to performance"
    else
        echo "Skipping CPU governor optimization (requires root)"
    fi
}

# Function to optimize memory settings
optimize_memory() {
    echo -e "${BLUE}Optimizing memory settings...${NC}"
    
    # Check current memory
    local total_mem=$(free -g | grep '^Mem:' | awk '{print $2}')
    echo "Total system memory: ${total_mem}GB"
    
    if [ "$EUID" -eq 0 ]; then
        # Disable transparent huge pages (can cause performance issues)
        echo "never" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        echo "never" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
        
        # Make it persistent
        cat > /etc/systemd/system/disable-thp.service << EOF
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never | tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null'
ExecStart=/bin/sh -c 'echo never | tee /sys/kernel/mm/transparent_hugepage/defrag > /dev/null'

[Install]
WantedBy=basic.target
EOF
        
        systemctl enable disable-thp.service 2>/dev/null || true
        systemctl start disable-thp.service 2>/dev/null || true
        
        echo "Memory optimizations applied"
    else
        echo "Skipping memory optimization (requires root)"
    fi
}

# Function to optimize network settings
optimize_network() {
    echo -e "${BLUE}Optimizing network settings...${NC}"
    
    if [ "$EUID" -eq 0 ]; then
        # Optimize network interface settings
        for interface in $(ip link show | grep -E '^[0-9]+:' | grep -v lo | cut -d: -f2 | tr -d ' '); do
            if [ -d "/sys/class/net/$interface" ]; then
                # Increase ring buffer sizes if possible
                ethtool -G "$interface" rx 4096 tx 4096 2>/dev/null || true
                
                # Enable hardware offloading if available
                ethtool -K "$interface" tso on gso on gro on lro on 2>/dev/null || true
                
                echo "Optimized network interface: $interface"
            fi
        done
    else
        echo "Skipping network optimization (requires root)"
    fi
}

# Function to check and display current settings
check_current_settings() {
    echo -e "${BLUE}Current system settings:${NC}"
    
    echo "Memory:"
    free -h
    echo
    
    echo "File descriptor limits:"
    ulimit -n
    echo
    
    echo "Available disk space:"
    df -h /data
    echo
    
    echo "I/O schedulers:"
    for device in $(lsblk -nd -o NAME | grep -E '^(sd|nvme|vd)'); do
        if [ -f "/sys/block/$device/queue/scheduler" ]; then
            echo "$device: $(cat /sys/block/$device/queue/scheduler)"
        fi
    done
    echo
    
    echo "CPU governor:"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "Not available"
    echo
    
    echo "Transparent Huge Pages:"
    cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "Not available"
    echo
}

# Function to create optimized systemd service
create_systemd_service() {
    echo -e "${BLUE}Creating optimized systemd service...${NC}"
    
    if [ "$EUID" -eq 0 ]; then
        cat > /etc/systemd/system/erigon-mev.service << EOF
[Unit]
Description=Erigon Ethereum Client (MEV Optimized)
After=network.target
Wants=network.target

[Service]
Type=exec
User=lyftium
Group=lyftium
WorkingDirectory=/data/blockchain/storage/erigon
ExecStart=/data/blockchain/nodes/ethereum/erigon/source/build/bin/erigon \\
    --datadir=/data/blockchain/storage/erigon \\
    --chain=mainnet \\
    --prune.mode=archive \\
    --http \\
    --http.addr=0.0.0.0 \\
    --http.port=8545 \\
    --http.vhosts=localhost,eth.rpc.lyftium.com \\
    --http.api=eth,net,web3,txpool,erigon,debug,trace,engine,admin \\
    --http.corsdomain="*" \\
    --ws \\
    --ws.addr=0.0.0.0 \\
    --ws.port=8546 \\
    --ws.api=eth,net,web3,txpool,erigon,debug,trace \\
    --authrpc.addr=127.0.0.1 \\
    --authrpc.port=8551 \\
    --authrpc.jwtsecret=/data/blockchain/storage/erigon/jwt.hex \\
    --authrpc.vhosts=localhost \\
    --port=30304 \\
    --p2p.protocol=68,67 \\
    --private.api.addr=127.0.0.1:9091 \\
    --db.pagesize=64k \\
    --maxpeers=100 \\
    --txpool.accountslots=256 \\
    --txpool.globalslots=50000 \\
    --txpool.globalqueue=50000 \\
    --txpool.pricelimit=1 \\
    --txpool.pricebump=10 \\
    --log.console.verbosity=info \\
    --log.dir.path=/data/blockchain/storage/erigon/logs \\
    --log.dir.verbosity=3 \\
    --torrent.upload.rate=1gb \\
    --torrent.download.rate=2gb \\
    --sync.bodydownloadtimeout=60s \\
    --sync.receiptdownloadtimeout=60s \\
    --sync.loop.throttle=100ms \\
    --batchsize=2G \\
    --db.read.concurrency=2048 \\
    --db.size.limit=2TB \\
    --snapshots.enabled=true \\
    --snapshots.keep-blocks=256000 \\
    --checkpoint.sync=true \\
    --metrics \\
    --metrics.addr=0.0.0.0 \\
    --metrics.port=6060 \\
    --pprof \\
    --pprof.addr=127.0.0.1 \\
    --pprof.port=6061

Restart=on-failure
RestartSec=10

# Resource limits
LimitNOFILE=1048576
LimitNPROC=1048576

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/data/blockchain/storage/erigon

# Performance settings
Nice=-10
IOSchedulingClass=1
IOSchedulingPriority=4

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        echo "Systemd service created: erigon-mev.service"
        echo "Enable with: systemctl enable erigon-mev"
        echo "Start with: systemctl start erigon-mev"
    else
        echo "Skipping systemd service creation (requires root)"
    fi
}

# Function to optimize data directory
optimize_data_directory() {
    echo -e "${BLUE}Optimizing data directory...${NC}"
    
    local data_dir="/data/blockchain/storage/erigon"
    
    # Ensure proper ownership
    if [ "$EUID" -eq 0 ]; then
        chown -R lyftium:lyftium "$data_dir" 2>/dev/null || true
    fi
    
    # Create necessary directories with proper permissions
    mkdir -p "$data_dir"/{logs,snapshots,keystore,geth,migrations}
    
    # Set proper permissions
    chmod 755 "$data_dir"
    chmod 755 "$data_dir"/{logs,snapshots,keystore,geth,migrations}
    
    # Check available space
    local available_space=$(df /data | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    echo "Data directory optimized"
    echo "Available space: ${available_gb}GB"
    
    if [ $available_gb -lt 2000 ]; then
        echo -e "${YELLOW}Warning: Less than 2TB available space${NC}"
        echo "Ethereum archive node requires significant disk space"
    fi
}

# Function to show recommendations
show_recommendations() {
    echo -e "${GREEN}=== Optimization Recommendations ===${NC}"
    echo
    echo "1. Hardware Recommendations:"
    echo "   - CPU: 16+ cores recommended for fast sync"
    echo "   - RAM: 64GB+ recommended for archive mode"
    echo "   - Storage: NVMe SSD with 3TB+ free space"
    echo "   - Network: 1Gbps+ connection recommended"
    echo
    echo "2. Sync Strategy:"
    echo "   - Use checkpoint sync for faster initial sync"
    echo "   - Consider snapshot download for recent state"
    echo "   - Archive mode required for MEV operations"
    echo
    echo "3. MEV-Specific Requirements:"
    echo "   - Archive mode for historical transaction data"
    echo "   - Full transaction pool monitoring"
    echo "   - Debug and trace APIs enabled"
    echo "   - Low-latency network connection"
    echo
    echo "4. Monitoring:"
    echo "   - Use sync monitor: ./sync-monitor.sh --continuous"
    echo "   - Monitor system resources continuously"
    echo "   - Set up alerts for sync issues"
    echo
    echo "5. Performance Tips:"
    echo "   - Restart Erigon with optimized config: ./restart-erigon-optimized.sh"
    echo "   - Monitor peer count (should be >50)"
    echo "   - Check sync speed regularly"
}

# Main function
main() {
    echo "Starting system optimization for Erigon MEV operations..."
    echo
    
    # Show current settings
    check_current_settings
    
    # Apply optimizations
    optimize_kernel_parameters
    optimize_file_descriptors
    optimize_io_scheduler
    optimize_cpu_governor
    optimize_memory
    optimize_network
    optimize_data_directory
    create_systemd_service
    
    echo
    echo -e "${GREEN}System optimization completed!${NC}"
    echo
    
    show_recommendations
    
    if [ "$EUID" -eq 0 ]; then
        echo
        echo -e "${YELLOW}System restart recommended to apply all optimizations${NC}"
    fi
}

# Run main function
main "$@"