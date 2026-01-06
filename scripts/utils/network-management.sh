#!/bin/bash
# Network Bandwidth Management Script for Blockchain Nodes
# Configures traffic shaping, connection limits, and QoS

set -euo pipefail

# Network interface (auto-detect primary interface)
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "Primary network interface: $PRIMARY_INTERFACE"

# Bandwidth allocations (in Mbps)
declare -A NODE_BANDWIDTH_LIMITS=(
    ["ethereum"]="1000"       # 1 Gbps
    ["erigon"]="1000"         # 1 Gbps
    ["polygon-bor"]="500"     # 500 Mbps
    ["polygon-heimdall"]="200" # 200 Mbps
    ["optimism"]="400"        # 400 Mbps
    ["arbitrum"]="400"        # 400 Mbps
    ["base"]="400"            # 400 Mbps
    ["bsc"]="600"             # 600 Mbps
    ["avalanche"]="200"       # 200 Mbps
    ["solana"]="1000"         # 1 Gbps
)

# Maximum peer connections
declare -A NODE_MAX_PEERS=(
    ["ethereum"]="50"
    ["erigon"]="100"
    ["polygon-bor"]="50"
    ["polygon-heimdall"]="30"
    ["optimism"]="50"
    ["arbitrum"]="50"
    ["base"]="50"
    ["bsc"]="50"
    ["avalanche"]="30"
    ["solana"]="100"
)

# Connection rate limits (new connections per minute)
declare -A NODE_CONN_RATE=(
    ["ethereum"]="60"
    ["erigon"]="120"
    ["polygon-bor"]="60"
    ["polygon-heimdall"]="30"
    ["optimism"]="60"
    ["arbitrum"]="60"
    ["base"]="60"
    ["bsc"]="60"
    ["avalanche"]="30"
    ["solana"]="120"
)

# Port mappings for each node
declare -A NODE_PORTS=(
    ["ethereum"]="30303"
    ["erigon"]="30303"
    ["polygon-bor"]="30303"
    ["polygon-heimdall"]="26656"
    ["optimism"]="9003"
    ["arbitrum"]="8547"
    ["base"]="8545"
    ["bsc"]="30311"
    ["avalanche"]="9651"
    ["solana"]="8000-8020"
)

# Function to create tc (traffic control) rules
setup_tc_rules() {
    local node_name=$1
    local bandwidth_mbps=${NODE_BANDWIDTH_LIMITS[$node_name]:-100}
    local port=${NODE_PORTS[$node_name]:-"30303"}
    
    # Calculate bandwidth in kbps
    local bandwidth_kbps=$((bandwidth_mbps * 1000))
    local burst_kbps=$((bandwidth_kbps / 10))  # 10% burst
    
    # Create class ID based on node priority
    local class_id
    case $node_name in
        "ethereum"|"erigon") class_id="1:10" ;;
        "polygon-bor"|"polygon-heimdall") class_id="1:20" ;;
        "optimism"|"arbitrum"|"base") class_id="1:30" ;;
        "bsc") class_id="1:40" ;;
        "avalanche"|"solana") class_id="1:50" ;;
        *) class_id="1:99" ;;
    esac
    
    # Add tc class
    sudo tc class add dev "$PRIMARY_INTERFACE" parent 1: classid "$class_id" htb \
        rate "${bandwidth_kbps}kbit" burst "${burst_kbps}kbit" prio "${class_id##*:}" 2>/dev/null || \
        echo "Failed to add tc class for $node_name"
    
    # Add filter for node port
    if [[ $port == *"-"* ]]; then
        # Port range
        local start_port=${port%-*}
        local end_port=${port#*-}
        sudo tc filter add dev "$PRIMARY_INTERFACE" protocol ip parent 1:0 prio 1 u32 \
            match ip sport "$start_port" 0xffff \
            match ip dport "$start_port" 0xffff \
            flowid "$class_id" 2>/dev/null || echo "Failed to add tc filter for $node_name"
    else
        # Single port
        sudo tc filter add dev "$PRIMARY_INTERFACE" protocol ip parent 1:0 prio 1 u32 \
            match ip sport "$port" 0xffff flowid "$class_id" 2>/dev/null || \
            echo "Failed to add tc filter for $node_name sport"
        sudo tc filter add dev "$PRIMARY_INTERFACE" protocol ip parent 1:0 prio 1 u32 \
            match ip dport "$port" 0xffff flowid "$class_id" 2>/dev/null || \
            echo "Failed to add tc filter for $node_name dport"
    fi
}

# Function to setup iptables connection limits
setup_connection_limits() {
    local node_name=$1
    local max_peers=${NODE_MAX_PEERS[$node_name]:-50}
    local conn_rate=${NODE_CONN_RATE[$node_name]:-60}
    local port=${NODE_PORTS[$node_name]:-"30303"}
    
    # Create custom chain for the node
    sudo iptables -N "LIMIT_${node_name^^}" 2>/dev/null || true
    
    # Limit total connections
    sudo iptables -A "LIMIT_${node_name^^}" -p tcp --syn -m connlimit \
        --connlimit-above "$max_peers" --connlimit-mask 0 -j REJECT \
        --reject-with tcp-reset
    
    # Limit connection rate
    sudo iptables -A "LIMIT_${node_name^^}" -p tcp --syn -m hashlimit \
        --hashlimit-name "${node_name}_rate" \
        --hashlimit-above "${conn_rate}/min" \
        --hashlimit-burst "$((conn_rate * 2))" \
        --hashlimit-mode srcip -j DROP
    
    # Apply rules to node port
    if [[ $port == *"-"* ]]; then
        # Port range
        sudo iptables -A INPUT -p tcp --dport "$port" -j "LIMIT_${node_name^^}"
    else
        # Single port
        sudo iptables -A INPUT -p tcp --dport "$port" -j "LIMIT_${node_name^^}"
    fi
}

# Function to create nftables rules (modern alternative)
create_nftables_config() {
    cat > /data/blockchain/nodes/resource-management/configs/nftables-blockchain.conf << 'EOF'
#!/usr/sbin/nft -f

# Blockchain nodes network management
table inet blockchain {
    # Connection tracking
    set ethereum_peers {
        type ipv4_addr
        size 65536
        flags timeout
        timeout 1h
    }
    
    set polygon_peers {
        type ipv4_addr
        size 65536
        flags timeout
        timeout 1h
    }
    
    # Rate limiting
    set ratelimit_global {
        type ipv4_addr
        size 65536
        flags dynamic,timeout
        timeout 1m
    }
    
    chain input {
        type filter hook input priority 0; policy accept;
        
        # Ethereum/Erigon
        tcp dport 30303 ct state new add @ethereum_peers { ip saddr }
        tcp dport 30303 ct state new @ethereum_peers size > 50 drop
        
        # Polygon
        tcp dport { 30303, 26656 } ct state new add @polygon_peers { ip saddr }
        tcp dport { 30303, 26656 } ct state new @polygon_peers size > 50 drop
        
        # Global rate limiting
        ct state new add @ratelimit_global { ip saddr limit rate over 100/minute } drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
}

# Function to setup QoS with DSCP marking
setup_qos_marking() {
    local node_name=$1
    local port=${NODE_PORTS[$node_name]:-"30303"}
    
    # DSCP values (0-63)
    local dscp_value
    case $node_name in
        "ethereum"|"erigon") dscp_value="46" ;;  # EF (Expedited Forwarding)
        "polygon-bor"|"solana") dscp_value="34" ;;  # AF41
        "polygon-heimdall") dscp_value="26" ;;  # AF31
        "optimism"|"arbitrum"|"base") dscp_value="18" ;;  # AF21
        "bsc") dscp_value="10" ;;  # AF11
        *) dscp_value="0" ;;  # Best effort
    esac
    
    # Mark packets with DSCP
    if [[ $port != *"-"* ]]; then
        sudo iptables -t mangle -A OUTPUT -p tcp --sport "$port" -j DSCP --set-dscp "$dscp_value"
        sudo iptables -t mangle -A OUTPUT -p tcp --dport "$port" -j DSCP --set-dscp "$dscp_value"
    fi
}

# Function to create network namespace for isolation (optional)
create_network_namespace() {
    local node_name=$1
    local namespace="ns_${node_name}"
    
    # Create namespace
    sudo ip netns add "$namespace" 2>/dev/null || echo "Namespace $namespace already exists"
    
    # Create veth pair
    sudo ip link add "veth_${node_name}_host" type veth peer name "veth_${node_name}_ns"
    
    # Move one end to namespace
    sudo ip link set "veth_${node_name}_ns" netns "$namespace"
    
    # Configure addresses
    sudo ip addr add "10.${class_id##*:}.0.1/24" dev "veth_${node_name}_host"
    sudo ip netns exec "$namespace" ip addr add "10.${class_id##*:}.0.2/24" dev "veth_${node_name}_ns"
    
    # Bring up interfaces
    sudo ip link set "veth_${node_name}_host" up
    sudo ip netns exec "$namespace" ip link set "veth_${node_name}_ns" up
    sudo ip netns exec "$namespace" ip link set lo up
    
    echo "Created network namespace $namespace for isolation"
}

# Function to create systemd drop-in for network settings
create_network_dropin() {
    local node_name=$1
    local service_name=$2
    local bandwidth_mbps=${NODE_BANDWIDTH_LIMITS[$node_name]:-100}
    
    local dropin_dir="/data/blockchain/nodes/resource-management/systemd-dropins/${service_name}.d"
    mkdir -p "$dropin_dir"
    
    cat > "${dropin_dir}/network-limits.conf" << EOF
[Service]
# Network isolation (optional - uncomment to enable)
# PrivateNetwork=no
# RestrictAddressFamilies=AF_INET AF_INET6
# IPAccounting=yes
# IPAddressAllow=any
# IPAddressDeny=

# Bandwidth limits (systemd 240+)
# IPIngressBandwidth=${bandwidth_mbps}M
# IPEgressBandwidth=${bandwidth_mbps}M

# Socket limits
LimitNOFILE=65535
EOF
    
    echo "Created network drop-in for $service_name"
}

# Function to monitor network usage
create_network_monitor() {
    cat > /data/blockchain/nodes/resource-management/scripts/monitor-network.sh << 'EOF'
#!/bin/bash
# Network monitoring script for blockchain nodes

# Function to get network stats
get_network_stats() {
    local interface=$1
    local node_name=$2
    local port=$3
    
    # Get bytes transferred
    local rx_bytes=$(cat /sys/class/net/${interface}/statistics/rx_bytes)
    local tx_bytes=$(cat /sys/class/net/${interface}/statistics/tx_bytes)
    
    # Get connection count
    local conn_count=$(ss -tn state established "( sport = :${port} or dport = :${port} )" | wc -l)
    
    echo "$node_name: RX=$((rx_bytes/1024/1024))MB TX=$((tx_bytes/1024/1024))MB Connections=$conn_count"
}

# Monitor all nodes
while true; do
    clear
    echo "Blockchain Node Network Statistics - $(date)"
    echo "========================================"
    
    for node in ethereum erigon polygon-bor polygon-heimdall optimism arbitrum base bsc avalanche solana; do
        port=${NODE_PORTS[$node]:-"30303"}
        if [[ $port != *"-"* ]]; then
            get_network_stats "$PRIMARY_INTERFACE" "$node" "$port"
        fi
    done
    
    sleep 5
done
EOF
    
    chmod +x /data/blockchain/nodes/resource-management/scripts/monitor-network.sh
}

# Function to initialize traffic control
init_tc() {
    # Delete existing qdisc
    sudo tc qdisc del dev "$PRIMARY_INTERFACE" root 2>/dev/null || true
    
    # Create root qdisc
    sudo tc qdisc add dev "$PRIMARY_INTERFACE" root handle 1: htb default 99
    
    # Create root class (full bandwidth)
    local link_speed=$(ethtool "$PRIMARY_INTERFACE" 2>/dev/null | grep "Speed:" | awk '{print $2}' | sed 's/Mb\/s//')
    if [ -z "$link_speed" ]; then
        link_speed="10000"  # Default to 10Gbps
    fi
    
    sudo tc class add dev "$PRIMARY_INTERFACE" parent 1: classid 1:1 htb rate "${link_speed}mbit"
}

# Main execution
main() {
    echo "Starting network bandwidth management configuration..."
    
    # Check for required tools
    for tool in tc iptables ip ethtool ss; do
        if ! command -v $tool &> /dev/null; then
            echo "Error: $tool is not installed"
            exit 1
        fi
    done
    
    # Initialize traffic control
    init_tc
    
    # Create nftables config
    create_nftables_config
    
    # Create network monitor
    create_network_monitor
    
    # Process each node
    for node_name in "${!NODE_BANDWIDTH_LIMITS[@]}"; do
        echo "Configuring network for $node_name..."
        
        # Setup traffic control
        setup_tc_rules "$node_name"
        
        # Setup connection limits
        setup_connection_limits "$node_name"
        
        # Setup QoS marking
        setup_qos_marking "$node_name"
        
        # Find service and create drop-in
        for service_suffix in "" "-node" ".service"; do
            service_name="${node_name}${service_suffix}"
            if systemctl list-unit-files | grep -q "^${service_name}"; then
                create_network_dropin "$node_name" "$service_name"
                break
            fi
        done
    done
    
    # Save iptables rules
    sudo iptables-save > /data/blockchain/nodes/resource-management/configs/iptables-blockchain.rules
    
    echo "Network bandwidth management configuration completed."
    echo "Monitor network usage with: /data/blockchain/nodes/resource-management/scripts/monitor-network.sh"
}

# Run main function
main "$@"