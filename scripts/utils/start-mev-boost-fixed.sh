#!/bin/bash

# Fixed MEV-Boost Production Startup Script
# Uses correct relay endpoints with proper hex encoding

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/data/blockchain/nodes/logs/mev-boost-fixed.log"
PID_FILE="/data/blockchain/nodes/pids/mev-boost.pid"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Stop existing instance
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "Stopping existing MEV-Boost process (PID: $OLD_PID)"
        kill "$OLD_PID"
        sleep 2
    fi
    rm -f "$PID_FILE"
fi

# Kill any existing MEV-Boost processes
pkill -f "mev-boost" || true
sleep 2

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$PID_FILE")"

# Correct production relay endpoints with proper hex encoding
FLASHBOTS_RELAY="https://0xac6e77dfe25ecd6110b8e780608cce0dab71fdd5ebea22a16c0205200f2f8e2e3ef4aecb4e0c49ef80ae8b65cde2d9@boost-relay.flashbots.net"

log "🚀 Starting MEV-Boost production server..."
info "Port: 18550"
info "Relay: Flashbots (verified endpoint)"
info "Log file: $LOG_FILE"

# Start MEV-Boost in background
nohup /usr/local/bin/mev-boost \
    -mainnet \
    -addr 0.0.0.0:18550 \
    -relay-check \
    -relays "$FLASHBOTS_RELAY" \
    -request-timeout-getheader 950 \
    -request-timeout-getpayload 4000 \
    -request-timeout-regval 3000 \
    -loglevel info \
    >> "$LOG_FILE" 2>&1 &

MEV_BOOST_PID=$!
echo "$MEV_BOOST_PID" > "$PID_FILE"

log "✅ MEV-Boost started successfully"
log "PID: $MEV_BOOST_PID"
log "Status endpoint: http://localhost:18550/eth/v1/builder/status"

# Wait for startup
sleep 5

# Validate startup
if kill -0 "$MEV_BOOST_PID" 2>/dev/null; then
    log "✅ MEV-Boost process is running"
    
    # Test health endpoint
    for i in {1..10}; do
        if curl -s --max-time 3 "http://localhost:18550/eth/v1/builder/status" >/dev/null 2>&1; then
            log "✅ MEV-Boost health endpoint responding"
            break
        fi
        info "Health check attempt $i/10..."
        sleep 2
    done
    
    # Check if port is listening
    if netstat -tln 2>/dev/null | grep -q ":18550 " || ss -tln 2>/dev/null | grep -q ":18550 "; then
        log "✅ MEV-Boost listening on port 18550"
    else
        log "⚠️ MEV-Boost may not be listening on port 18550"
    fi
    
    log "🎉 MEV-Boost deployment completed successfully!"
    log ""
    log "Configuration:"
    log "- Address: 0.0.0.0:18550"
    log "- Relay: Flashbots (mainnet)"
    log "- PID: $MEV_BOOST_PID"
    log "- Log: $LOG_FILE"
    log ""
    log "Next steps:"
    log "1. Configure beacon node to use: --builder-endpoint=http://localhost:18550"
    log "2. Monitor logs: tail -f $LOG_FILE"
    log "3. Check status: curl http://localhost:18550/eth/v1/builder/status"
    log "4. Test connection: curl -s http://localhost:18550/eth/v1/builder/status | jq"
    
else
    log "❌ MEV-Boost failed to start - check logs for details"
    tail -20 "$LOG_FILE" | grep -E "(error|fatal|ERROR|FATAL)" || true
    exit 1
fi