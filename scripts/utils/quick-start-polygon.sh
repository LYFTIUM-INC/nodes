#!/bin/bash

# Quick Start Polygon Node with Docker
# Simplified approach for MEV operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Create a simplified Docker Compose file
create_simple_compose() {
    log_info "Creating simplified Docker Compose configuration..."
    
    cat > "${SCRIPT_DIR}/docker-compose-simple.yml" << 'EOF'
version: '3.8'

services:
  polygon-heimdall:
    image: 0xpolygon/heimdall:latest
    container_name: polygon-heimdall
    restart: unless-stopped
    ports:
      - "26657:26657"
      - "1317:1317"
    volumes:
      - polygon_heimdall_data:/root/.heimdalld
    command: >
      start
      --home=/root/.heimdalld
      --chain=mainnet
      --rest-server
      --laddr=tcp://0.0.0.0:1317
    environment:
      - ETH_RPC_URL=https://ethereum-rpc.publicnode.com
      - GOGC=100
    mem_limit: 3g
    cpus: 1.0
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:1317/status"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 180s
    networks:
      - polygon_network

  polygon-bor:
    image: 0xpolygon/bor:latest
    container_name: polygon-bor
    restart: unless-stopped
    ports:
      - "8548:8545"
      - "8550:8546"
      - "30305:30303"
      - "6062:6060"
    volumes:
      - polygon_bor_data:/root/.bor
    command: >
      server
      --chain=mainnet
      --datadir=/root/.bor
      --http --http.addr=0.0.0.0 --http.port=8545
      --http.api=eth,net,web3,txpool,debug,trace,bor,admin
      --http.vhosts=*
      --http.corsdomain=*
      --ws --ws.addr=0.0.0.0 --ws.port=8546
      --ws.api=eth,net,web3,txpool,debug,trace,bor
      --ws.origins=*
      --syncmode=full
      --gcmode=archive
      --cache=8192
      --maxpeers=100
      --txpool.globalslots=81920
      --txpool.accountslots=128
      --txpool.globalqueue=20480
      --txpool.accountqueue=128
      --mine=false
      --metrics --metrics.addr=0.0.0.0 --metrics.port=6060
      --bor.heimdall=http://polygon-heimdall:1317
      --snapshot=true
      --log-level=info
    environment:
      - ETH_RPC_URL=https://ethereum-rpc.publicnode.com
      - GOGC=75
      - GOMAXPROCS=4
    mem_limit: 12g
    cpus: 4.0
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8545"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 300s
    networks:
      - polygon_network
    depends_on:
      polygon-heimdall:
        condition: service_healthy

networks:
  polygon_network:
    driver: bridge

volumes:
  polygon_bor_data:
    driver: local
  polygon_heimdall_data:
    driver: local
EOF
    
    log_success "Created simplified Docker Compose configuration"
}

# Start services
start_services() {
    log_info "Starting Polygon services..."
    
    cd "$SCRIPT_DIR"
    
    # Stop any existing containers
    docker-compose -f docker-compose-simple.yml down 2>/dev/null || true
    
    # Start Heimdall first
    log_info "Starting Heimdall..."
    docker-compose -f docker-compose-simple.yml up -d polygon-heimdall
    
    # Wait for Heimdall health check
    log_info "Waiting for Heimdall to become healthy..."
    for i in {1..60}; do
        if docker inspect polygon-heimdall --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
            log_success "Heimdall is healthy"
            break
        fi
        sleep 5
        if [ $((i % 6)) -eq 0 ]; then
            log_info "Still waiting for Heimdall... (${i}/60 attempts)"
        fi
    done
    
    if [ $i -eq 60 ]; then
        log_error "Heimdall failed to become healthy"
        return 1
    fi
    
    # Start Bor
    log_info "Starting Bor..."
    docker-compose -f docker-compose-simple.yml up -d polygon-bor
    
    # Wait for Bor health check
    log_info "Waiting for Bor to become healthy..."
    for i in {1..60}; do
        if docker inspect polygon-bor --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
            log_success "Bor is healthy"
            break
        fi
        sleep 5
        if [ $((i % 6)) -eq 0 ]; then
            log_info "Still waiting for Bor... (${i}/60 attempts)"
        fi
    done
    
    if [ $i -eq 60 ]; then
        log_warning "Bor health check timeout, but may still be starting..."
    fi
}

# Check status
check_status() {
    log_info "Checking service status..."
    
    echo ""
    echo -e "${BLUE}=== Container Status ===${NC}"
    docker-compose -f docker-compose-simple.yml ps
    
    echo ""
    echo -e "${BLUE}=== Health Status ===${NC}"
    echo "Heimdall: $(docker inspect polygon-heimdall --format='{{.State.Health.Status}}' 2>/dev/null || echo 'unknown')"
    echo "Bor: $(docker inspect polygon-bor --format='{{.State.Health.Status}}' 2>/dev/null || echo 'unknown')"
    
    echo ""
    echo -e "${BLUE}=== Port Status ===${NC}"
    local ports=("8548" "8550" "1317" "6062" "26657")
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "Port $port: ${GREEN}Open${NC}"
        else
            echo -e "Port $port: ${RED}Closed${NC}"
        fi
    done
    
    echo ""
    echo -e "${BLUE}=== RPC Tests ===${NC}"
    
    # Test Heimdall
    echo "Testing Heimdall RPC..."
    if HEIMDALL_RESULT=$(curl -s http://localhost:1317/status 2>/dev/null); then
        if echo "$HEIMDALL_RESULT" | jq -r '.result.sync_info.catching_up' 2>/dev/null; then
            local catching_up=$(echo "$HEIMDALL_RESULT" | jq -r '.result.sync_info.catching_up')
            if [ "$catching_up" = "false" ]; then
                echo -e "Heimdall: ${GREEN}Synced${NC}"
            else
                echo -e "Heimdall: ${YELLOW}Syncing${NC}"
            fi
        else
            echo -e "Heimdall: ${YELLOW}Starting${NC}"
        fi
    else
        echo -e "Heimdall: ${RED}Not responding${NC}"
    fi
    
    # Test Bor
    echo "Testing Bor RPC..."
    local block_number=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8548 2>/dev/null | jq -r '.result' 2>/dev/null)
    
    if [ -n "$block_number" ] && [ "$block_number" != "null" ]; then
        echo -e "Bor: ${GREEN}Block $((block_number))${NC}"
    else
        echo -e "Bor: ${RED}Not responding${NC}"
    fi
}

# Show logs
show_logs() {
    local service=${1:-""}
    
    if [ -n "$service" ]; then
        docker-compose -f docker-compose-simple.yml logs -f "$service"
    else
        docker-compose -f docker-compose-simple.yml logs -f
    fi
}

# Stop services
stop_services() {
    log_info "Stopping Polygon services..."
    docker-compose -f docker-compose-simple.yml down
    log_success "Services stopped"
}

# Main execution
main() {
    echo -e "${BLUE}=== Polygon MEV Node Quick Start ===${NC}"
    echo "Simplified deployment using Docker containers"
    echo ""
    
    create_simple_compose
    start_services
    
    # Give services a moment to start
    sleep 10
    
    check_status
    
    echo ""
    log_success "Polygon MEV node deployment completed!"
    echo ""
    echo -e "${GREEN}=== Connection Details ===${NC}"
    echo "Bor RPC: http://localhost:8548"
    echo "Bor WebSocket: ws://localhost:8550"
    echo "Heimdall API: http://localhost:1317"
    echo "Metrics: http://localhost:6062/metrics"
    echo ""
    echo -e "${YELLOW}=== Management Commands ===${NC}"
    echo "Stop: $0 stop"
    echo "Status: $0 status"
    echo "Logs: $0 logs [heimdall|bor]"
    echo "Health Check: ${SCRIPT_DIR}/polygon-health-check.sh"
    echo ""
    echo -e "${BLUE}=== Memory Allocation ===${NC}"
    echo "Heimdall: 3GB RAM limit"
    echo "Bor: 12GB RAM limit"
    echo "Total: 15GB of available 64GB system memory"
}

# Handle script arguments
case "${1:-}" in
    "stop")
        stop_services
        ;;
    "status")
        check_status
        ;;
    "logs")
        show_logs "${2:-}"
        ;;
    *)
        main
        ;;
esac