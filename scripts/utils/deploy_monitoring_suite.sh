#!/bin/bash
"""
Advanced MEV Monitoring Suite Deployment Script
Deploys and manages the complete monitoring and analytics infrastructure

Usage:
  ./deploy_monitoring_suite.sh [start|stop|restart|status|test]
  
Commands:
  start    - Start all monitoring systems
  stop     - Stop all monitoring systems  
  restart  - Restart all monitoring systems
  status   - Show system status
  test     - Run system tests
  logs     - Show system logs
  health   - Check system health
"""

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/data/blockchain/nodes/logs"
PID_DIR="/var/run/mev-monitoring"
VENV_PATH="/opt/mev-monitoring-venv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running as root for system operations
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root - ensure this is intended"
    fi
}

# Create necessary directories
setup_directories() {
    log "Setting up directories..."
    
    mkdir -p "$LOG_DIR"
    mkdir -p "$PID_DIR"
    mkdir -p "${SCRIPT_DIR}/models"
    
    # Set appropriate permissions
    chmod 755 "$LOG_DIR"
    chmod 755 "$PID_DIR"
    chmod 755 "${SCRIPT_DIR}"
    
    log_success "Directories created"
}

# Check and install Python dependencies
check_dependencies() {
    log "Checking Python dependencies..."
    
    # Check if virtual environment exists
    if [[ ! -d "$VENV_PATH" ]]; then
        log "Creating Python virtual environment..."
        python3 -m venv "$VENV_PATH"
    fi
    
    # Activate virtual environment
    source "$VENV_PATH/bin/activate"
    
    # Required packages
    REQUIRED_PACKAGES=(
        "numpy>=1.21.0"
        "pandas>=1.3.0"
        "scikit-learn>=1.0.0"
        "flask>=2.0.0"
        "flask-cors>=3.0.0"
        "flask-socketio>=5.0.0"
        "redis>=4.0.0"
        "aiohttp>=3.8.0"
        "websockets>=10.0"
        "requests>=2.25.0"
        "joblib>=1.1.0"
    )
    
    # Install/upgrade packages
    for package in "${REQUIRED_PACKAGES[@]}"; do
        pip install --upgrade "$package" 2>/dev/null || {
            log_warning "Failed to install $package, continuing..."
        }
    done
    
    log_success "Dependencies checked and installed"
}

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check Python version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python version: $python_version"
    
    # Check available memory
    available_memory=$(free -m | awk 'NR==2{printf "%.1f", $7/1024 }')
    log "Available memory: ${available_memory}GB"
    
    if (( $(echo "$available_memory < 2.0" | bc -l) )); then
        log_warning "Low available memory (${available_memory}GB). Recommend 4GB+ for optimal performance"
    fi
    
    # Check disk space
    available_disk=$(df -h "$LOG_DIR" | awk 'NR==2 {print $4}')
    log "Available disk space: $available_disk"
    
    # Check if Redis is available
    if command -v redis-cli &> /dev/null; then
        if redis-cli ping &> /dev/null; then
            log_success "Redis is running"
        else
            log_warning "Redis is installed but not running"
        fi
    else
        log_warning "Redis not installed - some features may be limited"
    fi
    
    log_success "System requirements check completed"
}

# Start individual monitoring system
start_system() {
    local system_name="$1"
    local script_name="$2"
    local description="$3"
    
    local pid_file="${PID_DIR}/${system_name}.pid"
    local log_file="${LOG_DIR}/${system_name}.log"
    
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        log_warning "$description is already running (PID: $(cat "$pid_file"))"
        return 0
    fi
    
    log "Starting $description..."
    
    # Activate virtual environment and start system
    source "$VENV_PATH/bin/activate"
    
    nohup python3 "${SCRIPT_DIR}/${script_name}" > "$log_file" 2>&1 &
    local pid=$!
    
    # Save PID
    echo $pid > "$pid_file"
    
    # Wait a moment and check if process is still running
    sleep 2
    if kill -0 $pid 2>/dev/null; then
        log_success "$description started successfully (PID: $pid)"
        return 0
    else
        log_error "$description failed to start"
        rm -f "$pid_file"
        return 1
    fi
}

# Stop individual monitoring system
stop_system() {
    local system_name="$1"
    local description="$2"
    
    local pid_file="${PID_DIR}/${system_name}.pid"
    
    if [[ ! -f "$pid_file" ]]; then
        log_warning "$description is not running"
        return 0
    fi
    
    local pid=$(cat "$pid_file")
    
    if kill -0 "$pid" 2>/dev/null; then
        log "Stopping $description (PID: $pid)..."
        
        # Send SIGTERM first
        kill "$pid" 2>/dev/null || true
        
        # Wait for graceful shutdown
        for i in {1..10}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            log_warning "Force killing $description..."
            kill -9 "$pid" 2>/dev/null || true
        fi
        
        rm -f "$pid_file"
        log_success "$description stopped"
    else
        log_warning "$description PID file exists but process is not running"
        rm -f "$pid_file"
    fi
}

# Get system status
get_system_status() {
    local system_name="$1"
    local description="$2"
    
    local pid_file="${PID_DIR}/${system_name}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}Running${NC} (PID: $pid)"
        else
            echo -e "${RED}Dead${NC} (stale PID file)"
        fi
    else
        echo -e "${RED}Stopped${NC}"
    fi
}

# Start all monitoring systems
start_all() {
    log "🚀 Starting Advanced MEV Monitoring Suite..."
    
    check_permissions
    setup_directories
    check_system_requirements
    check_dependencies
    
    # Define systems to start
    declare -A SYSTEMS=(
        ["performance_dashboard"]="real_time_performance_dashboard.py|Real-Time Performance Dashboard"
        ["predictive_analytics"]="predictive_analytics_engine.py|Predictive Analytics Engine"
        ["alerting_system"]="advanced_alerting_system.py|Advanced Alerting System"
        ["revenue_optimization"]="revenue_optimization_analytics.py|Revenue Optimization Analytics"
        ["competitive_intelligence"]="competitive_intelligence_system.py|Competitive Intelligence System"
        ["master_orchestrator"]="master_monitoring_orchestrator.py|Master Monitoring Orchestrator"
    )
    
    local failed_systems=0
    
    # Start systems in order (orchestrator last)
    for system in performance_dashboard predictive_analytics alerting_system revenue_optimization competitive_intelligence master_orchestrator; do
        IFS='|' read -r script_name description <<< "${SYSTEMS[$system]}"
        
        if ! start_system "$system" "$script_name" "$description"; then
            ((failed_systems++))
        fi
        
        # Small delay between starts
        sleep 1
    done
    
    echo ""
    if [[ $failed_systems -eq 0 ]]; then
        log_success "🎉 All monitoring systems started successfully!"
        log "📊 Dashboard available at: http://localhost:8091"
        log "🔔 Alerting system active"
        log "🤖 AI predictions running"
        log "💰 Revenue optimization active"
        log "🕵️ Competitive intelligence monitoring"
    else
        log_error "⚠️ $failed_systems system(s) failed to start. Check logs for details."
    fi
    
    echo ""
    log "Use './deploy_monitoring_suite.sh status' to check system status"
    log "Use './deploy_monitoring_suite.sh logs' to view system logs"
}

# Stop all monitoring systems
stop_all() {
    log "🛑 Stopping Advanced MEV Monitoring Suite..."
    
    # Define systems to stop (orchestrator first)
    declare -A SYSTEMS=(
        ["master_orchestrator"]="Master Monitoring Orchestrator"
        ["competitive_intelligence"]="Competitive Intelligence System"
        ["revenue_optimization"]="Revenue Optimization Analytics"
        ["alerting_system"]="Advanced Alerting System"
        ["predictive_analytics"]="Predictive Analytics Engine"
        ["performance_dashboard"]="Real-Time Performance Dashboard"
    )
    
    # Stop systems in reverse order
    for system in master_orchestrator competitive_intelligence revenue_optimization alerting_system predictive_analytics performance_dashboard; do
        description="${SYSTEMS[$system]}"
        stop_system "$system" "$description"
        sleep 1
    done
    
    log_success "🛑 All monitoring systems stopped"
}

# Show status of all systems
show_status() {
    echo ""
    echo -e "${CYAN}📊 Advanced MEV Monitoring Suite Status${NC}"
    echo "============================================="
    
    declare -A SYSTEMS=(
        ["master_orchestrator"]="Master Monitoring Orchestrator"
        ["performance_dashboard"]="Real-Time Performance Dashboard"
        ["predictive_analytics"]="Predictive Analytics Engine"
        ["alerting_system"]="Advanced Alerting System"
        ["revenue_optimization"]="Revenue Optimization Analytics"
        ["competitive_intelligence"]="Competitive Intelligence System"
    )
    
    local running_count=0
    local total_count=${#SYSTEMS[@]}
    
    for system in master_orchestrator performance_dashboard predictive_analytics alerting_system revenue_optimization competitive_intelligence; do
        description="${SYSTEMS[$system]}"
        status=$(get_system_status "$system" "$description")
        
        printf "%-35s: %s\n" "$description" "$status"
        
        if [[ "$status" == *"Running"* ]]; then
            ((running_count++))
        fi
    done
    
    echo "============================================="
    echo -e "Status: ${running_count}/${total_count} systems running"
    
    # Show system resources
    echo ""
    echo -e "${CYAN}📈 System Resources${NC}"
    echo "==================="
    echo "Memory Usage: $(free -h | awk 'NR==2{printf "%s/%s (%.1f%%)", $3,$2,$3*100/$2 }')"
    echo "Disk Usage: $(df -h "$LOG_DIR" | awk 'NR==2 {printf "%s/%s (%s)", $3,$2,$5}')"
    echo "Load Average: $(uptime | awk -F'load average:' '{ print $2 }')"
    
    # Show recent logs summary
    echo ""
    echo -e "${CYAN}📋 Recent Activity${NC}"
    echo "=================="
    
    if [[ -f "${LOG_DIR}/master_orchestrator.log" ]]; then
        echo "Last 3 log entries:"
        tail -n 3 "${LOG_DIR}/master_orchestrator.log" 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    else
        echo "No logs available yet"
    fi
}

# Run system tests
run_tests() {
    log "🧪 Running system tests..."
    
    source "$VENV_PATH/bin/activate"
    
    # Test 1: Check if all Python modules can be imported
    log "Testing Python module imports..."
    
    local test_script="${SCRIPT_DIR}/test_imports.py"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env python3
import sys
import importlib

modules_to_test = [
    'numpy',
    'pandas', 
    'sklearn',
    'flask',
    'redis',
    'aiohttp',
    'websockets',
    'requests'
]

failed_imports = []

for module in modules_to_test:
    try:
        importlib.import_module(module)
        print(f"✅ {module}")
    except ImportError as e:
        print(f"❌ {module}: {e}")
        failed_imports.append(module)

if failed_imports:
    print(f"\n❌ Failed to import: {', '.join(failed_imports)}")
    sys.exit(1)
else:
    print("\n✅ All modules imported successfully")
    sys.exit(0)
EOF
    
    if python3 "$test_script"; then
        log_success "Module import test passed"
    else
        log_error "Module import test failed"
        rm -f "$test_script"
        return 1
    fi
    
    rm -f "$test_script"
    
    # Test 2: Check database connectivity
    log "Testing database connectivity..."
    
    local db_test_script="${SCRIPT_DIR}/test_db.py"
    cat > "$db_test_script" << 'EOF'
#!/usr/bin/env python3
import sqlite3
import os

db_path = "/data/blockchain/nodes/logs/test_connection.db"

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)")
    cursor.execute("INSERT INTO test (value) VALUES ('test')")
    cursor.execute("SELECT * FROM test")
    result = cursor.fetchone()
    conn.close()
    
    if os.path.exists(db_path):
        os.remove(db_path)
    
    print("✅ Database connectivity test passed")
except Exception as e:
    print(f"❌ Database connectivity test failed: {e}")
    exit(1)
EOF
    
    if python3 "$db_test_script"; then
        log_success "Database connectivity test passed"
    else
        log_error "Database connectivity test failed"
        rm -f "$db_test_script"
        return 1
    fi
    
    rm -f "$db_test_script"
    
    # Test 3: Quick system functionality test
    log "Testing system functionality..."
    
    # Start a system briefly to test
    if start_system "test_performance" "real_time_performance_dashboard.py" "Test Performance Dashboard"; then
        sleep 5
        stop_system "test_performance" "Test Performance Dashboard"
        log_success "System functionality test passed"
    else
        log_error "System functionality test failed"
        return 1
    fi
    
    log_success "🎉 All tests passed!"
}

# Show system logs
show_logs() {
    local system="$1"
    
    if [[ -n "$system" ]]; then
        local log_file="${LOG_DIR}/${system}.log"
        if [[ -f "$log_file" ]]; then
            echo -e "${CYAN}📋 Logs for $system:${NC}"
            echo "========================="
            tail -f "$log_file"
        else
            log_error "Log file not found: $log_file"
        fi
    else
        echo -e "${CYAN}📋 Available log files:${NC}"
        echo "======================"
        ls -la "${LOG_DIR}"/*.log 2>/dev/null | while read -r line; do
            echo "  $line"
        done
        
        echo ""
        echo "Usage: $0 logs [system_name]"
        echo "Example: $0 logs master_orchestrator"
    fi
}

# Check system health
check_health() {
    log "🏥 Checking system health..."
    
    # Check if master orchestrator is running and responsive
    if curl -s http://localhost:8091/api/health &>/dev/null; then
        log_success "Master orchestrator is responsive"
        
        # Get health data
        health_data=$(curl -s http://localhost:8091/api/health 2>/dev/null)
        if [[ -n "$health_data" ]]; then
            echo "Health Summary:"
            echo "$health_data" | python3 -m json.tool 2>/dev/null || echo "$health_data"
        fi
    else
        log_warning "Master orchestrator not responsive on port 8091"
    fi
    
    # Check individual system health
    declare -A SYSTEMS=(
        ["master_orchestrator"]="Master Monitoring Orchestrator"
        ["performance_dashboard"]="Real-Time Performance Dashboard"
        ["predictive_analytics"]="Predictive Analytics Engine"
        ["alerting_system"]="Advanced Alerting System"
        ["revenue_optimization"]="Revenue Optimization Analytics"
        ["competitive_intelligence"]="Competitive Intelligence System"
    )
    
    echo ""
    echo "Individual System Health:"
    echo "========================"
    
    for system in master_orchestrator performance_dashboard predictive_analytics alerting_system revenue_optimization competitive_intelligence; do
        description="${SYSTEMS[$system]}"
        local pid_file="${PID_DIR}/${system}.pid"
        local log_file="${LOG_DIR}/${system}.log"
        
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                # Check for recent errors in logs
                if [[ -f "$log_file" ]]; then
                    local error_count=$(tail -n 100 "$log_file" 2>/dev/null | grep -c "ERROR\|❌" || echo "0")
                    if [[ "$error_count" -gt 0 ]]; then
                        echo -e "  $description: ${YELLOW}Running (${error_count} recent errors)${NC}"
                    else
                        echo -e "  $description: ${GREEN}Healthy${NC}"
                    fi
                else
                    echo -e "  $description: ${GREEN}Running${NC}"
                fi
            else
                echo -e "  $description: ${RED}Dead process${NC}"
            fi
        else
            echo -e "  $description: ${RED}Not running${NC}"
        fi
    done
}

# Main script logic
case "${1:-}" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 2
        start_all
        ;;
    status)
        show_status
        ;;
    test)
        run_tests
        ;;
    logs)
        show_logs "$2"
        ;;
    health)
        check_health
        ;;
    *)
        echo "Advanced MEV Monitoring Suite Deployment Script"
        echo ""
        echo "Usage: $0 [start|stop|restart|status|test|logs|health]"
        echo ""
        echo "Commands:"
        echo "  start    - Start all monitoring systems"
        echo "  stop     - Stop all monitoring systems"
        echo "  restart  - Restart all monitoring systems"
        echo "  status   - Show system status"
        echo "  test     - Run system tests"
        echo "  logs     - Show system logs"
        echo "  health   - Check system health"
        echo ""
        echo "Examples:"
        echo "  $0 start                    # Start all systems"
        echo "  $0 status                   # Check status"
        echo "  $0 logs master_orchestrator # View orchestrator logs"
        echo "  $0 health                   # Check system health"
        exit 1
        ;;
esac