#!/bin/bash
# Professional Sepolia Testnet Deployment Script
# Optimized for MEV Testing and Development

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEPOLIA_DIR="/data/blockchain/nodes/sepolia"
CONFIG_FILE="$SEPOLIA_DIR/config/erigon-sepolia.toml"
LOG_FILE="$SEPOLIA_DIR/logs/erigon-sepolia.log"
JWT_SECRET="$SEPOLIA_DIR/data/jwt.hex"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"  < /dev/null |  tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

# Resource validation
check_resources() {
    log "Checking system resources for Sepolia deployment..."
    
    # Memory check (minimum 4GB available)
    available_mem=$(free -g | awk 'NR==2{print $7}')
    if [ "$available_mem" -lt 4 ]; then
        warn "Low available memory: ${available_mem}GB (recommended: 4GB+)"
    fi
    
    # Disk space check (minimum 50GB available)
    available_disk=$(df -BG "$SEPOLIA_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$available_disk" -lt 50 ]; then
        warn "Low disk space: ${available_disk}GB (recommended: 50GB+)"
    fi
    
    log "Resource check completed"
}

# JWT secret generation
generate_jwt_secret() {
    if [ \! -f "$JWT_SECRET" ]; then
        log "Generating JWT secret for Engine API..."
        openssl rand -hex 32 > "$JWT_SECRET"
        chmod 600 "$JWT_SECRET"
        log "JWT secret created at $JWT_SECRET"
    else
        log "JWT secret already exists"
    fi
}

# Network connectivity test
test_connectivity() {
    log "Testing network connectivity..."
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        log "Network connectivity: OK"
    else
        error "Network connectivity failed"
    fi
}

# Port availability check
check_ports() {
    log "Checking port availability..."
    local ports=(8565 8566 8571 6070 30304)
    
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            warn "Port $port is already in use"
        else
            log "Port $port: available"
        fi
    done
}

# Main deployment function
deploy_sepolia() {
    log "Starting Sepolia testnet deployment with Erigon..."
    
    # Pre-deployment checks
    check_resources
    test_connectivity
    check_ports
    generate_jwt_secret
    
    # Create necessary directories
    mkdir -p "$SEPOLIA_DIR"/{data/erigon,logs}
    
    # Find Erigon binary
    ERIGON_BIN=""
    if [ -x "/data/blockchain/nodes/ethereum/erigon/bin/erigon" ]; then
        ERIGON_BIN="/data/blockchain/nodes/ethereum/erigon/bin/erigon"
    elif command -v erigon >/dev/null 2>&1; then
        ERIGON_BIN="erigon"
    else
        error "Erigon binary not found. Please install Erigon first."
    fi
    
    log "Using Erigon binary: $ERIGON_BIN"
    
    # Resource limits for Sepolia (lighter than mainnet)
    export GOMEMLIMIT=8GiB
    export GOGC=50
    
    # Start Erigon with optimized configuration
    log "Starting Erigon for Sepolia testnet..."
    
    exec "$ERIGON_BIN" \
        --config="$CONFIG_FILE" \
        --chain=sepolia \
        --datadir="$SEPOLIA_DIR/data/erigon" \
        --authrpc.jwtsecret="$JWT_SECRET" \
        --log.dir.path="$SEPOLIA_DIR/logs" \
        --maxpeers=50 \
        --torrent.download.rate=16mb \
        --torrent.upload.rate=4mb \
        --http \
        --http.addr=0.0.0.0 \
        --http.port=8575 \
        --http.api=eth,erigon,engine,web3,net,debug,trace,txpool,admin \
        --http.vhosts=* \
        --http.corsdomain=* \
        --ws \
        --ws.addr=0.0.0.0 \
        --ws.port=8576 \
        --ws.api=eth,web3,net,txpool \
        --ws.origins=* \
        --authrpc.addr=localhost \
        --authrpc.port=8581 \
        --authrpc.vhosts=localhost \
        --metrics \
        --metrics.addr=0.0.0.0 \
        --metrics.port=6070 \
        --prune=hrtc \
        --txpool.accountslots=16 \
        --txpool.globalslots=10000 \
        --nat=any \
        --log.console.verbosity=3
}

# Main execution
case "${1:-start}" in
    "start")
        deploy_sepolia
        ;;
    "check")
        check_resources
        test_connectivity
        check_ports
        log "Pre-deployment checks completed"
        ;;
    *)
        echo "Usage: $0 {start|check}"
        echo "  start - Deploy and start Sepolia testnet node"
        echo "  check - Run pre-deployment checks only"
        exit 1
        ;;
esac
