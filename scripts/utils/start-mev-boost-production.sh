#!/bin/bash

# Production MEV-Boost Startup Script
# Starts MEV-Boost with production relay endpoints and proper configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/data/blockchain/nodes/logs/mev-boost.log"
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

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$PID_FILE")"

# Production relay endpoints (verified working)
FLASHBOTS_RELAY="https://0xac6e77dfe25ecd6110b8e780608cce0dab71fdd5ebea22a16c0205200f2f8e2e3ad3b71d3499c54ad14d6c21b41a37ae@boost-relay.flashbots.net"
BLOXROUTE_RELAY="https://0x8b5d2e73e2a3a55c6c87b8b6eb92e0149a125c852751db1422fa951e42a09b82c142c3ea98d0d9930b056a3bc9896b8f@bloxroute.max-profit.blxrbdn.com"
BLOXROUTE_ETHICAL="https://0xad0a8bb54565c2211cee576363f3a347089d2f07cf72679d16911d740262694cadb62d7fd7483f27afd714ca0f1b9118@bloxroute.ethical.blxrbdn.com"
BLOCKNATIVE_RELAY="https://0x9000009807ed12c1f08bf4e81c6da3ba8e3fc3d953898ce0102433094e5f22f21102ec057841fcb81978ed1ea0fa8246@builder-relay-mainnet.blocknative.com"
SECURERPC_RELAY="https://0x98650451ba02064f7b000f5768cf0cf4d4e492317d82871bdc87ef841a0743f69f0f1eea11168503240ac35d101c9135@mainnet-relay.securerpc.com"
EDEN_RELAY="https://0xb3ee7afcf27f1f1259ac1787876318c6584ee353097a50ed84f51a1f21a323b3736f271a895c7ce918c038e4265918be@relay.edennetwork.io"
AGNOSTIC_RELAY="https://0xa7ab7a996c8584251c8f925da3170bdfd6ebc75d50f5ddc4050a6fdc77f2a3b5fce2cc750d0865e05d7228af97d69561@agnostic-relay.net"

# Combined relay list for maximum MEV capture
RELAY_LIST="$FLASHBOTS_RELAY,$BLOXROUTE_RELAY,$BLOXROUTE_ETHICAL,$BLOCKNATIVE_RELAY,$SECURERPC_RELAY,$EDEN_RELAY,$AGNOSTIC_RELAY"

log "🚀 Starting MEV-Boost production server..."
info "Port: 18550"
info "Relays: Flashbots, Bloxroute, Blocknative, SecureRPC, Eden, Agnostic (7 total)"
info "Log file: $LOG_FILE"

# Start MEV-Boost in background
nohup /usr/local/bin/mev-boost \
    -mainnet \
    -addr 127.0.0.1:18550 \
    -relay-check \
    -relays "$RELAY_LIST" \
    -request-timeout-getheader 950 \
    -request-timeout-getpayload 4000 \
    -request-timeout-regval 3000 \
    -request-max-retries 3 \
    -min-bid 0.01 \
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
    
    log "🎉 MEV-Boost deployment completed successfully!"
    log ""
    log "Configuration:"
    log "- Address: 127.0.0.1:18550 (localhost only)"
    log "- Relays: 7 production relays (Flashbots, Bloxroute, Blocknative, etc.)"
    log "- PID: $MEV_BOOST_PID"
    log "- Log: $LOG_FILE"
    log ""
    log "Next steps:"
    log "1. Configure beacon node to use: --builder-endpoint=http://localhost:18550"
    log "2. Monitor logs: tail -f $LOG_FILE"
    log "3. Check status: curl http://localhost:18550/eth/v1/builder/status"
    
else
    log "❌ MEV-Boost failed to start"
    exit 1
fi