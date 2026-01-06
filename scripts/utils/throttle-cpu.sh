#!/bin/bash

# Additional CPU throttling for Avalanche container
# Sets up cgroups limits for fine-grained control

CONTAINER_ID=$(docker inspect --format='{{.Id}}' avalanche-node 2>/dev/null)

if [ -n "$CONTAINER_ID" ]; then
    echo "Applying additional CPU throttling to container $CONTAINER_ID"
    
    # Find the cgroups path
    CGROUP_PATH="/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope"
    
    if [ -d "$CGROUP_PATH" ]; then
        # Set CPU bandwidth control (40% of one core, with 100ms period)
        echo "100000" | sudo tee "$CGROUP_PATH/cpu.cfs_period_us" > /dev/null
        echo "40000" | sudo tee "$CGROUP_PATH/cpu.cfs_quota_us" > /dev/null
        
        # Set CPU weight (lower priority)
        echo "100" | sudo tee "$CGROUP_PATH/cpu.weight" > /dev/null
        
        # Set nice level for lower priority
        echo "10" | sudo tee "$CGROUP_PATH/cpu.weight.nice" > /dev/null 2>/dev/null || true
        
        echo "CPU throttling applied successfully"
        echo "CPU quota: 40000/100000 (40%)"
        echo "CPU weight: 100 (low priority)"
    else
        echo "Cgroup path not found. Container may use systemd v2 cgroups."
        
        # Try systemd v2 path
        CGROUP_V2_PATH="/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope"
        if [ -d "$CGROUP_V2_PATH" ]; then
            echo "40000 100000" | sudo tee "$CGROUP_V2_PATH/cpu.max" > /dev/null
            echo "100" | sudo tee "$CGROUP_V2_PATH/cpu.weight" > /dev/null
            echo "CPU throttling applied via cgroups v2"
        fi
    fi
else
    echo "Avalanche container not found or not running"
fi