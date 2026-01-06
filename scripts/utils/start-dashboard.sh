#!/bin/bash
# MEV Infrastructure Dashboard Startup Script

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/dashboard-venv"

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

# Check if Python 3 is available
check_python() {
    if command -v python3 >/dev/null 2>&1; then
        log "Python 3 found: $(python3 --version)"
        return 0
    else
        error "Python 3 not found. Please install Python 3.8+ to run the dashboard."
        return 1
    fi
}

# Install Python dependencies
install_dependencies() {
    log "Setting up Python virtual environment..."
    
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        success "Virtual environment created"
    fi
    
    source "$VENV_DIR/bin/activate"
    
    log "Installing required packages..."
    pip install --quiet --upgrade pip
    pip install --quiet flask flask-cors psutil requests docker
    
    success "Dependencies installed"
}

# Check if dashboard server is already running
check_running() {
    if pgrep -f "dashboard-server.py" >/dev/null; then
        warn "Dashboard server is already running"
        echo "Use 'pkill -f dashboard-server.py' to stop it first"
        return 1
    fi
    return 0
}

# Start the dashboard server
start_dashboard() {
    log "Starting MEV Infrastructure Dashboard..."
    
    source "$VENV_DIR/bin/activate"
    
    # Make sure the server script is executable
    chmod +x "$SCRIPT_DIR/dashboard-server.py"
    
    # Start the server in background
    nohup python3 "$SCRIPT_DIR/dashboard-server.py" > "$SCRIPT_DIR/dashboard.log" 2>&1 &
    
    # Get the PID
    dashboard_pid=$!
    echo $dashboard_pid > "$SCRIPT_DIR/dashboard.pid"
    
    # Wait a moment and check if it started successfully
    sleep 3
    
    if kill -0 $dashboard_pid 2>/dev/null; then
        success "Dashboard server started (PID: $dashboard_pid)"
        echo ""
        echo -e "${GREEN}🚀 MEV Infrastructure Dashboard is now running!${NC}"
        echo ""
        echo -e "${YELLOW}Access URLs:${NC}"
        echo "  📊 Main Dashboard:    http://localhost:5000"
        echo "  🔌 Health Check:      http://localhost:5000/api/health"
        echo "  ⚙️  System Metrics:    http://localhost:5000/api/system-metrics"
        echo "  ⛓️  Node Status:       http://localhost:5000/api/node-status"
        echo "  💰 MEV Metrics:       http://localhost:5000/api/mev-metrics"
        echo ""
        echo -e "${YELLOW}Management:${NC}"
        echo "  View logs:           tail -f $SCRIPT_DIR/dashboard.log"
        echo "  Stop dashboard:      pkill -f dashboard-server.py"
        echo "  Restart dashboard:   $0 restart"
        echo ""
        return 0
    else
        error "Dashboard server failed to start"
        return 1
    fi
}

# Stop the dashboard server
stop_dashboard() {
    log "Stopping dashboard server..."
    
    if [ -f "$SCRIPT_DIR/dashboard.pid" ]; then
        pid=$(cat "$SCRIPT_DIR/dashboard.pid")
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            sleep 2
            if kill -0 $pid 2>/dev/null; then
                kill -9 $pid
            fi
            rm -f "$SCRIPT_DIR/dashboard.pid"
            success "Dashboard server stopped"
        else
            warn "Dashboard server was not running (stale PID file)"
            rm -f "$SCRIPT_DIR/dashboard.pid"
        fi
    else
        pkill -f dashboard-server.py 2>/dev/null || true
        success "Dashboard server stopped"
    fi
}

# Show dashboard status
show_status() {
    if pgrep -f "dashboard-server.py" >/dev/null; then
        pid=$(pgrep -f "dashboard-server.py")
        success "Dashboard server is running (PID: $pid)"
        echo "  Dashboard URL: http://localhost:5000"
        
        # Test if the dashboard is responding
        if curl -s --max-time 3 http://localhost:5000/api/health >/dev/null 2>&1; then
            success "Dashboard is responding to requests"
        else
            warn "Dashboard server is running but not responding"
        fi
    else
        warn "Dashboard server is not running"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                      MEV Infrastructure Dashboard Manager                      ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    case "${1:-start}" in
        "start")
            if ! check_python; then
                exit 1
            fi
            
            if ! check_running; then
                exit 1
            fi
            
            install_dependencies
            start_dashboard
            ;;
        "stop")
            stop_dashboard
            ;;
        "restart")
            stop_dashboard
            sleep 2
            if check_python && check_running; then
                install_dependencies
                start_dashboard
            fi
            ;;
        "status")
            show_status
            ;;
        "logs")
            if [ -f "$SCRIPT_DIR/dashboard.log" ]; then
                tail -f "$SCRIPT_DIR/dashboard.log"
            else
                warn "No log file found. Dashboard may not be running."
            fi
            ;;
        "install")
            check_python
            install_dependencies
            success "Dashboard dependencies installed. Use '$0 start' to run."
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status|logs|install}"
            echo ""
            echo "Commands:"
            echo "  start     - Start the dashboard server"
            echo "  stop      - Stop the dashboard server"
            echo "  restart   - Restart the dashboard server"
            echo "  status    - Show dashboard status"
            echo "  logs      - Show dashboard logs (real-time)"
            echo "  install   - Install dependencies only"
            exit 1
            ;;
    esac
}

main "$@"