#!/bin/bash

# MEV-Boost Production Deployment Script
# Deploys MEV-Boost with enterprise-grade configuration and monitoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEV_BOOST_DIR="/data/blockchain/nodes/mev-boost"
CONFIG_FILE="$MEV_BOOST_DIR/config/mev-boost-mainnet.yml"
LOG_FILE="/data/blockchain/nodes/logs/mev-boost-deploy.log"
PID_FILE="/data/blockchain/nodes/pids/mev-boost.pid"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Create necessary directories
create_directories() {
    log "Creating MEV-Boost directories..."
    mkdir -p /data/blockchain/nodes/{logs,pids}
    mkdir -p "$MEV_BOOST_DIR"/{config,data,scripts}
    chmod 755 /data/blockchain/nodes/{logs,pids}
    chmod 755 "$MEV_BOOST_DIR"/{config,data,scripts}
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check available memory
    TOTAL_MEM=$(free -m | awk 'NR==2{print $2}')
    if [ "$TOTAL_MEM" -lt 4096 ]; then
        warn "System has less than 4GB RAM. MEV-Boost may experience performance issues."
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df /data 2>/dev/null | awk 'NR==2 {print $4}' || df / | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 10485760 ]; then  # 10GB in KB
        warn "Less than 10GB disk space available. Consider freeing up space."
    fi
    
    # Check network connectivity to relays
    log "Testing relay connectivity..."
    if ! curl -s --max-time 5 https://boost-relay.flashbots.net/eth/v1/builder/status >/dev/null; then
        warn "Cannot reach Flashbots relay. Check network connectivity."
    else
        log "✅ Flashbots relay reachable"
    fi
}

# Build MEV-Boost if not present
build_mev_boost() {
    log "Building MEV-Boost..."
    
    cd "$MEV_BOOST_DIR/source"
    
    if [ ! -f "mev-boost" ]; then
        log "Building MEV-Boost binary..."
        make build
        
        if [ ! -f "mev-boost" ]; then
            error "Failed to build MEV-Boost binary"
        fi
        
        log "✅ MEV-Boost binary built successfully"
    else
        log "MEV-Boost binary already exists"
    fi
    
    # Make binary executable
    chmod +x mev-boost
    
    # Copy to system location for easier access
    if [ ! -f "/usr/local/bin/mev-boost" ]; then
        sudo cp mev-boost /usr/local/bin/
        sudo chmod +x /usr/local/bin/mev-boost
        log "✅ MEV-Boost binary installed to /usr/local/bin/"
    fi
}

# Configure systemd service
setup_systemd_service() {
    log "Setting up MEV-Boost systemd service..."
    
    sudo tee /etc/systemd/system/mev-boost.service > /dev/null << EOF
[Unit]
Description=MEV-Boost Relay for Ethereum
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
Restart=always
RestartSec=5
ExecStart=/usr/local/bin/mev-boost \\
    -mainnet \\
    -addr 0.0.0.0:18550 \\
    -relay-check \\
    -relays https://0xac6e77dfe25ecd6110b8e780608cce0dab71fdd5ebea22a16c0205200f2f8e2e3ef4aecb4e0c49ef80ae8b65cde2d9d@boost-relay.flashbots.net,https://0x8b5d2e73e2a3a55c6c87b8b8b6b6d6e6f6a6b6b6c6c6c6c6c6c6c6c6c6c6c6c6@bloxroute.max-profit.blxrbdn.com,https://0xb3ee7afcf27f1f1259ac1787876318c6584ee353097a50ed84f51a1f21a323b3736f271a895c7ce918c038e4265918be@relay.edennetwork.io \\
    -request-timeout-getheader 950ms \\
    -request-timeout-getpayload 4000ms \\
    -request-timeout-regval 3000ms

WorkingDirectory=/data/blockchain/nodes/mev-boost
StandardOutput=append:/data/blockchain/nodes/logs/mev-boost.log
StandardError=append:/data/blockchain/nodes/logs/mev-boost-error.log

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/data/blockchain/nodes

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable mev-boost
    log "✅ MEV-Boost systemd service configured"
}

# Start MEV-Boost service
start_mev_boost() {
    log "Starting MEV-Boost service..."
    
    # Stop if running
    if systemctl is-active --quiet mev-boost; then
        log "Stopping existing MEV-Boost service..."
        sudo systemctl stop mev-boost
        sleep 2
    fi
    
    # Start service
    sudo systemctl start mev-boost
    
    # Wait for startup
    sleep 5
    
    # Check status
    if systemctl is-active --quiet mev-boost; then
        log "✅ MEV-Boost service started successfully"
        
        # Get PID and save it
        MEV_BOOST_PID=$(systemctl show -p MainPID mev-boost | cut -d= -f2)
        echo "$MEV_BOOST_PID" > "$PID_FILE"
        log "MEV-Boost PID: $MEV_BOOST_PID"
    else
        error "Failed to start MEV-Boost service"
    fi
}

# Validate MEV-Boost deployment
validate_deployment() {
    log "Validating MEV-Boost deployment..."
    
    # Check if service is running
    if ! systemctl is-active --quiet mev-boost; then
        error "MEV-Boost service is not running"
    fi
    
    # Check if port is listening
    if ! netstat -tln | grep -q ":18550 "; then
        error "MEV-Boost is not listening on port 18550"
    fi
    
    # Test health endpoint (wait for startup)
    sleep 10
    local retry_count=0
    local max_retries=30
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -s --max-time 5 http://localhost:18550/eth/v1/builder/status >/dev/null 2>&1; then
            log "✅ MEV-Boost health check passed"
            break
        fi
        
        retry_count=$((retry_count + 1))
        info "Health check attempt $retry_count/$max_retries..."
        sleep 2
    done
    
    if [ $retry_count -eq $max_retries ]; then
        warn "MEV-Boost health check failed after $max_retries attempts"
    fi
    
    # Test relay connections
    log "Testing relay connections..."
    if /usr/local/bin/mev-boost -mainnet -relay-check -relays https://boost-relay.flashbots.net 2>&1 | grep -q "successfully"; then
        log "✅ Relay connections validated"
    else
        warn "Some relay connections may have issues"
    fi
}

# Create monitoring script
create_monitoring_script() {
    log "Creating MEV-Boost monitoring script..."
    
    cat > "$MEV_BOOST_DIR/scripts/monitor-mev-boost.sh" << 'EOF'
#!/bin/bash

# MEV-Boost Monitoring Script
# Monitors MEV-Boost health and performance

MEV_BOOST_URL="http://localhost:18550"
LOG_FILE="/data/blockchain/nodes/logs/mev-boost-monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check service status
if ! systemctl is-active --quiet mev-boost; then
    log "ERROR: MEV-Boost service is not running"
    exit 1
fi

# Check health endpoint
if ! curl -s --max-time 5 "$MEV_BOOST_URL/eth/v1/builder/status" >/dev/null; then
    log "ERROR: MEV-Boost health endpoint not responding"
    exit 1
fi

# Get metrics if available
if curl -s --max-time 5 "$MEV_BOOST_URL/metrics" >/dev/null; then
    METRICS=$(curl -s --max-time 5 "$MEV_BOOST_URL/metrics")
    REQUEST_COUNT=$(echo "$METRICS" | grep -o 'mevboost_requests_total[^0-9]*[0-9]*' | grep -o '[0-9]*$' | head -1)
    
    if [ -n "$REQUEST_COUNT" ]; then
        log "MEV-Boost requests total: $REQUEST_COUNT"
    fi
fi

log "MEV-Boost health check passed"
EOF

    chmod +x "$MEV_BOOST_DIR/scripts/monitor-mev-boost.sh"
    
    # Create cron job for monitoring
    echo "*/5 * * * * $MEV_BOOST_DIR/scripts/monitor-mev-boost.sh" | sudo crontab -
    log "✅ MEV-Boost monitoring configured"
}

# Performance optimization
optimize_performance() {
    log "Applying performance optimizations..."
    
    # Increase file descriptor limits
    echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
    echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
    
    # Network optimizations
    sudo sysctl -w net.core.rmem_max=134217728
    sudo sysctl -w net.core.wmem_max=134217728
    sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
    sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"
    
    log "✅ Performance optimizations applied"
}

# Main deployment function
main() {
    log "Starting MEV-Boost production deployment..."
    
    create_directories
    check_requirements
    build_mev_boost
    setup_systemd_service
    optimize_performance
    start_mev_boost
    validate_deployment
    create_monitoring_script
    
    log "🎉 MEV-Boost deployment completed successfully!"
    log ""
    log "Service Status: $(systemctl is-active mev-boost)"
    log "Service URL: http://localhost:18550"
    log "Log File: /data/blockchain/nodes/logs/mev-boost.log"
    log "Monitor Script: $MEV_BOOST_DIR/scripts/monitor-mev-boost.sh"
    log ""
    log "Next steps:"
    log "1. Configure your beacon node to use MEV-Boost"
    log "2. Set beacon node --http-address flag to http://localhost:18550"
    log "3. Monitor logs: tail -f /data/blockchain/nodes/logs/mev-boost.log"
    log "4. Check status: systemctl status mev-boost"
}

# Trap errors
trap 'error "Deployment failed at line $LINENO"' ERR

# Run main function
main "$@"