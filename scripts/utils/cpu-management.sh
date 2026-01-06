#!/bin/bash
# CPU Management Script for Blockchain Nodes
# This script configures CPU affinity, nice levels, and cgroups for optimal performance

set -euo pipefail

# Get total CPU cores
TOTAL_CORES=$(nproc)
HALF_CORES=$((TOTAL_CORES / 2))

# Node CPU allocation strategy
declare -A NODE_CPU_CONFIG=(
    # Critical nodes get dedicated cores
    ["ethereum"]="0-$((HALF_CORES-1))"
    ["erigon"]="0-$((HALF_CORES-1))"
    ["polygon-bor"]="$HALF_CORES-$((TOTAL_CORES-1))"
    ["polygon-heimdall"]="$HALF_CORES-$((TOTAL_CORES-1))"
    
    # Layer 2 nodes share cores
    ["optimism"]="0-$((TOTAL_CORES-1))"
    ["arbitrum"]="0-$((TOTAL_CORES-1))"
    ["base"]="0-$((TOTAL_CORES-1))"
    
    # Other chains
    ["bsc"]="0-$((TOTAL_CORES-1))"
    ["avalanche"]="0-$((TOTAL_CORES-1))"
    ["solana"]="0-$((TOTAL_CORES-1))"
)

# Nice levels (lower = higher priority)
declare -A NODE_NICE_LEVELS=(
    ["ethereum"]="-10"
    ["erigon"]="-10"
    ["polygon-bor"]="-5"
    ["polygon-heimdall"]="-5"
    ["optimism"]="0"
    ["arbitrum"]="0"
    ["base"]="0"
    ["bsc"]="5"
    ["avalanche"]="5"
    ["solana"]="5"
)

# CPU shares for cgroups (default is 1024)
declare -A NODE_CPU_SHARES=(
    ["ethereum"]="2048"
    ["erigon"]="2048"
    ["polygon-bor"]="1536"
    ["polygon-heimdall"]="1536"
    ["optimism"]="1024"
    ["arbitrum"]="1024"
    ["base"]="1024"
    ["bsc"]="768"
    ["avalanche"]="768"
    ["solana"]="768"
)

# Function to create cgroup v2 hierarchy
create_cgroup_v2() {
    local node_name=$1
    local cpu_shares=${NODE_CPU_SHARES[$node_name]:-1024}
    
    # Check if cgroup v2 is mounted
    if [ -d "/sys/fs/cgroup/blockchain" ]; then
        local cgroup_path="/sys/fs/cgroup/blockchain/${node_name}"
        
        # Create cgroup
        sudo mkdir -p "$cgroup_path"
        
        # Set CPU weight (cgroup v2 uses weight instead of shares)
        # Weight range is 1-10000, default is 100
        local cpu_weight=$((cpu_shares * 100 / 1024))
        echo "$cpu_weight" | sudo tee "${cgroup_path}/cpu.weight" > /dev/null
        
        # Set CPU max (optional - uncomment to limit CPU usage)
        # Format: "max_usage period" in microseconds
        # Example: "200000 1000000" = 20% of CPU
        # echo "max 1000000" | sudo tee "${cgroup_path}/cpu.max" > /dev/null
        
        echo "Created cgroup v2 for $node_name with CPU weight $cpu_weight"
    else
        echo "Warning: cgroup v2 not available at /sys/fs/cgroup/blockchain"
    fi
}

# Function to apply CPU affinity
apply_cpu_affinity() {
    local node_name=$1
    local pid=$2
    local cpu_list=${NODE_CPU_CONFIG[$node_name]:-"0-$((TOTAL_CORES-1))"}
    
    if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
        taskset -acp "$cpu_list" "$pid" 2>/dev/null || echo "Failed to set CPU affinity for $node_name (PID: $pid)"
    fi
}

# Function to set nice level
set_nice_level() {
    local node_name=$1
    local pid=$2
    local nice_level=${NODE_NICE_LEVELS[$node_name]:-0}
    
    if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
        renice "$nice_level" -p "$pid" 2>/dev/null || echo "Failed to set nice level for $node_name (PID: $pid)"
    fi
}

# Function to get PID from systemd service
get_service_pid() {
    local service_name=$1
    systemctl show -p MainPID "$service_name" 2>/dev/null | cut -d= -f2
}

# Main execution
main() {
    echo "Starting CPU resource management configuration..."
    echo "Total CPU cores: $TOTAL_CORES"
    
    # Create cgroup hierarchy
    if [ ! -d "/sys/fs/cgroup/blockchain" ]; then
        sudo mkdir -p /sys/fs/cgroup/blockchain
    fi
    
    # Process each node
    for node_name in "${!NODE_CPU_CONFIG[@]}"; do
        echo "Configuring $node_name..."
        
        # Create cgroup
        create_cgroup_v2 "$node_name"
        
        # Find service name (try different variations)
        for service_suffix in "" "-node" ".service"; do
            service_name="${node_name}${service_suffix}"
            pid=$(get_service_pid "$service_name")
            
            if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
                echo "Found $node_name with PID: $pid"
                
                # Apply CPU affinity
                apply_cpu_affinity "$node_name" "$pid"
                
                # Set nice level
                set_nice_level "$node_name" "$pid"
                
                # Add to cgroup
                echo "$pid" | sudo tee "/sys/fs/cgroup/blockchain/${node_name}/cgroup.procs" > /dev/null 2>&1 || \
                    echo "Failed to add $node_name to cgroup"
                
                break
            fi
        done
    done
    
    echo "CPU resource management configuration completed."
}

# Run main function
main "$@"