#!/bin/bash
# Disk I/O Management Script for Blockchain Nodes
# Configures I/O scheduling, priorities, and rate limiting

set -euo pipefail

# I/O scheduling classes
# 0 = none, 1 = realtime, 2 = best-effort, 3 = idle
declare -A NODE_IO_CLASS=(
    ["ethereum"]="1"      # Realtime
    ["erigon"]="1"        # Realtime
    ["polygon-bor"]="2"   # Best-effort
    ["polygon-heimdall"]="2" # Best-effort
    ["optimism"]="2"      # Best-effort
    ["arbitrum"]="2"      # Best-effort
    ["base"]="2"          # Best-effort
    ["bsc"]="2"           # Best-effort
    ["avalanche"]="3"     # Idle
    ["solana"]="1"        # Realtime
)

# I/O nice levels (0-7, lower = higher priority)
declare -A NODE_IO_NICE=(
    ["ethereum"]="0"
    ["erigon"]="0"
    ["polygon-bor"]="2"
    ["polygon-heimdall"]="3"
    ["optimism"]="3"
    ["arbitrum"]="3"
    ["base"]="3"
    ["bsc"]="2"
    ["avalanche"]="6"
    ["solana"]="1"
)

# I/O bandwidth limits (in MB/s, 0 = unlimited)
declare -A NODE_IO_READ_BPS=(
    ["ethereum"]="0"       # Unlimited
    ["erigon"]="0"         # Unlimited
    ["polygon-bor"]="200"  # 200 MB/s
    ["polygon-heimdall"]="100" # 100 MB/s
    ["optimism"]="150"     # 150 MB/s
    ["arbitrum"]="150"     # 150 MB/s
    ["base"]="150"         # 150 MB/s
    ["bsc"]="200"          # 200 MB/s
    ["avalanche"]="50"     # 50 MB/s
    ["solana"]="0"         # Unlimited
)

declare -A NODE_IO_WRITE_BPS=(
    ["ethereum"]="0"       # Unlimited
    ["erigon"]="0"         # Unlimited
    ["polygon-bor"]="150"  # 150 MB/s
    ["polygon-heimdall"]="75" # 75 MB/s
    ["optimism"]="100"     # 100 MB/s
    ["arbitrum"]="100"     # 100 MB/s
    ["base"]="100"         # 100 MB/s
    ["bsc"]="150"          # 150 MB/s
    ["avalanche"]="30"     # 30 MB/s
    ["solana"]="0"         # Unlimited
)

# Database optimization settings
declare -A NODE_DB_TYPE=(
    ["ethereum"]="leveldb"
    ["erigon"]="mdbx"
    ["polygon-bor"]="leveldb"
    ["polygon-heimdall"]="leveldb"
    ["optimism"]="leveldb"
    ["arbitrum"]="leveldb"
    ["base"]="leveldb"
    ["bsc"]="leveldb"
    ["avalanche"]="leveldb"
    ["solana"]="rocksdb"
)

# Function to get block device for a path
get_block_device() {
    local path=$1
    df "$path" | tail -1 | awk '{print $1}' | xargs lsblk -no PKNAME | head -1
}

# Function to configure I/O scheduler
configure_io_scheduler() {
    local device=$1
    local scheduler="mq-deadline"  # Good for databases
    
    if [ -e "/sys/block/${device}/queue/scheduler" ]; then
        echo "$scheduler" | sudo tee "/sys/block/${device}/queue/scheduler" > /dev/null 2>&1 || \
            echo "Failed to set I/O scheduler for $device"
        
        # Configure scheduler parameters
        if [ "$scheduler" = "mq-deadline" ]; then
            echo 100 | sudo tee "/sys/block/${device}/queue/iosched/read_expire" > /dev/null 2>&1
            echo 3000 | sudo tee "/sys/block/${device}/queue/iosched/write_expire" > /dev/null 2>&1
            echo 1 | sudo tee "/sys/block/${device}/queue/iosched/writes_starved" > /dev/null 2>&1
        fi
    fi
}

# Function to set I/O nice for process
set_io_nice() {
    local node_name=$1
    local pid=$2
    local io_class=${NODE_IO_CLASS[$node_name]:-2}
    local io_nice=${NODE_IO_NICE[$node_name]:-4}
    
    if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
        ionice -c "$io_class" -n "$io_nice" -p "$pid" 2>/dev/null || \
            echo "Failed to set I/O nice for $node_name (PID: $pid)"
    fi
}

# Function to configure cgroup I/O limits
configure_io_cgroup() {
    local node_name=$1
    local read_bps=${NODE_IO_READ_BPS[$node_name]:-0}
    local write_bps=${NODE_IO_WRITE_BPS[$node_name]:-0}
    
    if [ -d "/sys/fs/cgroup/blockchain/${node_name}" ]; then
        local cgroup_path="/sys/fs/cgroup/blockchain/${node_name}"
        
        # Get major:minor device numbers for data directories
        local data_dir="/data/blockchain/nodes/${node_name}"
        if [ -d "$data_dir" ]; then
            local device=$(get_block_device "$data_dir")
            local dev_major_minor=$(ls -l /dev/${device} | awk '{print $5 $6}' | tr -d ',')
            
            if [ -n "$dev_major_minor" ]; then
                # Set read bandwidth limit
                if [ "$read_bps" -gt 0 ]; then
                    local read_bps_bytes=$((read_bps * 1024 * 1024))
                    echo "${dev_major_minor} rbps=${read_bps_bytes}" | \
                        sudo tee "${cgroup_path}/io.max" > /dev/null 2>&1 || \
                        echo "Failed to set read bandwidth limit for $node_name"
                fi
                
                # Set write bandwidth limit
                if [ "$write_bps" -gt 0 ]; then
                    local write_bps_bytes=$((write_bps * 1024 * 1024))
                    echo "${dev_major_minor} wbps=${write_bps_bytes}" | \
                        sudo tee -a "${cgroup_path}/io.max" > /dev/null 2>&1 || \
                        echo "Failed to set write bandwidth limit for $node_name"
                fi
            fi
        fi
    fi
}

# Function to create database optimization config
create_db_optimization() {
    local node_name=$1
    local db_type=${NODE_DB_TYPE[$node_name]:-"leveldb"}
    local config_dir="/data/blockchain/nodes/resource-management/configs/${node_name}"
    
    mkdir -p "$config_dir"
    
    case $db_type in
        "leveldb")
            cat > "${config_dir}/db-optimization.conf" << EOF
# LevelDB optimization for $node_name
write_buffer_size=268435456        # 256MB
max_open_files=10000
block_size=16384                   # 16KB
block_cache_size=8589934592        # 8GB
bloom_filter_bits=10
compression=snappy
EOF
            ;;
        "mdbx")
            cat > "${config_dir}/db-optimization.conf" << EOF
# MDBX optimization for $node_name
MDBX_PAGESIZE=4096
MDBX_MAPSIZE=2TB
MDBX_READERS=256
MDBX_SYNC_MODE=nosync_safe
MDBX_WRITEMAP=1
EOF
            ;;
        "rocksdb")
            cat > "${config_dir}/db-optimization.conf" << EOF
# RocksDB optimization for $node_name
max_open_files=-1
max_background_jobs=16
max_write_buffer_number=6
write_buffer_size=134217728        # 128MB
target_file_size_base=134217728    # 128MB
max_bytes_for_level_base=536870912 # 512MB
compression_type=lz4
block_cache_size=8589934592        # 8GB
EOF
            ;;
    esac
}

# Function to create systemd drop-in for I/O settings
create_io_dropin() {
    local node_name=$1
    local service_name=$2
    local io_class=${NODE_IO_CLASS[$node_name]:-2}
    local io_nice=${NODE_IO_NICE[$node_name]:-4}
    local read_bps=${NODE_IO_READ_BPS[$node_name]:-0}
    local write_bps=${NODE_IO_WRITE_BPS[$node_name]:-0}
    
    local dropin_dir="/data/blockchain/nodes/resource-management/systemd-dropins/${service_name}.d"
    mkdir -p "$dropin_dir"
    
    cat > "${dropin_dir}/io-limits.conf" << EOF
[Service]
# I/O scheduling
IOSchedulingClass=${io_class}
IOSchedulingPriority=${io_nice}

# I/O bandwidth limits
$([ "$read_bps" -gt 0 ] && echo "IOReadBandwidthMax=/data/blockchain/nodes/${node_name} ${read_bps}M")
$([ "$write_bps" -gt 0 ] && echo "IOWriteBandwidthMax=/data/blockchain/nodes/${node_name} ${write_bps}M")

# I/O accounting
IOAccounting=yes

# Block I/O weight (100-1000, default 100)
IOWeight=$((1000 - io_nice * 100))
EOF
    
    echo "Created I/O drop-in for $service_name"
}

# Function to optimize filesystem mount options
optimize_mount_options() {
    local node_name=$1
    local data_dir="/data/blockchain/nodes/${node_name}"
    
    if [ -d "$data_dir" ]; then
        local mount_point=$(df "$data_dir" | tail -1 | awk '{print $6}')
        local device=$(df "$data_dir" | tail -1 | awk '{print $1}')
        local fs_type=$(mount | grep "^$device" | awk '{print $5}')
        
        echo "Recommended mount options for $node_name ($fs_type filesystem):"
        
        case $fs_type in
            "ext4")
                echo "  noatime,nodiratime,data=writeback,barrier=0,nobh,errors=remount-ro"
                ;;
            "xfs")
                echo "  noatime,nodiratime,nobarrier,logbufs=8,logbsize=256k"
                ;;
            "btrfs")
                echo "  noatime,nodiratime,compress=lzo,space_cache=v2,autodefrag"
                ;;
            "zfs")
                echo "  Set properties: compression=lz4, atime=off, xattr=sa, recordsize=128k"
                ;;
        esac
    fi
}

# Function to configure per-node I/O tuning
configure_node_io_tuning() {
    local node_name=$1
    
    # Create tuning script for the node
    cat > "/data/blockchain/nodes/resource-management/scripts/tune-${node_name}-io.sh" << 'EOF'
#!/bin/bash
# I/O tuning script for $node_name

# Increase read-ahead for sequential reads (blockchain data)
for device in $(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}'); do
    echo 4096 > /sys/block/${device}/queue/read_ahead_kb
done

# Optimize queue depth for NVMe
for device in $(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}'); do
    if [[ $device == nvme* ]]; then
        echo 1024 > /sys/block/${device}/queue/nr_requests
    fi
done

# Disable I/O merging for low latency
for device in $(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}'); do
    echo 2 > /sys/block/${device}/queue/nomerges
done
EOF
    
    chmod +x "/data/blockchain/nodes/resource-management/scripts/tune-${node_name}-io.sh"
}

# Function to get service PID
get_service_pid() {
    local service_name=$1
    systemctl show -p MainPID "$service_name" 2>/dev/null | cut -d= -f2
}

# Main execution
main() {
    echo "Starting I/O management configuration..."
    
    # Configure I/O scheduler for data devices
    for device in $(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}'); do
        echo "Configuring I/O scheduler for $device..."
        configure_io_scheduler "$device"
    done
    
    # Process each node
    for node_name in "${!NODE_IO_CLASS[@]}"; do
        echo "Configuring I/O for $node_name..."
        
        # Configure cgroup I/O settings
        configure_io_cgroup "$node_name"
        
        # Create database optimization config
        create_db_optimization "$node_name"
        
        # Create per-node tuning script
        configure_node_io_tuning "$node_name"
        
        # Show mount optimization recommendations
        optimize_mount_options "$node_name"
        
        # Find service and configure
        for service_suffix in "" "-node" ".service"; do
            service_name="${node_name}${service_suffix}"
            pid=$(get_service_pid "$service_name")
            
            if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
                # Set I/O nice
                set_io_nice "$node_name" "$pid"
                
                # Create systemd drop-in
                create_io_dropin "$node_name" "$service_name"
                
                break
            fi
        done
    done
    
    echo "I/O management configuration completed."
}

# Run main function
main "$@"