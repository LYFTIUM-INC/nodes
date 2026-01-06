#!/bin/bash
# Memory Management Script for Blockchain Nodes
# Configures memory limits, swap policies, and OOM priorities

set -euo pipefail

# Get total memory in MB
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))

echo "Total system memory: ${TOTAL_MEM_GB}GB"

# Memory allocation per node (in MB)
declare -A NODE_MEMORY_LIMITS=(
    # Ethereum nodes need significant memory
    ["ethereum"]="32768"      # 32GB
    ["erigon"]="65536"        # 64GB
    
    # Polygon nodes
    ["polygon-bor"]="16384"   # 16GB
    ["polygon-heimdall"]="8192" # 8GB
    
    # Layer 2 nodes
    ["optimism"]="16384"      # 16GB
    ["arbitrum"]="16384"      # 16GB
    ["base"]="16384"          # 16GB
    
    # Other chains
    ["bsc"]="32768"           # 32GB
    ["avalanche"]="8192"      # 8GB
    ["solana"]="65536"        # 64GB
)

# OOM score adjustment (-1000 to 1000, lower = less likely to be killed)
declare -A NODE_OOM_SCORES=(
    ["ethereum"]="-500"
    ["erigon"]="-500"
    ["polygon-bor"]="-300"
    ["polygon-heimdall"]="-300"
    ["optimism"]="-200"
    ["arbitrum"]="-200"
    ["base"]="-200"
    ["bsc"]="-100"
    ["avalanche"]="0"
    ["solana"]="-400"
)

# Swap memory percentage allowed (0-100)
declare -A NODE_SWAP_LIMITS=(
    ["ethereum"]="10"
    ["erigon"]="5"
    ["polygon-bor"]="20"
    ["polygon-heimdall"]="30"
    ["optimism"]="20"
    ["arbitrum"]="20"
    ["base"]="20"
    ["bsc"]="15"
    ["avalanche"]="40"
    ["solana"]="5"
)

# Function to create memory cgroup settings
configure_memory_cgroup() {
    local node_name=$1
    local memory_limit_mb=${NODE_MEMORY_LIMITS[$node_name]:-8192}
    local swap_limit_percent=${NODE_SWAP_LIMITS[$node_name]:-20}
    
    if [ -d "/sys/fs/cgroup/blockchain/${node_name}" ]; then
        local cgroup_path="/sys/fs/cgroup/blockchain/${node_name}"
        
        # Set memory limit (in bytes)
        local memory_limit_bytes=$((memory_limit_mb * 1024 * 1024))
        echo "$memory_limit_bytes" | sudo tee "${cgroup_path}/memory.max" > /dev/null 2>&1 || \
            echo "Failed to set memory limit for $node_name"
        
        # Set swap limit
        local swap_limit_bytes=$((memory_limit_bytes * swap_limit_percent / 100))
        echo "$swap_limit_bytes" | sudo tee "${cgroup_path}/memory.swap.max" > /dev/null 2>&1 || \
            echo "Failed to set swap limit for $node_name"
        
        # Set memory.high (soft limit at 90% of hard limit)
        local memory_high_bytes=$((memory_limit_bytes * 90 / 100))
        echo "$memory_high_bytes" | sudo tee "${cgroup_path}/memory.high" > /dev/null 2>&1 || \
            echo "Failed to set memory.high for $node_name"
        
        echo "Configured memory for $node_name: limit=${memory_limit_mb}MB, swap=${swap_limit_percent}%"
    fi
}

# Function to set OOM score
set_oom_score() {
    local node_name=$1
    local pid=$2
    local oom_score=${NODE_OOM_SCORES[$node_name]:-0}
    
    if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
        echo "$oom_score" | sudo tee "/proc/$pid/oom_score_adj" > /dev/null 2>&1 || \
            echo "Failed to set OOM score for $node_name (PID: $pid)"
    fi
}

# Function to optimize garbage collection
optimize_gc_settings() {
    local node_name=$1
    
    case $node_name in
        "ethereum"|"erigon")
            # Go-based nodes
            echo "GOGC=50"
            echo "GOMEMLIMIT=30GiB"
            ;;
        "polygon-bor")
            # Bor specific settings
            echo "GOGC=100"
            echo "GOMEMLIMIT=14GiB"
            ;;
        "solana")
            # Rust-based node
            echo "RUST_MIN_STACK=8388608"
            ;;
        *)
            # Default Go settings
            echo "GOGC=100"
            ;;
    esac
}

# Function to create systemd drop-in for memory settings
create_memory_dropin() {
    local node_name=$1
    local service_name=$2
    local memory_limit_mb=${NODE_MEMORY_LIMITS[$node_name]:-8192}
    local oom_score=${NODE_OOM_SCORES[$node_name]:-0}
    
    local dropin_dir="/data/blockchain/nodes/resource-management/systemd-dropins/${service_name}.d"
    mkdir -p "$dropin_dir"
    
    cat > "${dropin_dir}/memory-limits.conf" << EOF
[Service]
# Memory limits
MemoryMax=${memory_limit_mb}M
MemoryHigh=$((memory_limit_mb * 90 / 100))M
MemorySwapMax=$((memory_limit_mb * NODE_SWAP_LIMITS[$node_name] / 100))M

# OOM settings
OOMScoreAdjust=${oom_score}
OOMPolicy=stop

# Garbage collection optimization
$(optimize_gc_settings "$node_name" | sed 's/^/Environment=/')

# Memory accounting
MemoryAccounting=yes
EOF
    
    echo "Created memory drop-in for $service_name"
}

# Function to configure system-wide memory settings
configure_system_memory() {
    echo "Configuring system-wide memory settings..."
    
    # Configure swappiness (lower = less swap usage)
    echo 10 | sudo tee /proc/sys/vm/swappiness > /dev/null
    
    # Configure cache pressure (higher = more aggressive cache reclaim)
    echo 50 | sudo tee /proc/sys/vm/vfs_cache_pressure > /dev/null
    
    # Configure dirty ratio (percentage of memory that can be dirty)
    echo 10 | sudo tee /proc/sys/vm/dirty_ratio > /dev/null
    echo 5 | sudo tee /proc/sys/vm/dirty_background_ratio > /dev/null
    
    # Configure OOM killer behavior
    echo 1 | sudo tee /proc/sys/vm/oom_kill_allocating_task > /dev/null
    
    # Make settings persistent
    cat > /data/blockchain/nodes/resource-management/configs/sysctl-memory.conf << EOF
# Memory management settings for blockchain nodes
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.oom_kill_allocating_task = 1
vm.overcommit_memory = 1
vm.overcommit_ratio = 80
EOF
    
    echo "System memory settings configured"
}

# Function to get service PID
get_service_pid() {
    local service_name=$1
    systemctl show -p MainPID "$service_name" 2>/dev/null | cut -d= -f2
}

# Main execution
main() {
    echo "Starting memory management configuration..."
    
    # Configure system-wide settings
    configure_system_memory
    
    # Process each node
    for node_name in "${!NODE_MEMORY_LIMITS[@]}"; do
        echo "Configuring memory for $node_name..."
        
        # Configure cgroup memory settings
        configure_memory_cgroup "$node_name"
        
        # Find service and configure
        for service_suffix in "" "-node" ".service"; do
            service_name="${node_name}${service_suffix}"
            pid=$(get_service_pid "$service_name")
            
            if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
                # Set OOM score
                set_oom_score "$node_name" "$pid"
                
                # Create systemd drop-in
                create_memory_dropin "$node_name" "$service_name"
                
                break
            fi
        done
    done
    
    echo "Memory management configuration completed."
    echo "Note: Restart services for systemd drop-in changes to take effect."
}

# Run main function
main "$@"