#!/bin/bash

# Install Polygon binaries directly
# Optimized for MEV operations on 64GB system

set -e

# Configuration
BOR_VERSION="v1.3.7"
HEIMDALL_VERSION="v1.0.9"
INSTALL_DIR="/usr/local/bin"
DATA_DIR="/data/blockchain/nodes/polygon"
USER="erigon"
GROUP="erigon"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we have sudo access
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo access"
        exit 1
    fi
}

# Download and install binaries
install_binaries() {
    log_info "Installing Polygon binaries..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download Bor
    log_info "Downloading Bor ${BOR_VERSION}..."
    BOR_URL="https://github.com/maticnetwork/bor/releases/download/${BOR_VERSION}/bor-${BOR_VERSION}-linux-amd64.tar.gz"
    
    if wget -q "$BOR_URL" -O bor.tar.gz; then
        tar -xzf bor.tar.gz
        sudo mv bor-${BOR_VERSION}-linux-amd64/bor "$INSTALL_DIR/"
        sudo chmod +x "$INSTALL_DIR/bor"
        log_success "Bor installed successfully"
    else
        log_error "Failed to download Bor"
        exit 1
    fi
    
    # Download Heimdall
    log_info "Downloading Heimdall ${HEIMDALL_VERSION}..."
    HEIMDALL_URL="https://github.com/maticnetwork/heimdall/releases/download/${HEIMDALL_VERSION}/heimdall-${HEIMDALL_VERSION}-linux-amd64.tar.gz"
    
    if wget -q "$HEIMDALL_URL" -O heimdall.tar.gz; then
        tar -xzf heimdall.tar.gz
        sudo mv heimdall-${HEIMDALL_VERSION}-linux-amd64/heimdall* "$INSTALL_DIR/"
        sudo chmod +x "$INSTALL_DIR/heimdall"*
        log_success "Heimdall installed successfully"
    else
        log_error "Failed to download Heimdall"
        exit 1
    fi
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    # Verify installations
    log_info "Verifying installations..."
    "$INSTALL_DIR/bor" version
    "$INSTALL_DIR/heimdall" version
}

# Setup directories
setup_directories() {
    log_info "Setting up directories..."
    
    # Create data directories
    sudo mkdir -p "${DATA_DIR}/bor/data"
    sudo mkdir -p "${DATA_DIR}/heimdall/data"
    sudo mkdir -p "${DATA_DIR}/logs"
    
    # Set ownership
    sudo chown -R "${USER}:${GROUP}" "${DATA_DIR}"
    sudo chmod -R 755 "${DATA_DIR}"
    
    log_success "Directories created successfully"
}

# Initialize Heimdall
init_heimdall() {
    log_info "Initializing Heimdall..."
    
    HEIMDALL_HOME="${DATA_DIR}/heimdall/data"
    
    # Initialize if not already done
    if [ ! -f "${HEIMDALL_HOME}/config/genesis.json" ]; then
        sudo -u "$USER" "$INSTALL_DIR/heimdall" init --home="$HEIMDALL_HOME" --chain-id=heimdall-137
        
        # Download genesis file
        sudo -u "$USER" wget -q https://raw.githubusercontent.com/maticnetwork/heimdall/master/builder/files/genesis-mainnet-v1.json \
            -O "${HEIMDALL_HOME}/config/genesis.json"
        
        log_success "Heimdall initialized"
    else
        log_info "Heimdall already initialized"
    fi
}

# Initialize Bor
init_bor() {
    log_info "Initializing Bor..."
    
    BOR_HOME="${DATA_DIR}/bor/data"
    
    # Initialize if not already done
    if [ ! -f "${BOR_HOME}/genesis.json" ]; then
        # Download genesis file
        wget -q https://raw.githubusercontent.com/maticnetwork/bor/master/builder/files/genesis-mainnet-v1.json \
            -O /tmp/bor-genesis.json
        
        # Initialize with genesis
        sudo -u "$USER" "$INSTALL_DIR/bor" --datadir="$BOR_HOME" init /tmp/bor-genesis.json
        
        rm /tmp/bor-genesis.json
        log_success "Bor initialized"
    else
        log_info "Bor already initialized"
    fi
}

# Install systemd services
install_services() {
    log_info "Installing systemd services..."
    
    # Create improved systemd service files
    cat > /tmp/polygon-heimdall.service << 'EOF'
[Unit]
Description=Polygon Heimdall Node (MEV Optimized)
After=network.target
Wants=network.target

[Service]
Type=simple
User=erigon
Group=erigon
ExecStartPre=/bin/mkdir -p /data/blockchain/nodes/polygon/heimdall/data
ExecStartPre=/bin/chown -R erigon:erigon /data/blockchain/nodes/polygon/heimdall/data
ExecStart=/usr/local/bin/heimdall start \
    --home=/data/blockchain/nodes/polygon/heimdall/data \
    --chain=mainnet \
    --seeds=1500161dd491b67fb1ac81868952be49e2509c9f@52.78.36.216:26656,dd4a3f1750af5765266231b9d8ac764599921736@3.36.224.80:26656,8ea4f592ad6cc38d7532aff418d1fb97052463af@34.240.245.39:26656,e772e1fb8c3492a9570a377a5eafdb1dc53cd778@54.194.245.5:26656 \
    --rest-server \
    --laddr=tcp://0.0.0.0:1317 \
    --rpc.unsafe \
    --log_level=info
Restart=always
RestartSec=5
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=30
LimitNOFILE=65536
LimitNPROC=32768

# Memory optimization
Environment=GOGC=100
Environment=ETH_RPC_URL=https://ethereum-rpc.publicnode.com

# Process limits
MemoryMax=3G
CPUQuota=100%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/data/blockchain/nodes/polygon/heimdall
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
EOF

    cat > /tmp/polygon-bor.service << 'EOF'
[Unit]
Description=Polygon Bor Node (MEV Optimized)
After=network.target polygon-heimdall.service
Wants=network.target
Requires=polygon-heimdall.service

[Service]
Type=simple
User=erigon
Group=erigon
ExecStartPre=/bin/mkdir -p /data/blockchain/nodes/polygon/bor/data
ExecStartPre=/bin/chown -R erigon:erigon /data/blockchain/nodes/polygon/bor/data
ExecStart=/usr/local/bin/bor server \
    --chain=mainnet \
    --datadir=/data/blockchain/nodes/polygon/bor/data \
    --identity="mev-polygon-node" \
    --http --http.addr=0.0.0.0 --http.port=8548 \
    --http.api=eth,net,web3,txpool,debug,trace,bor,admin \
    --http.vhosts=* \
    --http.corsdomain=* \
    --ws --ws.addr=0.0.0.0 --ws.port=8550 \
    --ws.api=eth,net,web3,txpool,debug,trace,bor \
    --ws.origins=* \
    --syncmode=full \
    --gcmode=archive \
    --cache=8192 \
    --cache.database=2048 \
    --cache.trie=2048 \
    --cache.gc=1024 \
    --cache.snapshot=1024 \
    --cache.noprefetch=false \
    --maxpeers=100 \
    --p2p.maxpendpeers=50 \
    --port=30305 \
    --txpool.locals= \
    --txpool.nolocals=false \
    --txpool.journal=/data/blockchain/nodes/polygon/bor/data/txpool.journal \
    --txpool.rejournal=1h \
    --txpool.pricelimit=1 \
    --txpool.pricebump=10 \
    --txpool.accountslots=128 \
    --txpool.globalslots=81920 \
    --txpool.accountqueue=128 \
    --txpool.globalqueue=20480 \
    --txpool.lifetime=3h \
    --mine=false \
    --miner.gaslimit=30000000 \
    --metrics --metrics.addr=0.0.0.0 --metrics.port=6062 \
    --bor.heimdall=http://localhost:1317 \
    --bor.runheimdall=false \
    --bor.useheimdallapp=false \
    --bor.logs=false \
    --snapshot=true \
    --log-level=info \
    --verbosity=3 \
    --bootnodes=enode://0cb82b395094ee4a2915e9714894627de9ed8498fb881cec6db7c65e8b9a5bd7@3.93.224.197:30303,enode://88116f4295f5a31538ae409e4d44ad40d22e44ee9342869e7d68bdec55b0f83c@34.226.134.117:30303
Restart=always
RestartSec=10
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=60
LimitNOFILE=65536
LimitNPROC=32768

# Memory optimization
Environment=GOGC=75
Environment=GOMAXPROCS=4
Environment=ETH_RPC_URL=https://ethereum-rpc.publicnode.com

# Process limits for 64GB system
MemoryMax=12G
CPUQuota=400%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/data/blockchain/nodes/polygon/bor
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
EOF

    # Install service files
    sudo mv /tmp/polygon-heimdall.service /etc/systemd/system/
    sudo mv /tmp/polygon-bor.service /etc/systemd/system/
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    # Enable services
    sudo systemctl enable polygon-heimdall.service
    sudo systemctl enable polygon-bor.service
    
    log_success "Systemd services installed and enabled"
}

# Start services
start_services() {
    log_info "Starting Polygon services..."
    
    # Start Heimdall first
    sudo systemctl start polygon-heimdall.service
    sleep 10
    
    # Wait for Heimdall to be ready
    log_info "Waiting for Heimdall to start..."
    for i in {1..60}; do
        if curl -s http://localhost:1317/status > /dev/null 2>&1; then
            log_success "Heimdall is running"
            break
        fi
        sleep 5
        if [ $i -eq 60 ]; then
            log_error "Heimdall failed to start within timeout"
            return 1
        fi
    done
    
    # Start Bor
    sudo systemctl start polygon-bor.service
    sleep 10
    
    # Wait for Bor to be ready
    log_info "Waiting for Bor to start..."
    for i in {1..60}; do
        if curl -s -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
           http://localhost:8548 > /dev/null 2>&1; then
            log_success "Bor is running"
            break
        fi
        sleep 5
        if [ $i -eq 60 ]; then
            log_error "Bor failed to start within timeout"
            return 1
        fi
    done
}

# Check status
check_status() {
    log_info "Checking service status..."
    
    echo "=== Service Status ==="
    sudo systemctl status polygon-heimdall.service --no-pager -l | head -10
    echo ""
    sudo systemctl status polygon-bor.service --no-pager -l | head -10
    
    echo -e "\n=== RPC Tests ==="
    
    # Test Heimdall
    echo "Testing Heimdall RPC..."
    if HEIMDALL_STATUS=$(curl -s http://localhost:1317/status); then
        if echo "$HEIMDALL_STATUS" | jq -r '.result.sync_info.catching_up' 2>/dev/null; then
            log_success "Heimdall RPC responding"
        fi
    else
        log_error "Heimdall RPC not responding"
    fi
    
    # Test Bor
    echo "Testing Bor RPC..."
    BLOCK_NUMBER=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8548 | jq -r '.result' 2>/dev/null)
    
    if [ "$BLOCK_NUMBER" != "null" ] && [ -n "$BLOCK_NUMBER" ]; then
        echo "Current block: $BLOCK_NUMBER"
        log_success "Bor RPC responding"
    else
        log_error "Bor RPC not responding"
    fi
}

# Main execution
main() {
    log_info "Starting Polygon Binary Installation"
    
    check_sudo
    
    # Ask for confirmation
    echo -e "\n${YELLOW}This will install Polygon binaries and configure services for MEV operations.${NC}"
    echo -e "${YELLOW}Memory allocation: Heimdall 3GB, Bor 12GB (total 15GB of 64GB system)${NC}"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    install_binaries
    setup_directories
    init_heimdall
    init_bor
    install_services
    start_services
    check_status
    
    log_success "Polygon MEV node installation completed!"
    echo -e "\n${GREEN}=== Node Information ===${NC}"
    echo "Bor RPC: http://localhost:8548"
    echo "Bor WebSocket: ws://localhost:8550"
    echo "Heimdall API: http://localhost:1317"
    echo "Metrics: http://localhost:6062/metrics"
    echo -e "\n${YELLOW}=== Service Management ===${NC}"
    echo "Start: sudo systemctl start polygon-heimdall polygon-bor"
    echo "Stop: sudo systemctl stop polygon-bor polygon-heimdall"
    echo "Status: sudo systemctl status polygon-heimdall polygon-bor"
    echo "Logs: sudo journalctl -f -u polygon-bor"
}

# Run main function
main "$@"