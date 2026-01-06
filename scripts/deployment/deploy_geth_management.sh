#!/bin/bash
#
# Geth Management System Deployment Script
# This script deploys the complete Geth management infrastructure
#
# Usage: ./deploy_geth_management.sh [options]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
INSTALL_DIR="/opt/geth-management"
CONFIG_DIR="/etc/geth-management"
SERVICE_USER="geth"
SERVICE_GROUP="geth"
LOG_LEVEL="INFO"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

show_banner() {
    cat << 'EOF'
    ____              _____ _   _   _
   |  _ \            | ____| \ | | | |
   | |_) | __ _  _ __| |  _|  \| | | |
   |  _ < / _` || '__| | |___ . ` | | |
   | |_) | (_| | |  | |____/|\___| | |
   |____/ \__,_|_|  |_____|   |_|_|_|_|_|_|
           Management System Deployment
EOF
    echo
}

show_help() {
    cat << EOF
Geth Management System Deployment Script

Usage: $0 [options]

OPTIONS:
    --install-dir <path>      Installation directory (default: /opt/geth-management)
    --config-dir <path>      Configuration directory (default: /etc/geth-management)
    --user <username>         Service user (default: geth)
    --group <groupname>       Service group (default: geth)
    --log-level <level>       Log level (DEBUG, INFO, WARNING, ERROR) (default: INFO)
    --python-version <version> Python version to use (default: auto-detect)
    --skip-deps               Skip dependency installation
    --help                    Show this help message

EXAMPLES:
    $0                           # Deploy with default settings
    $0 --install-dir /usr/local/geth-management
    $0 --user ethereum --group ethereum
    $0 --log-level DEBUG

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --config-dir)
                CONFIG_DIR="$2"
                shift 2
                ;;
            --user)
                SERVICE_USER="$2"
                shift 2
                ;;
            --group)
                SERVICE_GROUP="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --python-version)
                PYTHON_VERSION="$2"
                shift 2
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

detect_python() {
    if [[ -n "${PYTHON_VERSION:-}" ]]; then
        PYTHON_CMD="python$PYTHON_VERSION"
    else
        # Find the best available Python version
        for cmd in python3.11 python3.10 python3.9 python3 python; do
            if command -v "$cmd" &> /dev/null; then
                PYTHON_CMD="$cmd"
                break
            fi
        done
    fi

    if [[ -z "$PYTHON_CMD" ]]; then
        log_error "Python 3 is required but not found"
        exit 1
    fi

    log_info "Using Python: $PYTHON_CMD"
}

install_dependencies() {
    log_step "Installing system dependencies..."

    # Update package list
    apt-get update

    # Install required packages
    local packages=(
        curl
        wget
        tar
        jq
        git
        python3-pip
        python3-dev
        python3-venv
        build-essential
        libssl-dev
        libffi-dev
        systemtap-sdt-dev
    )

    if [[ -z "${SKIP_DEPS:-}" ]]; then
        apt-get install -y "${packages[@]}"
        log_success "System dependencies installed"
    else
        log_warning "Skipping dependency installation"
    fi

    # Install Python packages
    log_step "Installing Python dependencies..."
    "$PYTHON_CMD" -m pip install --upgrade pip
    "$PYTHON_CMD" -m pip install requests psutil pyyaml jsonschema toml prometheus-client
    log_success "Python dependencies installed"
}

create_user() {
    log_step "Creating service user and group..."

    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd --system --home "$INSTALL_DIR" --shell /bin/bash "$SERVICE_USER"
        log_success "Created user: $SERVICE_USER"
    else
        log_info "User $SERVICE_USER already exists"
    fi

    # Create group if it doesn't exist
    if ! getent group "$SERVICE_GROUP" &>/dev/null; then
        groupadd "$SERVICE_GROUP"
        log_success "Created group: $SERVICE_GROUP"
    fi

    # Add user to group
    usermod -aG "$SERVICE_GROUP" "$SERVICE_USER"
}

setup_directories() {
    log_step "Creating directory structure..."

    # Create main directories
    mkdir -p "$INSTALL_DIR"/{bin,config,lib,data,logs,scripts}
    mkdir -p "$CONFIG_DIR"
    mkdir -p "/var/lib/geth"
    mkdir -p "/var/log/geth"
    mkdir -p "/opt/backups"
    mkdir -p "/etc/systemd/system"

    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR"
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "/var/lib/geth"
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "/var/log/geth"
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "/opt/backups"

    # Set proper permissions
    chmod 755 "$INSTALL_DIR"
    chmod 700 "$CONFIG_DIR"
    chmod 755 "/var/lib/geth"
    chmod 755 "/var/log/geth"
    chmod 755 "/opt/backups"

    log_success "Directory structure created"
}

install_scripts() {
    log_step "Installing management scripts..."

    # Copy main management script
    cp "/data/blockchain/nodes/geth_manager.py" "$INSTALL_DIR/bin/"
    chmod +x "$INSTALL_DIR/bin/geth_manager.py"

    # Copy wrapper script
    cp "/data/blockchain/nodes/manage_geth.sh" "$INSTALL_DIR/bin/"
    chmod +x "$INSTALL_DIR/bin/manage_geth.sh"

    # Create symlinks in system directories
    ln -sf "$INSTALL_DIR/bin/geth_manager.py" "/usr/local/bin/geth-manager"
    ln -sf "$INSTALL_DIR/bin/manage_geth.sh" "/usr/local/bin/manage-geth"

    # Create additional utility scripts
    cat > "$INSTALL_DIR/scripts/health_check.sh" << 'EOF'
#!/bin/bash
# Geth Health Check Script

SERVICE_NAME="geth"
RPC_URL="http://127.0.0.1:8545"
WS_URL="ws://127.0.0.1:8546"
METRICS_URL="http://127.0.0.1:6060/metrics"

echo "=== Geth Health Check ==="
echo "Timestamp: $(date)"
echo

# Service status
echo "Service Status:"
systemctl is-active "$SERVICE_NAME" || echo "Service: inactive"
systemctl is-enabled "$SERVICE_NAME" || echo "Service: disabled"
echo

# Process status
echo "Process Status:"
if pgrep -x geth > /dev/null; then
    echo "geth process: running (PID: $(pgrep -x geth))"
    ps -p "$(pgrep -x geth)" -o pid,ppid,cmd,etime,pcpu,pmem
else
    echo "geth process: not running"
fi
echo

# Network status
echo "Network Status:"
netstat -tlnp | grep -E ':(8545|8546|30303|6060|8551)' || echo "No listening ports found"
echo

# RPC connectivity
echo "RPC Connectivity:"
if curl -s --max-time 5 "$RPC_URL" > /dev/null; then
    echo "HTTP RPC: available"
else
    echo "HTTP RPC: unavailable"
fi

if curl -s --max-time 5 "$METRICS_URL" > /dev/null; then
    echo "Metrics: available"
else
    echo "Metrics: unavailable"
fi
echo

# Disk usage
echo "Disk Usage:"
if [ -d "/var/lib/geth" ]; then
    du -sh /var/lib/geth || echo "Cannot access data directory"
else
    echo "Data directory not found"
fi

echo "========================="
EOF

    chmod +x "$INSTALL_DIR/scripts/health_check.sh"

    # Create performance monitoring script
    cat > "$INSTALL_DIR/scripts/monitor_performance.sh" << 'EOF'
#!/bin/bash
# Geth Performance Monitoring Script

INTERVAL=${1:-30}
DURATION=${2:-300}

echo "Starting Geth performance monitoring..."
echo "Interval: ${INTERVAL}s, Duration: ${DURATION}s"
echo

END_TIME=$((SECONDS + DURATION))
COLLECTED_SAMPLES=0

while [ $SECONDS -lt $END_TIME ]; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Get system metrics
    CPU_USAGE=$(top -bn1 -p "$(pgrep -x geth 2>/dev/null | head -1)" | awk '/geth/ {print $9}' 2>/dev/null || echo "N/A")
    MEM_USAGE=$(ps -p "$(pgrep -x geth 2>/dev/null | head -1)" -o %mem 2>/dev/null || echo "N/A")

    # Get Geth-specific metrics if available
    PEER_COUNT="N/A"
    SYNC_PROGRESS="N/A"

    if curl -s --max-time 3 http://127.0.0.1:8545 > /dev/null; then
        PEER_COUNT=$(curl -s --max-time 3 -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result' 2>/dev/null || echo "N/A")

        SYNC_STATUS=$(curl -s --max-time 3 -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":2}' 2>/dev/null)
        if [ "$SYNC_STATUS" != "false" ]; then
            SYNC_PROGRESS=$(echo "$SYNC_STATUS" | jq -r '.currentBlock / .highestBlock * 100' 2>/dev/null || echo "N/A")
        else
            SYNC_PROGRESS="100"
        fi
    fi

    echo "$TIMESTAMP,CPU: $CPU_USAGE%,MEM: $MEM_USAGE%,PEERS: $PEER_COUNT,SYNC: $SYNC_PROGRESS%"

    COLLECTED_SAMPLES=$((COLLECTED_SAMPLES + 1))
    sleep $INTERVAL
done

echo "Monitoring completed. Collected $COLLECTED_SAMPLES samples."
EOF

    chmod +x "$INSTALL_DIR/scripts/monitor_performance.sh"

    log_success "Management scripts installed"
}

create_config() {
    log_step "Creating configuration files..."

    # Create main configuration
    cat > "$CONFIG_DIR/manager.yaml" << EOF
# Geth Manager Configuration

# Logging
logging:
  level: $LOG_LEVEL
  file: /var/log/geth/manager.log
  max_size: 100MB
  max_files: 10

# Default settings
defaults:
  network: mainnet
  sync_mode: snap
  data_dir: /var/lib/geth
  http_port: 8545
  ws_port: 8546
  p2p_port: 30303
  metrics_port: 6060
  max_peers: 50
  cache_size: 1024
  auth_rpc_port: 8551

# Monitoring
monitoring:
  enabled: true
  interval: 30
  metrics_retention: 7d
  alerts:
    cpu_threshold: 80
    memory_threshold: 70
    disk_threshold: 100  # GB
    peer_threshold_min: 3
    peer_threshold_max: 80

# Backup settings
backup:
  enabled: true
  directory: /opt/backups
  retention: 30d
  compression: true

# Auto-updates
auto_update:
  enabled: false
  check_interval: 24h
EOF

    # Create systemd service for management system
    cat > "/etc/systemd/system/geth-monitor.service" << 'EOF'
[Unit]
Description=Geth Monitoring Service
After=network.target geth.service
Wants=geth.service

[Service]
Type=simple
User=geth
Group=geth
Restart=always
RestartSec=30s
ExecStart=/opt/geth-management/scripts/monitor_performance.sh 60 3600
WorkingDirectory=/opt/geth-management
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    systemctl enable geth-monitor

    log_success "Configuration files created"
}

setup_logging() {
    log_step "Setting up logging..."

    # Configure log rotation for Geth
    cat > "/etc/logrotate.d/geth" << 'EOF'
/var/log/geth/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 geth geth
    postrotate
        systemctl reload geth || true
    endscript
}

/opt/geth-management/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 geth geth
}
EOF

    # Configure journald persistence
    mkdir -p /var/log/journal
    echo "Storage=persistent" >> /etc/systemd/journald.conf
    systemctl restart systemd-journald

    log_success "Logging configuration completed"
}

create_systemd_timer() {
    log_step "Creating systemd timers..."

    # Create backup timer
    cat > "/etc/systemd/system/geth-backup.timer" << 'EOF'
[Unit]
Description=Geth Daily Backup
Wants=geth-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    cat > "/etc/systemd/system/geth-backup.service" << 'EOF'
[Unit]
Description=Geth Backup Service
Requires=geth.service

[Service]
Type=oneshot
User=geth
Group=geth
ExecStart=/opt/geth-management/bin/manage-geth.sh backup

[Install]
WantedBy=multi-user.target
EOF

    # Create health check timer
    cat > "/etc/systemd/system/geth-health.timer" << 'EOF'
[Unit]
Description=Geth Health Check
Wants=geth-health.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

    cat > "/etc/systemd/system/geth-health.service" << 'EOF'
[Unit]
Description=Geth Health Check

[Service]
Type=oneshot
User=geth
Group=geth
ExecStart=/opt/geth-management/scripts/health_check.sh

[Install]
WantedBy=multi-user.target
EOF

    # Reload and enable timers
    systemctl daemon-reload
    systemctl enable geth-backup.timer
    systemctl enable geth-health.timer

    log_success "Systemd timers created"
}

verify_installation() {
    log_step "Verifying installation..."

    local errors=0

    # Check files
    local files=(
        "$INSTALL_DIR/bin/geth_manager.py"
        "$INSTALL_DIR/bin/manage_geth.sh"
        "$CONFIG_DIR/manager.yaml"
        "/etc/systemd/system/geth-monitor.service"
        "/etc/systemd/system/geth-backup.timer"
        "/etc/systemd/system/geth-health.timer"
    )

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "✓ $file"
        else
            log_error "✗ $file"
            errors=$((errors + 1))
        fi
    done

    # Check user
    if id "$SERVICE_USER" &>/dev/null; then
        log_success "✓ Service user: $SERVICE_USER"
    else
        log_error "✗ Service user: $SERVICE_USER"
        errors=$((errors + 1))
    fi

    # Check Python modules
    local modules=("requests" "psutil" "yaml" "jsonschema")
    for module in "${modules[@]}"; do
        if python3 -c "import $module" 2>/dev/null; then
            log_success "✓ Python module: $module"
        else
            log_error "✗ Python module: $module"
            errors=$((errors + 1))
        fi
    done

    if [[ $errors -eq 0 ]]; then
        log_success "Installation verification passed"
        return 0
    else
        log_error "Installation verification failed with $errors errors"
        return 1
    fi
}

show_post_install_info() {
    cat << EOF

${GREEN}🎉 Geth Management System Deployment Completed!${NC}

${CYAN}=== Quick Start Commands ===${NC}

# Check Geth status
manage-geth status

# Start Geth (if not running)
manage-geth start

# View logs
manage-geth logs --follow

# Run health check
/opt/geth-management/scripts/health_check.sh

# Monitor performance
/opt/geth-management/scripts/monitor_performance.sh

${CYAN}=== Important Files ===${NC}

• Configuration: $CONFIG_DIR/manager.yaml
• Main script: $INSTALL_DIR/bin/geth_manager.py
• Wrapper script: $INSTALL_DIR/bin/manage_geth.sh
• Service: /etc/systemd/system/geth.service
• Logs: /var/log/geth/

${CYAN}=== Services ===${NC}

• geth.service: Main Geth service
• geth-monitor.service: Performance monitoring
• geth-backup.timer: Daily backup timer
• geth-health.timer: Health check timer

${CYAN}=== Monitoring ===${NC}

• HTTP RPC: http://127.0.0.1:8545
• WebSocket: ws://127.0.0.1:8546
• Metrics: http://127.0.0.1:6060/metrics
• Auth RPC: http://127.0.0.1:8551

${YELLOW}=== Next Steps ===${NC}

1. Configure Geth settings in $CONFIG_DIR/manager.yaml
2. Start Geth with: manage-geth start
3. Monitor sync progress with: manage-geth status
4. Set up monitoring alerts as needed

EOF
}

# Main execution
main() {
    show_banner
    parse_arguments "$@"

    log_info "Starting Geth Management System deployment..."

    check_root

    detect_python
    install_dependencies
    create_user
    setup_directories
    install_scripts
    create_config
    setup_logging
    create_systemd_timer

    if verify_installation; then
        show_post_install_info
        log_success "Deployment completed successfully!"

        # Start monitoring services
        log_step "Starting monitoring services..."
        systemctl start geth-monitor
        systemctl start geth-health.timer

        exit 0
    else
        log_error "Deployment failed. Please check the errors above."
        exit 1
    fi
}

# Execute main function
main "$@"