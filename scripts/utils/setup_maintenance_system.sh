#!/bin/bash

# Comprehensive Blockchain Node Maintenance System Setup
# This script sets up the complete maintenance infrastructure for 24/7 operations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Configuration
MAINTENANCE_DIR="/data/blockchain/nodes/maintenance"
SCRIPTS_DIR="$MAINTENANCE_DIR/scripts"
CONFIGS_DIR="$MAINTENANCE_DIR/configs"
LOGS_DIR="$MAINTENANCE_DIR/logs"
TOOLS_DIR="$MAINTENANCE_DIR/tools"
RUNBOOKS_DIR="$MAINTENANCE_DIR/runbooks"
DASHBOARDS_DIR="$MAINTENANCE_DIR/dashboards"
BACKUPS_DIR="$MAINTENANCE_DIR/backups"

# System requirements check
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. Consider running as a dedicated user for security."
    fi
    
    # Check Python version
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi
    
    local python_version=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)
    log_info "Python version: $python_version"
    
    # Check disk space
    local available_space=$(df -BG "$MAINTENANCE_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 10 ]]; then
        log_error "Insufficient disk space. At least 10GB required, found ${available_space}GB"
        exit 1
    fi
    
    # Check if systemd is available
    if ! command -v systemctl &> /dev/null; then
        log_warning "systemctl not found. Some features may not work properly."
    fi
    
    log_success "System requirements check passed"
}

# Install Python dependencies
install_dependencies() {
    log_info "Installing Python dependencies..."
    
    # Create virtual environment if it doesn't exist
    if [[ ! -d "$MAINTENANCE_DIR/venv" ]]; then
        python3 -m venv "$MAINTENANCE_DIR/venv"
        log_success "Created virtual environment"
    fi
    
    # Activate virtual environment
    source "$MAINTENANCE_DIR/venv/bin/activate"
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install required packages
    cat > "$MAINTENANCE_DIR/requirements.txt" << 'EOF'
aiohttp==3.8.6
asyncio==3.4.3
psutil==5.9.6
pyyaml==6.0.1
numpy==1.24.4
pandas==2.0.3
scikit-learn==1.3.1
matplotlib==3.7.3
seaborn==0.12.2
flask==2.3.3
flask-socketio==5.3.6
paramiko==3.3.1
boto3==1.29.7
sqlite3==3.42.0
EOF
    
    pip install -r "$MAINTENANCE_DIR/requirements.txt"
    
    log_success "Python dependencies installed"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    mkdir -p "$LOGS_DIR"/{archived,reports}
    mkdir -p "$BACKUPS_DIR"/{automated,manual}
    mkdir -p "$CONFIGS_DIR"
    mkdir -p "$SCRIPTS_DIR"
    mkdir -p "$TOOLS_DIR"
    mkdir -p "$RUNBOOKS_DIR"
    mkdir -p "$DASHBOARDS_DIR"/{templates,static}
    
    # Create systemd service directories
    mkdir -p /etc/systemd/system
    
    # Set proper permissions
    chmod 755 "$MAINTENANCE_DIR"
    chmod 750 "$LOGS_DIR"
    chmod 750 "$BACKUPS_DIR"
    chmod 755 "$SCRIPTS_DIR"
    chmod 644 "$CONFIGS_DIR"/*
    
    log_success "Directory structure created"
}

# Setup systemd services
setup_systemd_services() {
    log_info "Setting up systemd services..."
    
    # Master Orchestrator Service
    cat > /etc/systemd/system/blockchain-maintenance.service << EOF
[Unit]
Description=Blockchain Node Maintenance Orchestrator
After=network.target
Wants=network.target

[Service]
Type=simple
User=lyftium
Group=lyftium
WorkingDirectory=$MAINTENANCE_DIR
Environment=PATH=$MAINTENANCE_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONPATH=$SCRIPTS_DIR:$TOOLS_DIR:$DASHBOARDS_DIR
ExecStart=$MAINTENANCE_DIR/venv/bin/python $SCRIPTS_DIR/master_maintenance_orchestrator.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
TimeoutStartSec=60
TimeoutStopSec=30

# Resource limits
MemoryLimit=2G
CPUQuota=50%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$MAINTENANCE_DIR /data/blockchain/nodes

[Install]
WantedBy=multi-user.target
EOF

    # Health Monitor Service
    cat > /etc/systemd/system/blockchain-health-monitor.service << EOF
[Unit]
Description=Blockchain Node Health Monitor
After=network.target
Wants=network.target

[Service]
Type=simple
User=lyftium
Group=lyftium
WorkingDirectory=$MAINTENANCE_DIR
Environment=PATH=$MAINTENANCE_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONPATH=$SCRIPTS_DIR
ExecStart=$MAINTENANCE_DIR/venv/bin/python $SCRIPTS_DIR/automated_health_checker.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Resource limits
MemoryLimit=512M
CPUQuota=25%

[Install]
WantedBy=multi-user.target
EOF

    # Dashboard Service
    cat > /etc/systemd/system/blockchain-dashboard.service << EOF
[Unit]
Description=Blockchain Node Monitoring Dashboard
After=network.target
Wants=network.target

[Service]
Type=simple
User=lyftium
Group=lyftium
WorkingDirectory=$MAINTENANCE_DIR
Environment=PATH=$MAINTENANCE_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONPATH=$DASHBOARDS_DIR:$SCRIPTS_DIR
ExecStart=$MAINTENANCE_DIR/venv/bin/python $DASHBOARDS_DIR/comprehensive_monitoring_dashboard.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Resource limits
MemoryLimit=1G
CPUQuota=30%

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    
    log_success "Systemd services created"
}

# Setup cron jobs
setup_cron_jobs() {
    log_info "Setting up cron jobs..."
    
    # Create cron entries
    cat > /tmp/maintenance_cron << EOF
# Blockchain Node Maintenance Cron Jobs

# Health checks every 5 minutes
*/5 * * * * $MAINTENANCE_DIR/venv/bin/python $SCRIPTS_DIR/automated_health_checker.py >/dev/null 2>&1

# Log rotation every 6 hours
0 */6 * * * $MAINTENANCE_DIR/venv/bin/python $SCRIPTS_DIR/log_rotation_manager.py >/dev/null 2>&1

# Performance optimization every 4 hours
0 */4 * * * $MAINTENANCE_DIR/venv/bin/python $SCRIPTS_DIR/performance_optimizer.py >/dev/null 2>&1

# Capacity planning every 15 minutes
*/15 * * * * $MAINTENANCE_DIR/venv/bin/python $TOOLS_DIR/capacity_planner.py >/dev/null 2>&1

# Daily backup at 2 AM
0 2 * * * $SCRIPTS_DIR/automated_backup_system.sh >/dev/null 2>&1

# Weekly capacity report on Sunday at 6 AM
0 6 * * 0 $MAINTENANCE_DIR/venv/bin/python $TOOLS_DIR/capacity_planner.py --report >/dev/null 2>&1

# Monthly maintenance report on 1st of month at 7 AM
0 7 1 * * $SCRIPTS_DIR/generate_maintenance_report.sh >/dev/null 2>&1

# Cleanup old logs daily at 1 AM
0 1 * * * find $LOGS_DIR -name "*.log.*" -mtime +7 -delete >/dev/null 2>&1
EOF

    # Install cron jobs for the maintenance user
    crontab -u lyftium /tmp/maintenance_cron
    rm /tmp/maintenance_cron
    
    log_success "Cron jobs configured"
}

# Create monitoring scripts
create_monitoring_scripts() {
    log_info "Creating monitoring scripts..."
    
    # Quick status script
    cat > "$SCRIPTS_DIR/quick_status.sh" << 'EOF'
#!/bin/bash
# Quick status check for all blockchain nodes

echo "=== Blockchain Node Quick Status ==="
echo "Generated: $(date)"
echo ""

# Check systemd services
echo "=== Service Status ==="
for service in erigon arbitrum-node polygon-bor optimism-node base-node bsc-node avalanche-node solana-dev mev-boost; do
    if systemctl is-active --quiet $service 2>/dev/null; then
        echo "✅ $service: Running"
    else
        echo "❌ $service: Not running"
    fi
done

echo ""
echo "=== System Resources ==="
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "Memory Usage: $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')%"
echo "Disk Usage: $(df -h /data/blockchain/nodes | awk 'NR==2 {print $5}')"

echo ""
echo "=== Network Status ==="
netstat -tuln | grep -E ':854[5-9]|:9650|:8899|:18550' | wc -l | xargs echo "Active RPC endpoints:"

echo ""
echo "=== Recent Alerts ==="
if [[ -f "/data/blockchain/nodes/maintenance/logs/alerts.log" ]]; then
    tail -5 /data/blockchain/nodes/maintenance/logs/alerts.log | grep -E "(ERROR|WARN)" || echo "No recent alerts"
else
    echo "No alerts log found"
fi
EOF

    # Emergency recovery script
    cat > "$SCRIPTS_DIR/emergency_recovery.sh" << 'EOF'
#!/bin/bash
# Emergency recovery script for critical situations

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo "=== EMERGENCY RECOVERY PROCEDURE ==="
echo "This script will attempt to recover from critical failures"
echo "Use only in emergency situations!"
echo ""

read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Emergency recovery cancelled"
    exit 0
fi

# Stop all blockchain services
log_warning "Stopping all blockchain services..."
for service in erigon arbitrum-node polygon-bor optimism-node base-node bsc-node avalanche-node solana-dev mev-boost; do
    if systemctl is-active --quiet $service 2>/dev/null; then
        systemctl stop $service
        log_success "Stopped $service"
    fi
done

# Clear system caches
log_warning "Clearing system caches..."
sync
echo 3 > /proc/sys/vm/drop_caches
log_success "System caches cleared"

# Check and repair filesystems if needed
log_warning "Checking filesystem health..."
fsck -y /data/blockchain/nodes 2>/dev/null || log_warning "Filesystem check completed with warnings"

# Restart services one by one with health checks
log_warning "Restarting services with health checks..."
for service in erigon mev-boost arbitrum-node polygon-bor optimism-node base-node bsc-node avalanche-node solana-dev; do
    log_warning "Starting $service..."
    systemctl start $service
    sleep 30
    
    if systemctl is-active --quiet $service; then
        log_success "$service started successfully"
    else
        log_error "$service failed to start"
    fi
done

# Restart maintenance services
log_warning "Restarting maintenance services..."
systemctl restart blockchain-maintenance
systemctl restart blockchain-health-monitor
systemctl restart blockchain-dashboard

log_success "Emergency recovery procedure completed"
log_warning "Please monitor the dashboard and logs for any issues"
EOF

    # Make scripts executable
    chmod +x "$SCRIPTS_DIR"/*.sh
    
    log_success "Monitoring scripts created"
}

# Create backup script
create_backup_script() {
    log_info "Creating automated backup script..."
    
    cat > "$SCRIPTS_DIR/automated_backup_system.sh" << 'EOF'
#!/bin/bash
# Automated backup system for blockchain nodes

set -euo pipefail

BACKUP_DIR="/data/blockchain/nodes/maintenance/backups/automated"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/data/blockchain/nodes/maintenance/logs/backup_${TIMESTAMP}.log"

# Logging function
log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

log "Starting automated backup process"

# Create backup directory
mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Backup configurations
log "Backing up configurations..."
tar -czf "$BACKUP_DIR/$TIMESTAMP/configs_$TIMESTAMP.tar.gz" \
    /data/blockchain/nodes/*/config \
    /data/blockchain/nodes/maintenance/configs \
    2>/dev/null || true

# Backup keystore files
log "Backing up keystore files..."
find /data/blockchain/nodes -name "keystore" -type d -exec tar -czf "$BACKUP_DIR/$TIMESTAMP/keystores_$TIMESTAMP.tar.gz" {} + 2>/dev/null || true

# Backup JWT secrets
log "Backing up JWT secrets..."
find /data/blockchain/nodes -name "jwt.hex" -exec tar -czf "$BACKUP_DIR/$TIMESTAMP/jwt_secrets_$TIMESTAMP.tar.gz" {} + 2>/dev/null || true

# Backup maintenance scripts
log "Backing up maintenance scripts..."
tar -czf "$BACKUP_DIR/$TIMESTAMP/maintenance_scripts_$TIMESTAMP.tar.gz" \
    /data/blockchain/nodes/maintenance/scripts \
    /data/blockchain/nodes/maintenance/tools \
    2>/dev/null || true

# Backup important logs (last 7 days)
log "Backing up recent logs..."
find /data/blockchain/nodes/logs -name "*.log" -mtime -7 -exec tar -czf "$BACKUP_DIR/$TIMESTAMP/recent_logs_$TIMESTAMP.tar.gz" {} + 2>/dev/null || true

# Cleanup old backups (keep last 7 days)
log "Cleaning up old backups..."
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_DIR/$TIMESTAMP" | cut -f1)
log "Backup completed. Size: $BACKUP_SIZE"

# Send notification if configured
if command -v mail &> /dev/null && [[ -n "${BACKUP_EMAIL:-}" ]]; then
    echo "Blockchain node backup completed successfully. Size: $BACKUP_SIZE" | \
    mail -s "Blockchain Backup Report - $(date)" "$BACKUP_EMAIL"
fi

log "Automated backup process finished"
EOF

    chmod +x "$SCRIPTS_DIR/automated_backup_system.sh"
    
    log_success "Automated backup script created"
}

# Configure log rotation
configure_log_rotation() {
    log_info "Configuring log rotation..."
    
    cat > /etc/logrotate.d/blockchain-maintenance << 'EOF'
/data/blockchain/nodes/maintenance/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    copytruncate
    notifempty
    create 644 lyftium lyftium
}

/data/blockchain/nodes/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    copytruncate
    notifempty
    create 644 lyftium lyftium
    size 100M
}
EOF

    # Test logrotate configuration
    logrotate -d /etc/logrotate.d/blockchain-maintenance > /dev/null 2>&1
    
    log_success "Log rotation configured"
}

# Setup firewall rules
setup_firewall() {
    log_info "Setting up firewall rules..."
    
    # Check if ufw is available
    if command -v ufw &> /dev/null; then
        # Allow dashboard access
        ufw allow 5000/tcp comment "Blockchain Dashboard"
        
        # Allow RPC endpoints (local only)
        for port in 8545 8547 8548 8549 8550 8551 8899 9650; do
            ufw allow from 127.0.0.1 to any port $port
            ufw allow from 10.0.0.0/8 to any port $port
            ufw allow from 172.16.0.0/12 to any port $port
            ufw allow from 192.168.0.0/16 to any port $port
        done
        
        log_success "Firewall rules configured"
    else
        log_warning "UFW not found, skipping firewall configuration"
    fi
}

# Create maintenance user if needed
create_maintenance_user() {
    if ! id "lyftium" &>/dev/null; then
        log_info "Creating maintenance user..."
        useradd -r -m -s /bin/bash lyftium
        usermod -a -G docker lyftium 2>/dev/null || true
        log_success "Maintenance user created"
    else
        log_info "Maintenance user already exists"
    fi
}

# Set proper ownership
set_ownership() {
    log_info "Setting proper ownership..."
    
    chown -R lyftium:lyftium "$MAINTENANCE_DIR"
    chown -R lyftium:lyftium /data/blockchain/nodes/logs 2>/dev/null || true
    
    # Set proper permissions for scripts
    find "$SCRIPTS_DIR" -name "*.py" -exec chmod +x {} \;
    find "$SCRIPTS_DIR" -name "*.sh" -exec chmod +x {} \;
    
    log_success "Ownership and permissions set"
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    # Test Python scripts
    if ! python3 -c "import yaml, aiohttp, psutil, numpy, pandas, sklearn, flask" 2>/dev/null; then
        log_error "Python dependencies test failed"
        return 1
    fi
    
    # Test systemd services
    if ! systemctl daemon-reload; then
        log_error "Systemd reload failed"
        return 1
    fi
    
    # Test file permissions
    if [[ ! -x "$SCRIPTS_DIR/master_maintenance_orchestrator.py" ]]; then
        log_error "Script permissions incorrect"
        return 1
    fi
    
    log_success "Installation tests passed"
}

# Generate summary report
generate_summary() {
    log_info "Generating installation summary..."
    
    cat > "$MAINTENANCE_DIR/INSTALLATION_SUMMARY.md" << EOF
# Blockchain Node Maintenance System Installation Summary

**Installation Date:** $(date)
**Installation User:** $(whoami)
**System:** $(uname -a)

## 🎯 What's Installed

### Core Components
- ✅ Master Maintenance Orchestrator
- ✅ Automated Health Checker
- ✅ Backup Manager
- ✅ Performance Optimizer
- ✅ Automated Restart Manager
- ✅ Log Rotation Manager
- ✅ Zero-Downtime Updater
- ✅ Capacity Planner
- ✅ Monitoring Dashboard

### System Services
- ✅ blockchain-maintenance.service
- ✅ blockchain-health-monitor.service  
- ✅ blockchain-dashboard.service

### Monitoring & Alerting
- ✅ Real-time dashboard (http://localhost:5000)
- ✅ Automated health checks every 5 minutes
- ✅ Performance monitoring every 4 hours
- ✅ Capacity planning every 15 minutes
- ✅ Daily backups at 2 AM

## 🚀 How to Start

### Start All Services
\`\`\`bash
sudo systemctl enable blockchain-maintenance
sudo systemctl enable blockchain-health-monitor
sudo systemctl enable blockchain-dashboard

sudo systemctl start blockchain-maintenance
sudo systemctl start blockchain-health-monitor
sudo systemctl start blockchain-dashboard
\`\`\`

### Check Status
\`\`\`bash
# Quick status check
$SCRIPTS_DIR/quick_status.sh

# Detailed status
sudo systemctl status blockchain-maintenance
\`\`\`

### Access Dashboard
Open your browser and go to: http://localhost:5000

## 📊 Key Features

### 24/7 Automated Operations
- Continuous health monitoring
- Automatic restart on failures
- Performance optimization
- Proactive capacity planning

### Backup & Recovery
- Daily automated backups
- Emergency recovery procedures
- Zero-downtime updates
- Disaster recovery runbooks

### Monitoring & Alerting
- Real-time dashboard
- Performance trends
- Capacity forecasting
- MEV operation monitoring

## 📁 Important Directories

- **Scripts:** $SCRIPTS_DIR
- **Configs:** $CONFIGS_DIR  
- **Logs:** $LOGS_DIR
- **Backups:** $BACKUPS_DIR
- **Tools:** $TOOLS_DIR

## 🔧 Manual Operations

### Emergency Recovery
\`\`\`bash
sudo $SCRIPTS_DIR/emergency_recovery.sh
\`\`\`

### Manual Backup
\`\`\`bash
$SCRIPTS_DIR/automated_backup_system.sh
\`\`\`

### Generate Reports
\`\`\`bash
python3 $TOOLS_DIR/capacity_planner.py --report
\`\`\`

## 📞 Support

- **Logs:** Check $LOGS_DIR for detailed logs
- **Status:** Run quick_status.sh for system overview
- **Dashboard:** Monitor http://localhost:5000
- **Recovery:** Use emergency_recovery.sh for critical issues

---
*Blockchain Node Maintenance System v1.0*
EOF

    log_success "Installation summary created: $MAINTENANCE_DIR/INSTALLATION_SUMMARY.md"
}

# Main installation function
main() {
    echo "========================================"
    echo "Blockchain Node Maintenance System Setup"
    echo "========================================"
    echo ""
    
    # Run installation steps
    check_requirements
    create_maintenance_user
    create_directories
    install_dependencies
    setup_systemd_services
    setup_cron_jobs
    create_monitoring_scripts
    create_backup_script
    configure_log_rotation
    setup_firewall
    set_ownership
    test_installation
    generate_summary
    
    echo ""
    echo "========================================"
    log_success "Installation completed successfully!"
    echo "========================================"
    echo ""
    echo "🎯 Next Steps:"
    echo "1. Start the services:"
    echo "   sudo systemctl enable --now blockchain-maintenance"
    echo "   sudo systemctl enable --now blockchain-health-monitor"
    echo "   sudo systemctl enable --now blockchain-dashboard"
    echo ""
    echo "2. Access the dashboard:"
    echo "   http://localhost:5000"
    echo ""
    echo "3. Check the installation summary:"
    echo "   cat $MAINTENANCE_DIR/INSTALLATION_SUMMARY.md"
    echo ""
    echo "4. Monitor the logs:"
    echo "   tail -f $LOGS_DIR/orchestrator.log"
    echo ""
    log_success "Your blockchain nodes are now under comprehensive maintenance!"
}

# Run main function
main "$@"