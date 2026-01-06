#!/bin/bash
#
# Geth Management Wrapper Script
# This script provides a simplified interface to manage Geth node operations
#
# Usage: ./manage_geth.sh <action> [options]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values - updated for production infrastructure
GETH_VERSION="latest"
NETWORK="mainnet"
SYNC_MODE="snap"
CONFIG_FILE="/data/blockchain/nodes/config/geth_backup.yaml"
BACKUP_DIR="/data/blockchain/nodes/backups"

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_python() {
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi
}

ensure_directories() {
    log_info "Creating necessary directories..."
    mkdir -p /data/blockchain/nodes/{config,data,logs,backups,bin}
    mkdir -p /data/blockchain/nodes/state
    mkdir -p /data/blockchain/nodes/monitoring
    mkdir -p $BACKUP_DIR

    # Set proper permissions
    chown -R root:root /data/blockchain/nodes
    chmod 755 /data/blockchain/nodes
    chmod 755 /data/blockchain/nodes/state
    chmod 755 /data/blockchain/nodes/monitoring
}

install_dependencies() {
    log_info "Installing system dependencies..."
    apt-get update
    apt-get install -y curl wget tar jq python3 python3-pip git
    pip3 install requests psutil pyyaml jsonschema
}

show_help() {
    cat << EOF
Geth Management Script

Usage: $0 <action> [options]

ACTIONS:
    install     Install Geth client
    uninstall   Remove Geth client
    setup       Complete Geth setup (install + configure + start)
    start       Start Geth service
    stop        Stop Geth service
    restart     Restart Geth service
    status      Show Geth status
    logs        Show Geth logs
    backup      Backup Geth data
    restore     Restore Geth data from backup
    optimize    Show performance optimizations
    update      Update Geth to latest version

OPTIONS:
    --version <version>     Geth version to install (default: latest)
    --network <network>     Network to use (mainnet, goerli, sepolia) (default: mainnet)
    --sync-mode <mode>      Sync mode (fast, full, snap, light) (default: snap)
    --config <path>         Configuration file path (default: /etc/geth/config.yaml)
    --backup-path <path>    Backup file path (for restore)
    --lines <number>        Number of log lines to show (default: 100)
    --follow                Follow logs in real-time
    --help                  Show this help message

EXAMPLES:
    $0 setup
    $0 setup --network sepolia --sync-mode fast
    $0 start
    $0 status
    $0 logs --follow
    $0 backup
    $0 restore --backup-path /opt/backups/geth_backup_20231211_143022.tar.gz
    $0 optimize

EOF
}

validate_network() {
    local network=$1
    case $network in
        mainnet|goerli|sepolia|holesky|gnosis|polygon)
            return 0
            ;;
        *)
            log_error "Invalid network: $network"
            log_error "Valid networks: mainnet, goerli, sepolia, holesky, gnosis, polygon"
            return 1
            ;;
    esac
}

validate_sync_mode() {
    local mode=$1
    case $mode in
        fast|full|snap|light)
            return 0
            ;;
        *)
            log_error "Invalid sync mode: $mode"
            log_error "Valid sync modes: fast, full, snap, light"
            return 1
            ;;
    esac
}

check_existing_installation() {
    if command -v geth &> /dev/null; then
        local version=$(geth version 2>/dev/null | head -1)
        log_info "Geth is already installed: $version"
        return 0
    else
        log_info "Geth is not installed"
        return 1
    fi
}

install_geth() {
    log_info "Starting Geth installation..."

    # Check if already installed
    if check_existing_installation; then
        log_warning "Geth is already installed. Use 'update' action to upgrade."
        return 0
    fi

    # Install dependencies
    install_dependencies

    # Use Python manager for installation
    log_info "Installing Geth version: $GETH_VERSION"
    python3 /data/blockchain/nodes/geth_manager.py install --version "$GETH_VERSION"

    if [[ $? -eq 0 ]]; then
        log_success "Geth installation completed successfully"
    else
        log_error "Geth installation failed"
        exit 1
    fi
}

setup_geth() {
    log_info "Starting complete Geth setup..."

    # Validate inputs
    if ! validate_network "$NETWORK"; then
        exit 1
    fi

    if ! validate_sync_mode "$SYNC_MODE"; then
        exit 1
    fi

    # Ensure directories exist
    ensure_directories

    # Install Geth if not already installed
    if ! check_existing_installation; then
        install_geth
    fi

    # Run setup through Python manager
    log_info "Configuring Geth for $NETWORK network with $SYNC_MODE sync mode"
    python3 /data/blockchain/nodes/geth_manager.py setup \
        --network "$NETWORK" \
        --sync-mode "$SYNC_MODE" \
        --config "$CONFIG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "Geth setup completed successfully"
        log_info "Service status: $(systemctl is-active geth 2>/dev/null || echo 'inactive')"
        log_info "HTTP RPC: http://127.0.0.1:8549"
        log_info "WebSocket: ws://127.0.0.1:8550"
        log_info "Metrics: http://127.0.0.1:6069/metrics"
        log_info "Auth RPC: http://127.0.0.1:8554"
    else
        log_error "Geth setup failed"
        exit 1
    fi
}

start_geth() {
    log_info "Starting Geth service..."
    python3 /data/blockchain/nodes/geth_manager.py start --config "$CONFIG_FILE"
}

stop_geth() {
    log_info "Stopping Geth service..."
    python3 /data/blockchain/nodes/geth_manager.py stop --config "$CONFIG_FILE"
}

restart_geth() {
    log_info "Restarting Geth service..."
    python3 /data/blockchain/nodes/geth_manager.py restart --config "$CONFIG_FILE"
}

show_status() {
    log_info "Getting Geth status..."
    python3 /data/blockchain/nodes/geth_manager.py status --config "$CONFIG_FILE"
}

show_logs() {
    local lines=${1:-100}
    local follow=${2:-false}

    log_info "Getting Geth logs (last $lines lines)..."
    python3 /data/blockchain/nodes/geth_manager.py logs --config "$CONFIG_FILE" --lines "$lines" ${follow:+--follow}
}

create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/geth_backup_$timestamp.tar.gz"

    log_info "Creating Geth backup..."
    python3 /data/blockchain/nodes/geth_manager.py backup --backup-path "$backup_path" --config "$CONFIG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "Backup created: $backup_path"

        # Show backup info
        local size=$(du -h "$backup_path" 2>/dev/null | cut -f1)
        log_info "Backup size: $size"
    else
        log_error "Backup creation failed"
        exit 1
    fi
}

restore_backup() {
    local backup_path=$1

    if [[ -z "$backup_path" ]]; then
        log_error "Backup path is required for restore operation"
        log_info "Usage: $0 restore --backup-path <backup-file>"
        exit 1
    fi

    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_path"
        exit 1
    fi

    log_info "Restoring Geth from backup..."
    log_warning "This will replace current Geth data and restart the service"
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        python3 /data/blockchain/nodes/geth_manager.py restore --backup-path "$backup_path" --config "$CONFIG_FILE"

        if [[ $? -eq 0 ]]; then
            log_success "Backup restored successfully"
            log_info "Geth service has been restarted"
        else
            log_error "Backup restore failed"
            exit 1
        fi
    else
        log_info "Restore operation cancelled"
    fi
}

show_optimizations() {
    log_info "Analyzing Geth performance..."
    python3 /data/blockchain/nodes/geth_manager.py optimize --config "$CONFIG_FILE"
}

update_geth() {
    log_info "Updating Geth to latest version..."
    install_geth

    if systemctl is-active geth &>/dev/null; then
        log_info "Restarting Geth with updated binary..."
        restart_geth
    fi

    log_success "Geth update completed"
}

uninstall_geth() {
    log_warning "This will completely remove Geth and all its data"
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        python3 /data/blockchain/nodes/geth_manager.py uninstall --config "$CONFIG_FILE"

        if [[ $? -eq 0 ]]; then
            log_success "Geth uninstalled successfully"
        else
            log_error "Geth uninstallation failed"
            exit 1
        fi
    else
        log_info "Uninstallation cancelled"
    fi
}

# Parse command line arguments
ACTION=""
FOLLOW=false
LINES=100
BACKUP_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        install|uninstall|setup|start|stop|restart|status|logs|backup|restore|optimize|update|help)
            ACTION="$1"
            shift
            ;;
        --version)
            GETH_VERSION="$2"
            shift 2
            ;;
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --sync-mode)
            SYNC_MODE="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --backup-path)
            BACKUP_PATH="$2"
            shift 2
            ;;
        --lines)
            LINES="$2"
            shift 2
            ;;
        --follow)
            FOLLOW=true
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

# Check if action is provided
if [[ -z "$ACTION" ]]; then
    log_error "No action specified"
    show_help
    exit 1
fi

# Check for root privileges
if [[ "$ACTION" != "help" && "$ACTION" != "status" ]]; then
    check_root
fi

# Check Python installation
if [[ "$ACTION" != "help" ]]; then
    check_python
fi

# Ensure Python script exists
if [[ ! -f "/data/blockchain/nodes/geth_manager.py" ]]; then
    log_error "Geth manager script not found: /data/blockchain/nodes/geth_manager.py"
    exit 1
fi

# Execute requested action
case $ACTION in
    install)
        install_geth
        ;;
    uninstall)
        uninstall_geth
        ;;
    setup)
        setup_geth
        ;;
    start)
        start_geth
        ;;
    stop)
        stop_geth
        ;;
    restart)
        restart_geth
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$LINES" "$FOLLOW"
        ;;
    backup)
        create_backup
        ;;
    restore)
        restore_backup "$BACKUP_PATH"
        ;;
    optimize)
        show_optimizations
        ;;
    update)
        update_geth
        ;;
    help)
        show_help
        ;;
    *)
        log_error "Unknown action: $ACTION"
        show_help
        exit 1
        ;;
esac