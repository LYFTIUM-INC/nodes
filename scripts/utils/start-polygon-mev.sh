#!/bin/bash

# Quick Start Script for Polygon MEV Node
# Uses Docker Compose with optimized configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-mev-optimized.yml"

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

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check available memory
    local total_mem_gb=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}')
    if [ $total_mem_gb -lt 16 ]; then
        log_error "Insufficient memory. At least 16GB RAM required, found ${total_mem_gb}GB"
        exit 1
    fi
    
    log_success "System requirements check passed"
}

# Create necessary directories
setup_directories() {
    log_info "Setting up directories..."
    
    local dirs=(
        "/data/blockchain/nodes/polygon/heimdall/data"
        "/data/blockchain/nodes/polygon/bor/data"
        "/data/blockchain/nodes/polygon/config"
        "/data/blockchain/nodes/logs"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            sudo mkdir -p "$dir"
            sudo chown -R 1000:1000 "$dir"  # Default Docker user
            log_info "Created directory: $dir"
        fi
    done
    
    log_success "Directories setup completed"
}

# Download genesis files if needed
setup_genesis() {
    log_info "Setting up genesis files..."
    
    local heimdall_genesis="/data/blockchain/nodes/polygon/heimdall/data/config/genesis.json"
    local bor_genesis="/data/blockchain/nodes/polygon/bor/data/genesis.json"
    
    # Create config directory for Heimdall
    sudo mkdir -p "$(dirname "$heimdall_genesis")"
    
    # Download Heimdall genesis if not exists
    if [ ! -f "$heimdall_genesis" ]; then
        log_info "Downloading Heimdall genesis..."
        sudo wget -q https://raw.githubusercontent.com/maticnetwork/heimdall/master/builder/files/genesis-mainnet-v1.json \
            -O "$heimdall_genesis"
        sudo chown 1000:1000 "$heimdall_genesis"
    fi
    
    # Download Bor genesis if not exists
    if [ ! -f "$bor_genesis" ]; then
        log_info "Downloading Bor genesis..."
        sudo wget -q https://raw.githubusercontent.com/maticnetwork/bor/master/builder/files/genesis-mainnet-v1.json \
            -O "$bor_genesis"
        sudo chown 1000:1000 "$bor_genesis"
    fi
    
    log_success "Genesis files setup completed"
}

# Start the services
start_services() {
    log_info "Starting Polygon services..."
    
    cd "$SCRIPT_DIR"
    
    # Stop any existing containers
    docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    
    # Pull latest images
    log_info "Pulling latest Docker images..."
    docker-compose -f "$COMPOSE_FILE" pull
    
    # Start services
    log_info "Starting Heimdall first..."
    docker-compose -f "$COMPOSE_FILE" up -d polygon-heimdall
    
    # Wait for Heimdall to be ready
    log_info "Waiting for Heimdall to start (may take 2-3 minutes)..."
    local attempts=0
    while [ $attempts -lt 60 ]; do
        if curl -s http://localhost:1317/status >/dev/null 2>&1; then
            log_success "Heimdall is ready"
            break
        fi
        sleep 5
        attempts=$((attempts + 1))
        if [ $((attempts % 6)) -eq 0 ]; then
            log_info "Still waiting for Heimdall... (${attempts}/60 attempts)"
        fi
    done
    
    if [ $attempts -eq 60 ]; then
        log_error "Heimdall failed to start within timeout"
        return 1
    fi
    
    # Start Bor
    log_info "Starting Bor..."
    docker-compose -f "$COMPOSE_FILE" up -d polygon-bor
    
    # Wait for Bor to be ready
    log_info "Waiting for Bor to start..."
    attempts=0
    while [ $attempts -lt 30 ]; do
        if curl -s -X POST -H "Content-Type: application/json" \
           --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
           http://localhost:8548 >/dev/null 2>&1; then
            log_success "Bor is ready"
            break
        fi
        sleep 5
        attempts=$((attempts + 1))
        if [ $((attempts % 6)) -eq 0 ]; then
            log_info "Still waiting for Bor... (${attempts}/30 attempts)"
        fi
    done
    
    if [ $attempts -eq 30 ]; then
        log_error "Bor failed to start within timeout"
        return 1
    fi
    
    log_success "All services started successfully"
}

# Show status
show_status() {
    log_info "Checking service status..."
    
    echo ""
    echo -e "${BLUE}=== Container Status ===${NC}"
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    echo -e "${BLUE}=== Port Status ===${NC}"
    local ports=("8548" "8550" "1317" "6061" "26657")
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            echo -e "Port $port: ${GREEN}Open${NC}"
        else
            echo -e "Port $port: ${RED}Closed${NC}"
        fi
    done
    
    echo ""
    echo -e "${BLUE}=== Quick RPC Test ===${NC}"
    
    # Test Heimdall
    if curl -s http://localhost:1317/status | jq -r '.result.sync_info.catching_up' >/dev/null 2>&1; then
        local catching_up=$(curl -s http://localhost:1317/status | jq -r '.result.sync_info.catching_up')
        if [ "$catching_up" = "false" ]; then
            echo -e "Heimdall: ${GREEN}Synced${NC}"
        else
            echo -e "Heimdall: ${YELLOW}Syncing${NC}"
        fi
    else
        echo -e "Heimdall: ${RED}Not responding${NC}"
    fi
    
    # Test Bor
    local block_number=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8548 | jq -r '.result' 2>/dev/null)
    
    if [ -n "$block_number" ] && [ "$block_number" != "null" ]; then
        echo -e "Bor: ${GREEN}Block $((block_number))${NC}"
    else
        echo -e "Bor: ${RED}Not responding${NC}"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}=== Polygon MEV Node Startup ===${NC}"
    echo "This will start a Polygon node optimized for MEV operations"
    echo ""
    
    check_requirements
    setup_directories
    setup_genesis
    start_services
    show_status
    
    echo ""
    log_success "Polygon MEV node is running!"
    echo ""
    echo -e "${GREEN}=== Connection Details ===${NC}"
    echo "Bor RPC: http://localhost:8548"
    echo "Bor WebSocket: ws://localhost:8550"
    echo "Heimdall API: http://localhost:1317"
    echo "Metrics: http://localhost:6061/metrics"
    echo ""
    echo -e "${YELLOW}=== Management Commands ===${NC}"
    echo "Stop: docker-compose -f ${COMPOSE_FILE} down"
    echo "Restart: docker-compose -f ${COMPOSE_FILE} restart"
    echo "Logs: docker-compose -f ${COMPOSE_FILE} logs -f"
    echo "Health Check: ${SCRIPT_DIR}/polygon-health-check.sh"
    echo "Memory Monitor: ${SCRIPT_DIR}/monitor-polygon-memory.sh -c"
}

# Handle script arguments
case "${1:-}" in
    "stop")
        log_info "Stopping Polygon services..."
        docker-compose -f "$COMPOSE_FILE" down
        log_success "Services stopped"
        ;;
    "restart")
        log_info "Restarting Polygon services..."
        docker-compose -f "$COMPOSE_FILE" restart
        show_status
        ;;
    "status")
        show_status
        ;;
    "logs")
        docker-compose -f "$COMPOSE_FILE" logs -f
        ;;
    *)
        main
        ;;
esac