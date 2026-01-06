#!/bin/bash
# Advanced MEV Expert Dashboard Startup Script

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/expert-dashboard-venv"

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

expert() {
    echo -e "${PURPLE}[MEV EXPERT]${NC} $1"
}

# Install enhanced dependencies
install_expert_dependencies() {
    log "Setting up Advanced MEV Expert environment..."
    
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        success "Expert virtual environment created"
    fi
    
    source "$VENV_DIR/bin/activate"
    
    log "Installing MEV-specific packages..."
    pip install --quiet --upgrade pip
    pip install --quiet flask flask-cors psutil requests docker numpy pandas
    pip install --quiet web3 ccxt python-binance websocket-client
    
    success "Expert dependencies installed"
}

# Check if expert dashboard is running
check_expert_running() {
    if pgrep -f "advanced-dashboard-server.py" >/dev/null; then
        warn "Expert dashboard server is already running"
        echo "Use 'pkill -f advanced-dashboard-server.py' to stop it first"
        return 1
    fi
    return 0
}

# Start the expert dashboard
start_expert_dashboard() {
    log "Starting Advanced MEV Expert Dashboard..."
    
    source "$VENV_DIR/bin/activate"
    
    # Make sure the server script is executable
    chmod +x "$SCRIPT_DIR/advanced-dashboard-server.py"
    
    # Start the expert server
    nohup python3 "$SCRIPT_DIR/advanced-dashboard-server.py" > "$SCRIPT_DIR/expert-dashboard.log" 2>&1 &
    
    # Get the PID
    expert_pid=$!
    echo $expert_pid > "$SCRIPT_DIR/expert-dashboard.pid"
    
    # Wait and check if it started successfully
    sleep 3
    
    if kill -0 $expert_pid 2>/dev/null; then
        success "Expert dashboard server started (PID: $expert_pid)"
        echo ""
        echo -e "${PURPLE}🚀 Advanced MEV Expert Dashboard is now LIVE!${NC}"
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                    MEV EXPERT ACCESS POINTS                     ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║ 📊 Expert Dashboard:     http://localhost:5001                  ║${NC}"
        echo -e "${CYAN}║ ⚡ MEV Opportunities:     http://localhost:5001/api/enhanced/opportunities ║${NC}"
        echo -e "${CYAN}║ 💰 Profit Analytics:     http://localhost:5001/api/enhanced/profits       ║${NC}"
        echo -e "${CYAN}║ ⛽ Real-Time Gas:         http://localhost:5001/api/enhanced/gas-prices    ║${NC}"
        echo -e "${CYAN}║ 🔗 Advanced Nodes:       http://localhost:5001/api/enhanced/node-status   ║${NC}"
        echo -e "${CYAN}║ 📈 System Metrics:       http://localhost:5001/api/enhanced/system-metrics║${NC}"
        echo -e "${CYAN}║ 🔌 Health Check:         http://localhost:5001/api/enhanced/health        ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}🎯 MEV EXPERT FEATURES:${NC}"
        echo "  ⚡ Real-time arbitrage opportunity detection"
        echo "  💎 Cross-chain MEV analytics"
        echo "  📊 Advanced profit tracking with charts"
        echo "  ⛽ Live gas price monitoring across all chains"
        echo "  🤖 Auto-trading controls and circuit breakers"
        echo "  🔍 Liquidation opportunity scanner"
        echo "  📈 Performance analytics per chain"
        echo "  🛡️ Risk management dashboard"
        echo ""
        echo -e "${YELLOW}🛠️ EXPERT MANAGEMENT:${NC}"
        echo "  View logs:             tail -f $SCRIPT_DIR/expert-dashboard.log"
        echo "  Stop expert dashboard: pkill -f advanced-dashboard-server.py"
        echo "  Restart dashboard:     $0 restart"
        echo "  Monitor opportunities: curl http://localhost:5001/api/enhanced/opportunities"
        echo ""
        return 0
    else
        error "Expert dashboard server failed to start"
        return 1
    fi
}

# Stop the expert dashboard
stop_expert_dashboard() {
    log "Stopping expert dashboard server..."
    
    if [ -f "$SCRIPT_DIR/expert-dashboard.pid" ]; then
        pid=$(cat "$SCRIPT_DIR/expert-dashboard.pid")
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            sleep 2
            if kill -0 $pid 2>/dev/null; then
                kill -9 $pid
            fi
            rm -f "$SCRIPT_DIR/expert-dashboard.pid"
            success "Expert dashboard server stopped"
        else
            warn "Expert dashboard server was not running (stale PID file)"
            rm -f "$SCRIPT_DIR/expert-dashboard.pid"
        fi
    else
        pkill -f advanced-dashboard-server.py 2>/dev/null || true
        success "Expert dashboard server stopped"
    fi
}

# Show expert status
show_expert_status() {
    echo -e "${PURPLE}=== MEV EXPERT DASHBOARD STATUS ===${NC}"
    echo ""
    
    if pgrep -f "advanced-dashboard-server.py" >/dev/null; then
        pid=$(pgrep -f "advanced-dashboard-server.py")
        success "Expert dashboard is running (PID: $pid)"
        echo "  Expert Dashboard: http://localhost:5001"
        
        # Test if responding
        if curl -s --max-time 3 http://localhost:5001/api/enhanced/health >/dev/null 2>&1; then
            expert "Dashboard is responding - MEV systems operational"
            
            # Get quick stats
            opportunities=$(curl -s --max-time 2 http://localhost:5001/api/enhanced/opportunities 2>/dev/null | jq length 2>/dev/null || echo "N/A")
            echo "  🎯 Active opportunities: $opportunities"
            
            active_chains=$(curl -s --max-time 2 http://localhost:5001/api/enhanced/node-status 2>/dev/null | jq 'to_entries | map(select(.value.status == "online")) | length' 2>/dev/null || echo "N/A")
            echo "  ⛓️  Active chains: $active_chains"
            
        else
            warn "Expert dashboard server is running but not responding"
        fi
    else
        warn "Expert dashboard server is not running"
        echo "  Use '$0 start' to launch the MEV expert dashboard"
    fi
    echo ""
}

# Main execution
main() {
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}                        MEV EXPERT DASHBOARD MANAGER                           ${NC}"
    echo -e "${PURPLE}                     Advanced Multi-Chain Arbitrage Center                    ${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    case "${1:-start}" in
        "start")
            if ! command -v python3 >/dev/null 2>&1; then
                error "Python 3 not found. Please install Python 3.8+ to run the expert dashboard."
                exit 1
            fi
            
            if ! check_expert_running; then
                exit 1
            fi
            
            install_expert_dependencies
            start_expert_dashboard
            ;;
        "stop")
            stop_expert_dashboard
            ;;
        "restart")
            stop_expert_dashboard
            sleep 2
            if command -v python3 >/dev/null 2>&1 && check_expert_running; then
                install_expert_dependencies
                start_expert_dashboard
            fi
            ;;
        "status")
            show_expert_status
            ;;
        "logs")
            if [ -f "$SCRIPT_DIR/expert-dashboard.log" ]; then
                tail -f "$SCRIPT_DIR/expert-dashboard.log"
            else
                warn "No expert log file found. Dashboard may not be running."
            fi
            ;;
        "opportunities")
            if pgrep -f "advanced-dashboard-server.py" >/dev/null; then
                echo -e "${PURPLE}🎯 Current MEV Opportunities:${NC}"
                curl -s http://localhost:5001/api/enhanced/opportunities | jq -r '.[] | "⚡ \(.type): \(.pair // .protocol) - Profit: \(.profit_eth) ETH (\(.confidence) confidence)"' 2>/dev/null || echo "Failed to fetch opportunities"
            else
                warn "Expert dashboard is not running"
            fi
            ;;
        "profit")
            if pgrep -f "advanced-dashboard-server.py" >/dev/null; then
                echo -e "${PURPLE}💰 Current Profit Analytics:${NC}"
                curl -s http://localhost:5001/api/enhanced/profits | jq -r '.totals | "Today: \(.today) ETH | Week: \(.week) ETH | Success Rate: \(.success_rate)%"' 2>/dev/null || echo "Failed to fetch profit data"
            else
                warn "Expert dashboard is not running"
            fi
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status|logs|opportunities|profit}"
            echo ""
            echo "Commands:"
            echo "  start          - Start the MEV expert dashboard"
            echo "  stop           - Stop the expert dashboard"
            echo "  restart        - Restart the expert dashboard"
            echo "  status         - Show expert dashboard status"
            echo "  logs           - Show expert dashboard logs (real-time)"
            echo "  opportunities  - Show current MEV opportunities"
            echo "  profit         - Show current profit analytics"
            exit 1
            ;;
    esac
}

main "$@"