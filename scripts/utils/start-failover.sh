#!/bin/bash
# Blockchain Failover System Startup Script

set -euo pipefail

FAILOVER_DIR="/data/blockchain/nodes/failover"
LOG_FILE="${FAILOVER_DIR}/failover.log"
PID_FILE="${FAILOVER_DIR}/failover.pid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Create directory if it doesn't exist
mkdir -p "$FAILOVER_DIR"

start_failover() {
    log "Starting Blockchain Failover System..."
    
    # Check if already running
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "Failover system is already running (PID: $(cat "$PID_FILE"))"
        return 1
    fi
    
    # Install dependencies if needed
    if ! python3 -c "import yaml, requests" 2>/dev/null; then
        log "Installing Python dependencies..."
        pip3 install pyyaml requests
    fi
    
    # Start the circuit breaker service
    cd "$FAILOVER_DIR"
    nohup python3 circuit-breaker.py > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    
    sleep 2
    
    # Verify it started
    if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        success "Failover system started successfully (PID: $(cat "$PID_FILE"))"
        test_endpoints
    else
        error "Failed to start failover system"
        return 1
    fi
}

stop_failover() {
    log "Stopping Blockchain Failover System..."
    
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            success "Failover system stopped"
        else
            warn "Failover system was not running"
            rm -f "$PID_FILE"
        fi
    else
        warn "No PID file found, failover system may not be running"
    fi
}

status_failover() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        success "Failover system is running (PID: $(cat "$PID_FILE"))"
        
        # Show endpoint status
        log "Checking endpoint status..."
        check_endpoint_health
        
        return 0
    else
        error "Failover system is not running"
        return 1
    fi
}

test_endpoints() {
    log "Testing blockchain endpoints..."
    
    # Test Ethereum
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 | jq -r '.result' >/dev/null 2>&1; then
        success "Ethereum endpoint: OK"
    else
        warn "Ethereum endpoint: FAILED - Will use backup"
    fi
    
    # Test Arbitrum
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8549 >/dev/null 2>&1; then
        success "Arbitrum endpoint: OK"
    else
        warn "Arbitrum endpoint: FAILED - Will use backup"
    fi
    
    # Test Optimism
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8550 >/dev/null 2>&1; then
        success "Optimism endpoint: OK"
    else
        warn "Optimism endpoint: FAILED - Will use backup"
    fi
    
    # Test Base
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8547 >/dev/null 2>&1; then
        success "Base endpoint: OK"
    else
        warn "Base endpoint: FAILED - Will use backup"
    fi
    
    # Test BSC
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8555 >/dev/null 2>&1; then
        success "BSC endpoint: OK"
    else
        warn "BSC endpoint: FAILED - Will use backup"
    fi
    
    # Test Solana
    if curl -s http://localhost:8899/health | grep -q "ok"; then
        success "Solana endpoint: OK"
    else
        warn "Solana endpoint: FAILED - Will use backup"
    fi
}

check_endpoint_health() {
    local total=0
    local healthy=0
    
    # Check each endpoint
    for endpoint in ethereum:8545 arbitrum:8549 optimism:8550 base:8547 bsc:8555; do
        local name=${endpoint%:*}
        local port=${endpoint#*:}
        
        total=$((total + 1))
        
        if curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            http://localhost:$port >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $name (port $port)"
            healthy=$((healthy + 1))
        else
            echo -e "  ${RED}✗${NC} $name (port $port)"
        fi
    done
    
    # Check Solana separately
    total=$((total + 1))
    if curl -s http://localhost:8899/health | grep -q "ok"; then
        echo -e "  ${GREEN}✓${NC} solana (port 8899)"
        healthy=$((healthy + 1))
    else
        echo -e "  ${RED}✗${NC} solana (port 8899)"
    fi
    
    log "Health Summary: $healthy/$total endpoints healthy"
}

test_failover() {
    log "Testing failover functionality..."
    
    # Create test script
    cat > "${FAILOVER_DIR}/test-failover.py" << 'EOF'
#!/usr/bin/env python3
import sys
sys.path.append('/data/blockchain/nodes/failover')
from circuit_breaker import FailoverManager

try:
    failover = FailoverManager()
    
    # Test each blockchain
    blockchains = ['ethereum', 'arbitrum', 'optimism', 'base', 'bsc']
    
    for blockchain in blockchains:
        try:
            result = failover.rpc_call(blockchain, "eth_blockNumber")
            if result and 'result' in result:
                print(f"✓ {blockchain}: Block {int(result['result'], 16)}")
            else:
                print(f"✗ {blockchain}: Failed to get block number")
        except Exception as e:
            print(f"✗ {blockchain}: Error - {e}")
    
    # Test Solana
    try:
        solana_cb = failover.get_endpoint("solana")
        if solana_cb:
            health = solana_cb.call("health", "GET")
            if health:
                print(f"✓ solana: Health check passed")
            else:
                print(f"✗ solana: Health check failed")
    except Exception as e:
        print(f"✗ solana: Error - {e}")
    
    # Print status
    status = failover.get_all_status()
    print("\nCircuit Breaker Status:")
    for name, cb_status in status.items():
        state = cb_status['state']
        color = '✓' if state == 'closed' else '!' if state == 'half_open' else '✗'
        print(f"  {color} {name}: {state}")
        
except Exception as e:
    print(f"Error testing failover: {e}")
    sys.exit(1)
EOF
    
    chmod +x "${FAILOVER_DIR}/test-failover.py"
    python3 "${FAILOVER_DIR}/test-failover.py"
}

create_systemd_service() {
    log "Creating systemd service for failover system..."
    
    sudo tee /etc/systemd/system/blockchain-failover.service > /dev/null << EOF
[Unit]
Description=Blockchain Failover System
After=network.target
Wants=network.target

[Service]
Type=forking
User=root
WorkingDirectory=$FAILOVER_DIR
ExecStart=$FAILOVER_DIR/start-failover.sh start
ExecStop=$FAILOVER_DIR/start-failover.sh stop
ExecReload=$FAILOVER_DIR/start-failover.sh restart
PIDFile=$PID_FILE
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable blockchain-failover.service
    success "Systemd service created and enabled"
}

case "${1:-}" in
    start)
        start_failover
        ;;
    stop)
        stop_failover
        ;;
    restart)
        stop_failover
        sleep 2
        start_failover
        ;;
    status)
        status_failover
        ;;
    test)
        test_failover
        ;;
    install-service)
        create_systemd_service
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|test|install-service}"
        echo ""
        echo "Commands:"
        echo "  start           - Start the failover system"
        echo "  stop            - Stop the failover system"
        echo "  restart         - Restart the failover system"
        echo "  status          - Check system status and endpoint health"
        echo "  test            - Test failover functionality"
        echo "  install-service - Install systemd service"
        exit 1
        ;;
esac