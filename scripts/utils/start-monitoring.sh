#!/bin/bash
# Blockchain Node Monitoring System Startup Script
# Initializes and starts the complete monitoring infrastructure

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MONITORING_DIR="/data/blockchain/nodes/monitoring"
LOG_DIR="/data/blockchain/nodes/logs"
PID_DIR="$MONITORING_DIR/pids"

echo -e "${BLUE}🚀 Blockchain Node Monitoring System Startup${NC}"
echo -e "Starting comprehensive monitoring infrastructure..."
echo ""

# Create necessary directories
mkdir -p "$LOG_DIR" "$PID_DIR"

# Function to check if process is running
is_running() {
    local pidfile=$1
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$pidfile"
            return 1
        fi
    fi
    return 1
}

# Function to start component
start_component() {
    local name=$1
    local script=$2
    local args=$3
    local pidfile="$PID_DIR/${name}.pid"
    
    if is_running "$pidfile"; then
        echo -e "${YELLOW}⚠${NC}  $name is already running"
        return 0
    fi
    
    echo -e "${BLUE}▶${NC}  Starting $name..."
    
    cd "$MONITORING_DIR"
    nohup python3 "$script" $args > "$LOG_DIR/${name}.log" 2>&1 &
    local pid=$!
    echo $pid > "$pidfile"
    
    # Wait a moment and check if it started successfully
    sleep 2
    if is_running "$pidfile"; then
        echo -e "${GREEN}✓${NC}  $name started successfully (PID: $pid)"
        return 0
    else
        echo -e "${RED}✗${NC}  Failed to start $name"
        return 1
    fi
}

# Function to stop component
stop_component() {
    local name=$1
    local pidfile="$PID_DIR/${name}.pid"
    
    if is_running "$pidfile"; then
        local pid=$(cat "$pidfile")
        echo -e "${YELLOW}⏹${NC}  Stopping $name (PID: $pid)..."
        
        kill "$pid"
        
        # Wait for graceful shutdown
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 30 ]; do
            sleep 1
            ((count++))
        done
        
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}⚠${NC}  Force killing $name..."
            kill -9 "$pid" 2>/dev/null || true
        fi
        
        rm -f "$pidfile"
        echo -e "${GREEN}✓${NC}  $name stopped"
    else
        echo -e "${YELLOW}⚠${NC}  $name is not running"
    fi
}

# Function to show status
show_status() {
    echo -e "${BLUE}📊 Monitoring System Status${NC}"
    echo ""
    
    local components=(
        "health-monitor:Health Monitor"
        "alert-system:Alert System" 
        "performance-dashboard:Performance Dashboard"
    )
    
    for comp in "${components[@]}"; do
        local name=$(echo "$comp" | cut -d: -f1)
        local display=$(echo "$comp" | cut -d: -f2)
        local pidfile="$PID_DIR/${name}.pid"
        
        if is_running "$pidfile"; then
            local pid=$(cat "$pidfile")
            echo -e "${GREEN}✓${NC}  $display (PID: $pid)"
        else
            echo -e "${RED}✗${NC}  $display (not running)"
        fi
    done
    
    echo ""
    echo -e "${BLUE}🔍 Quick Health Check${NC}"
    
    # Check if nodes are accessible
    local healthy_nodes=0
    local total_nodes=0
    
    declare -A test_ports=(
        ["ethereum-light"]=8545
        ["arbitrum-node"]=8560
        ["base-mainnet"]=8547
        ["optimism-node"]=8550
        ["solana-dev"]=8899
    )
    
    for node in "${!test_ports[@]}"; do
        local port=${test_ports[$node]}
        ((total_nodes++))
        
        if docker ps --format "{{.Names}}" | grep -q "^${node}$"; then
            if curl -s --max-time 2 -X POST -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                "http://localhost:${port}" >/dev/null 2>&1 ||
               curl -s --max-time 2 -X POST -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"getSlot","params":[],"id":1}' \
                "http://localhost:${port}" >/dev/null 2>&1; then
                echo -e "${GREEN}✓${NC}  $node is healthy"
                ((healthy_nodes++))
            else
                echo -e "${YELLOW}⚠${NC}  $node is running but RPC not responding"
            fi
        else
            echo -e "${RED}✗${NC}  $node is not running"
        fi
    done
    
    echo ""
    echo -e "Node Health: ${healthy_nodes}/${total_nodes} nodes healthy"
}

# Function to run initial setup
setup_monitoring() {
    echo -e "${BLUE}🔧 Setting up monitoring system...${NC}"
    
    # Check Python dependencies
    echo -e "${BLUE}▶${NC}  Checking Python dependencies..."
    python3 -c "
import sys
required_packages = ['asyncio', 'aiohttp', 'psutil', 'docker', 'yaml', 'numpy', 'flask']
missing = []
for package in required_packages:
    try:
        __import__(package)
    except ImportError:
        missing.append(package)
        
if missing:
    print(f'Missing packages: {missing}')
    print('Install with: pip install ' + ' '.join(missing))
    sys.exit(1)
else:
    print('All required packages are available')
" || {
        echo -e "${RED}✗${NC}  Missing Python dependencies"
        echo "Please install required packages first"
        exit 1
    }
    
    # Initialize database
    echo -e "${BLUE}▶${NC}  Initializing monitoring database..."
    cd "$MONITORING_DIR"
    python3 comprehensive-health-monitor.py --status >/dev/null 2>&1 || {
        echo -e "${RED}✗${NC}  Failed to initialize monitoring database"
        exit 1
    }
    
    # Calculate initial baselines
    echo -e "${BLUE}▶${NC}  Calculating performance baselines..."
    python3 performance-baseline.py --calculate >/dev/null 2>&1 || {
        echo -e "${YELLOW}⚠${NC}  Could not calculate baselines (insufficient data)"
    }
    
    echo -e "${GREEN}✓${NC}  Monitoring system setup completed"
}

# Function to run tests
run_tests() {
    echo -e "${BLUE}🧪 Running monitoring system tests...${NC}"
    
    cd "$MONITORING_DIR"
    if python3 test-monitoring-system.py --basic; then
        echo -e "${GREEN}✓${NC}  Basic tests passed"
    else
        echo -e "${RED}✗${NC}  Some tests failed - check logs for details"
    fi
}

# Main execution
main() {
    local action="${1:-start}"
    
    case "$action" in
        "start")
            setup_monitoring
            
            echo ""
            echo -e "${BLUE}🚀 Starting monitoring components...${NC}"
            
            # Start health monitor
            start_component "health-monitor" "comprehensive-health-monitor.py" "--daemon"
            
            # Start performance dashboard  
            start_component "performance-dashboard" "performance-dashboard.py" "--host 0.0.0.0 --port 3001"
            
            echo ""
            echo -e "${GREEN}✅ Monitoring system started successfully!${NC}"
            echo ""
            echo -e "${BLUE}📊 Access Points:${NC}"
            echo -e "  • Performance Dashboard: http://localhost:3001"
            echo -e "  • Health Status: python3 comprehensive-health-monitor.py --status"
            echo -e "  • Logs: tail -f $LOG_DIR/health-monitor.log"
            echo ""
            echo -e "${BLUE}💡 Next Steps:${NC}"
            echo -e "  • View status: $0 status"
            echo -e "  • Run tests: $0 test"
            echo -e "  • Stop system: $0 stop"
            ;;
            
        "stop")
            echo -e "${BLUE}⏹ Stopping monitoring components...${NC}"
            
            stop_component "health-monitor"
            stop_component "performance-dashboard"
            
            echo ""
            echo -e "${GREEN}✅ Monitoring system stopped${NC}"
            ;;
            
        "restart")
            echo -e "${BLUE}🔄 Restarting monitoring system...${NC}"
            main "stop"
            sleep 3
            main "start"
            ;;
            
        "status")
            show_status
            ;;
            
        "test")
            run_tests
            ;;
            
        "setup")
            setup_monitoring
            ;;
            
        "logs")
            local component="${2:-health-monitor}"
            local logfile="$LOG_DIR/${component}.log"
            
            if [ -f "$logfile" ]; then
                echo -e "${BLUE}📋 Showing logs for $component${NC}"
                tail -f "$logfile"
            else
                echo -e "${RED}✗${NC}  Log file not found: $logfile"
                echo -e "Available logs:"
                ls -la "$LOG_DIR"/*.log 2>/dev/null || echo "No log files found"
            fi
            ;;
            
        "dashboard")
            echo -e "${BLUE}📊 Opening Performance Dashboard${NC}"
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "http://localhost:3001"
            elif command -v open >/dev/null 2>&1; then
                open "http://localhost:3001"
            else
                echo "Dashboard URL: http://localhost:3001"
            fi
            ;;
            
        "help"|"-h"|"--help")
            echo "Blockchain Node Monitoring System"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  start     - Start monitoring system (default)"
            echo "  stop      - Stop monitoring system"
            echo "  restart   - Restart monitoring system"
            echo "  status    - Show system status"
            echo "  test      - Run system tests"
            echo "  setup     - Initialize monitoring system"
            echo "  logs [component] - Show logs (components: health-monitor, performance-dashboard)"
            echo "  dashboard - Open performance dashboard"
            echo "  help      - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 start          # Start monitoring"
            echo "  $0 status         # Check status"
            echo "  $0 logs health-monitor    # View health monitor logs"
            ;;
            
        *)
            echo -e "${RED}✗${NC}  Unknown command: $action"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}⚠${NC}  Interrupted by user"; exit 130' INT

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi