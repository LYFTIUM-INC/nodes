#!/bin/bash
set -e

# Lighthouse Beacon Node Deployment Script
# Optimized for MEV operations with checkpoint sync

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STORAGE_DIR="/data/blockchain/storage"
LIGHTHOUSE_DIR="${STORAGE_DIR}/lighthouse"
ERIGON_DIR="${STORAGE_DIR}/erigon"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed"
    fi
    
    # Check if blockchain network exists
    if ! docker network ls | grep -q blockchain_network; then
        log "Creating blockchain_network..."
        docker network create blockchain_network || true
    fi
    
    log "Prerequisites check completed"
}

# Create directory structure
create_directories() {
    log "Creating directory structure..."
    
    # Create necessary directories
    mkdir -p "${LIGHTHOUSE_DIR}"/{beacon,validator}
    mkdir -p "${SCRIPT_DIR}"/{config,validator-keys}
    mkdir -p "${ERIGON_DIR}"
    
    # Set proper permissions
    chmod -R 755 "${LIGHTHOUSE_DIR}"
    
    log "Directory structure created"
}

# Stop existing services
stop_existing_services() {
    log "Stopping existing services..."
    
    cd "$SCRIPT_DIR"
    docker-compose -f docker-compose-optimized.yml down || true
    
    # Also stop any standalone beacon services
    docker stop lighthouse-beacon lighthouse-validator mev-boost jwt-generator 2>/dev/null || true
    docker rm lighthouse-beacon lighthouse-validator mev-boost jwt-generator 2>/dev/null || true
    
    log "Existing services stopped"
}

# Check Erigon status
check_erigon_status() {
    log "Checking Erigon execution client status..."
    
    # Check if Erigon is running
    if ! docker ps | grep -q erigon; then
        warning "Erigon is not running. Lighthouse beacon node requires an execution client."
        warning "Please ensure Erigon is running before starting Lighthouse."
        
        read -p "Do you want to start Erigon now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            start_erigon
        else
            error "Cannot proceed without execution client"
        fi
    else
        info "Erigon is running"
        
        # Check if JWT auth is enabled
        if docker exec erigon ps aux | grep -q "authrpc.jwtsecret"; then
            info "Erigon has JWT authentication enabled"
        else
            warning "Erigon may not have JWT authentication enabled"
            warning "Lighthouse requires JWT authentication for Engine API"
        fi
    fi
}

# Start Erigon if needed
start_erigon() {
    log "Starting Erigon execution client..."
    
    cd "$SCRIPT_DIR"
    docker-compose -f docker-compose-optimized.yml up -d jwt-generator
    
    # Wait for JWT secret
    sleep 5
    
    docker-compose -f docker-compose-optimized.yml up -d erigon
    
    # Wait for Erigon to be ready
    log "Waiting for Erigon to be ready..."
    for i in {1..60}; do
        if docker exec erigon curl -s http://localhost:8545 &>/dev/null; then
            log "Erigon is ready"
            break
        fi
        sleep 5
    done
}

# Deploy Lighthouse beacon node
deploy_lighthouse() {
    log "Deploying Lighthouse beacon node..."
    
    cd "$SCRIPT_DIR"
    
    # Generate JWT secret first
    docker-compose -f docker-compose-optimized.yml up -d jwt-generator
    
    # Wait for JWT generation
    sleep 5
    
    # Start Lighthouse beacon node
    docker-compose -f docker-compose-optimized.yml up -d lighthouse-beacon
    
    log "Lighthouse beacon node deployment initiated"
}

# Wait for sync
wait_for_sync() {
    log "Waiting for beacon node to sync..."
    info "Using checkpoint sync from https://mainnet.checkpoint.sigp.io"
    info "This should complete in approximately 5-10 minutes"
    
    # Wait for container to be healthy
    for i in {1..30}; do
        if docker ps --filter "name=lighthouse-beacon" --filter "health=healthy" | grep -q lighthouse-beacon; then
            log "Lighthouse beacon node is healthy"
            break
        fi
        sleep 10
        echo -n "."
    done
    echo
    
    # Check sync status
    for i in {1..120}; do
        if docker exec lighthouse-beacon curl -s http://localhost:5052/eth/v1/node/syncing | grep -q '"is_syncing":false'; then
            log "Beacon node is fully synced!"
            break
        else
            SYNC_STATUS=$(docker exec lighthouse-beacon curl -s http://localhost:5052/eth/v1/node/syncing | jq -r '.data.sync_distance // "unknown"' 2>/dev/null || echo "checking")
            info "Sync distance: $SYNC_STATUS slots"
        fi
        sleep 30
    done
}

# Deploy MEV-Boost (optional)
deploy_mev_boost() {
    log "Checking if MEV-Boost should be deployed..."
    
    read -p "Do you want to deploy MEV-Boost for MEV operations? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Deploying MEV-Boost..."
        cd "$SCRIPT_DIR"
        docker-compose -f docker-compose-optimized.yml --profile mev up -d
        log "MEV-Boost deployed"
    else
        info "Skipping MEV-Boost deployment"
    fi
}

# Configure monitoring
configure_monitoring() {
    log "Configuring monitoring endpoints..."
    
    # Create Prometheus scrape config
    cat > "${SCRIPT_DIR}/config/prometheus-lighthouse.yml" << EOF
scrape_configs:
  - job_name: 'lighthouse-beacon'
    static_configs:
      - targets: ['lighthouse-beacon:5053']
        labels:
          service: 'lighthouse'
          component: 'beacon'
  
  - job_name: 'lighthouse-validator'
    static_configs:
      - targets: ['lighthouse-validator:5064']
        labels:
          service: 'lighthouse'
          component: 'validator'
  
  - job_name: 'erigon'
    static_configs:
      - targets: ['erigon:6060']
        labels:
          service: 'erigon'
          component: 'execution'
EOF
    
    log "Monitoring configuration created"
}

# Health check
perform_health_check() {
    log "Performing health checks..."
    
    # Check beacon node health
    if docker exec lighthouse-beacon curl -s http://localhost:5052/eth/v1/node/health | grep -q "200"; then
        log "✓ Beacon node is healthy"
    else
        warning "✗ Beacon node health check failed"
    fi
    
    # Check peer count
    PEER_COUNT=$(docker exec lighthouse-beacon curl -s http://localhost:5052/eth/v1/node/peer_count | jq -r '.data.connected // 0' 2>/dev/null || echo "0")
    if [ "$PEER_COUNT" -gt 0 ]; then
        log "✓ Connected to $PEER_COUNT peers"
    else
        warning "✗ No peers connected yet"
    fi
    
    # Check execution client connection
    if docker exec lighthouse-beacon curl -s http://localhost:5052/eth/v1/node/version; then
        log "✓ Beacon API is accessible"
    else
        warning "✗ Beacon API is not accessible"
    fi
}

# Show connection information
show_connection_info() {
    log "Deployment Summary"
    echo "===================="
    echo
    info "Lighthouse Beacon Node:"
    info "  HTTP API: http://localhost:5052"
    info "  Metrics: http://localhost:5053/metrics"
    info "  P2P: 9000/tcp and 9000/udp"
    echo
    info "Erigon Execution Client:"
    info "  JSON-RPC: http://localhost:8545"
    info "  WebSocket: ws://localhost:8546"
    info "  Engine API: http://localhost:8551 (JWT protected)"
    echo
    if docker ps | grep -q mev-boost; then
        info "MEV-Boost:"
        info "  API: http://localhost:18550"
    fi
    echo
    info "Useful commands:"
    info "  View logs: docker logs -f lighthouse-beacon"
    info "  Check sync: docker exec lighthouse-beacon curl http://localhost:5052/eth/v1/node/syncing"
    info "  Peer count: docker exec lighthouse-beacon curl http://localhost:5052/eth/v1/node/peer_count"
    echo
}

# Main execution
main() {
    log "Starting Lighthouse Beacon Node deployment"
    echo "========================================"
    
    check_prerequisites
    create_directories
    stop_existing_services
    check_erigon_status
    deploy_lighthouse
    wait_for_sync
    deploy_mev_boost
    configure_monitoring
    perform_health_check
    show_connection_info
    
    log "Lighthouse deployment completed successfully!"
    info "The beacon node is now running and syncing with the Ethereum network"
    info "Monitor the logs with: docker logs -f lighthouse-beacon"
}

# Run main function
main "$@"