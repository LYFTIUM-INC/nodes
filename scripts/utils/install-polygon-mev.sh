#!/bin/bash

# Polygon MEV Node Installation Script
# Optimized for 64GB RAM system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="/data/blockchain/nodes/polygon"
USER="erigon"
GROUP="erigon"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root for security reasons"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check available memory
    TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$((TOTAL_MEM / 1024 / 1024))
    
    if [ $TOTAL_MEM_GB -lt 32 ]; then
        log_error "Insufficient memory. At least 32GB RAM required, found ${TOTAL_MEM_GB}GB"
        exit 1
    fi
    
    log_success "Memory check passed: ${TOTAL_MEM_GB}GB available"
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG "${DATA_DIR}" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ $AVAILABLE_SPACE -lt 1000 ]; then
        log_warning "Low disk space. Recommended: >1TB, available: ${AVAILABLE_SPACE}GB"
    fi
    
    log_success "Disk space check: ${AVAILABLE_SPACE}GB available"
}

# Download and install Polygon binaries
install_binaries() {
    log_info "Installing Polygon binaries..."
    
    BOR_VERSION="v1.4.1"
    HEIMDALL_VERSION="v1.0.9"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download Bor
    log_info "Downloading Bor ${BOR_VERSION}..."
    BOR_URL="https://github.com/maticnetwork/bor/releases/download/${BOR_VERSION}/bor-${BOR_VERSION}-linux-amd64.tar.gz"
    wget -q "$BOR_URL" -O bor.tar.gz
    tar -xzf bor.tar.gz
    sudo mv bor-${BOR_VERSION}-linux-amd64/bor /usr/local/bin/
    sudo chmod +x /usr/local/bin/bor
    
    # Download Heimdall
    log_info "Downloading Heimdall ${HEIMDALL_VERSION}..."
    HEIMDALL_URL="https://github.com/maticnetwork/heimdall/releases/download/${HEIMDALL_VERSION}/heimdall-${HEIMDALL_VERSION}-linux-amd64.tar.gz"
    wget -q "$HEIMDALL_URL" -O heimdall.tar.gz
    tar -xzf heimdall.tar.gz
    sudo mv heimdall-${HEIMDALL_VERSION}-linux-amd64/heimdall* /usr/local/bin/
    sudo chmod +x /usr/local/bin/heimdall*
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    log_success "Binaries installed successfully"
}

# Setup directories and permissions
setup_directories() {
    log_info "Setting up directories..."
    
    # Create data directories
    sudo mkdir -p "${DATA_DIR}/bor/data"
    sudo mkdir -p "${DATA_DIR}/heimdall/data"
    sudo mkdir -p "${DATA_DIR}/logs"
    
    # Set ownership
    sudo chown -R "${USER}:${GROUP}" "${DATA_DIR}"
    sudo chmod -R 755 "${DATA_DIR}"
    
    log_success "Directories created and permissions set"
}

# Initialize Heimdall
init_heimdall() {
    log_info "Initializing Heimdall..."
    
    HEIMDALL_HOME="${DATA_DIR}/heimdall/data"
    
    # Initialize if not already done
    if [ ! -f "${HEIMDALL_HOME}/config/genesis.json" ]; then
        sudo -u $USER heimdall init --home="$HEIMDALL_HOME" --chain-id=heimdall-137
        
        # Download genesis file
        sudo -u $USER wget -q https://raw.githubusercontent.com/maticnetwork/heimdall/master/builder/files/genesis-mainnet-v1.json \
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
        sudo -u $USER bor --datadir="$BOR_HOME" init /tmp/bor-genesis.json
        
        rm /tmp/bor-genesis.json
        log_success "Bor initialized"
    else
        log_info "Bor already initialized"
    fi
}

# Install systemd services
install_services() {
    log_info "Installing systemd services..."
    
    # Copy service files
    sudo cp "${SCRIPT_DIR}/../systemd/polygon-heimdall.service" /etc/systemd/system/
    sudo cp "${SCRIPT_DIR}/../systemd/polygon-bor.service" /etc/systemd/system/
    
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
    for i in {1..30}; do
        if curl -s http://localhost:1317/status > /dev/null 2>&1; then
            log_success "Heimdall is running"
            break
        fi
        sleep 5
        if [ $i -eq 30 ]; then
            log_error "Heimdall failed to start within timeout"
            exit 1
        fi
    done
    
    # Start Bor
    sudo systemctl start polygon-bor.service
    sleep 10
    
    # Wait for Bor to be ready
    log_info "Waiting for Bor to start..."
    for i in {1..30}; do
        if curl -s -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
           http://localhost:8548 > /dev/null 2>&1; then
            log_success "Bor is running"
            break
        fi
        sleep 5
        if [ $i -eq 30 ]; then
            log_error "Bor failed to start within timeout"
            exit 1
        fi
    done
}

# Check status
check_status() {
    log_info "Checking service status..."
    
    echo "=== Heimdall Status ==="
    sudo systemctl status polygon-heimdall.service --no-pager -l
    
    echo -e "\n=== Bor Status ==="
    sudo systemctl status polygon-bor.service --no-pager -l
    
    echo -e "\n=== RPC Tests ==="
    
    # Test Heimdall
    echo "Testing Heimdall RPC..."
    if curl -s http://localhost:1317/status | jq -r '.result.sync_info.catching_up' 2>/dev/null; then
        log_success "Heimdall RPC responding"
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
    
    # Check sync status
    echo "Checking sync status..."
    SYNC_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        http://localhost:8548 | jq -r '.result')
    
    if [ "$SYNC_STATUS" = "false" ]; then
        log_success "Node is fully synced"
    else
        log_info "Node is syncing..."
    fi
}

# Main execution
main() {
    log_info "Starting Polygon MEV Node Installation"
    
    check_root
    check_requirements
    
    # Ask for confirmation
    echo -e "\n${YELLOW}This will install and configure Polygon (Matic) node optimized for MEV operations.${NC}"
    echo -e "${YELLOW}The installation will use up to 12GB RAM for Bor and 3GB for Heimdall.${NC}"
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
    echo "Metrics: http://localhost:6061/metrics"
    echo -e "\n${YELLOW}=== Service Management ===${NC}"
    echo "Start: sudo systemctl start polygon-heimdall polygon-bor"
    echo "Stop: sudo systemctl stop polygon-bor polygon-heimdall"
    echo "Status: sudo systemctl status polygon-heimdall polygon-bor"
    echo "Logs: sudo journalctl -f -u polygon-bor"
}

# Run main function
main "$@"