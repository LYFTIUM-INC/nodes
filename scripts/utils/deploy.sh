#!/bin/bash

# Private Mempool Infrastructure Deployment Script
# Comprehensive deployment for world-class MEV infrastructure

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/data/blockchain/nodes"
MEMPOOL_DIR="$PROJECT_ROOT/mev/private_mempool"
LOGS_DIR="$PROJECT_ROOT/logs"
VENV_DIR="$MEMPOOL_DIR/venv"
CONFIG_DIR="$MEMPOOL_DIR/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_section() {
    echo
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed! Cleaning up..."
    if [[ -d "$VENV_DIR" ]]; then
        rm -rf "$VENV_DIR"
    fi
    exit 1
}

trap cleanup_on_error ERR

# Function to check system requirements
check_system_requirements() {
    log_section "🔍 CHECKING SYSTEM REQUIREMENTS"
    
    # Check Python version
    if command -v python3.11 &> /dev/null; then
        PYTHON_CMD="python3.11"
    elif command -v python3.10 &> /dev/null; then
        PYTHON_CMD="python3.10"
    elif command -v python3.9 &> /dev/null; then
        PYTHON_CMD="python3.9"
    elif command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    else
        log_error "Python 3.9+ is required but not found"
        exit 1
    fi
    
    PYTHON_VERSION=$($PYTHON_CMD --version | cut -d' ' -f2)
    log_info "Python version: $PYTHON_VERSION"
    
    # Check pip
    if ! $PYTHON_CMD -m pip --version &> /dev/null; then
        log_error "pip is required but not found"
        exit 1
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        log_warning "Git not found - some features may be limited"
    fi
    
    # Check available memory
    AVAILABLE_MEMORY=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [[ $AVAILABLE_MEMORY -lt 4096 ]]; then
        log_warning "Low available memory: ${AVAILABLE_MEMORY}MB (recommended: 4GB+)"
    else
        log_info "Available memory: ${AVAILABLE_MEMORY}MB"
    fi
    
    # Check disk space
    AVAILABLE_DISK=$(df -BM "$PROJECT_ROOT" | awk 'NR==2{print $4}' | sed 's/M//')
    if [[ $AVAILABLE_DISK -lt 10240 ]]; then
        log_warning "Low disk space: ${AVAILABLE_DISK}MB (recommended: 10GB+)"
    else
        log_info "Available disk space: ${AVAILABLE_DISK}MB"
    fi
    
    log_success "System requirements check completed"
}

# Function to create directories
create_directories() {
    log_section "📁 CREATING DIRECTORY STRUCTURE"
    
    # Create required directories
    mkdir -p "$LOGS_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$MEMPOOL_DIR/data"
    mkdir -p "$MEMPOOL_DIR/backups"
    
    # Set proper permissions
    chmod 755 "$MEMPOOL_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$LOGS_DIR"
    
    log_success "Directory structure created"
}

# Function to setup Python virtual environment
setup_virtual_environment() {
    log_section "🐍 SETTING UP PYTHON VIRTUAL ENVIRONMENT"
    
    # Remove existing virtual environment if it exists
    if [[ -d "$VENV_DIR" ]]; then
        log_info "Removing existing virtual environment..."
        rm -rf "$VENV_DIR"
    fi
    
    # Create new virtual environment
    log_info "Creating virtual environment with $PYTHON_CMD..."
    $PYTHON_CMD -m venv "$VENV_DIR"
    
    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip
    log_info "Upgrading pip..."
    pip install --upgrade pip setuptools wheel
    
    log_success "Virtual environment created and activated"
}

# Function to install Python dependencies
install_dependencies() {
    log_section "📦 INSTALLING PYTHON DEPENDENCIES"
    
    # Ensure virtual environment is activated
    source "$VENV_DIR/bin/activate"
    
    # Install requirements
    log_info "Installing requirements from requirements.txt..."
    pip install -r "$MEMPOOL_DIR/requirements.txt"
    
    # Verify critical packages
    log_info "Verifying critical package installations..."
    
    CRITICAL_PACKAGES=("web3" "flashbots" "requests" "websocket-client" "cryptography")
    
    for package in "${CRITICAL_PACKAGES[@]}"; do
        if python -c "import $package" &> /dev/null; then
            log_success "✓ $package installed successfully"
        else
            log_error "✗ $package installation failed"
            exit 1
        fi
    done
    
    log_success "All dependencies installed successfully"
}

# Function to configure environment
configure_environment() {
    log_section "⚙️  CONFIGURING ENVIRONMENT"
    
    # Create sample configuration if it doesn't exist
    SAMPLE_CONFIG="$CONFIG_DIR/sample_config.json"
    if [[ ! -f "$SAMPLE_CONFIG" ]]; then
        log_info "Creating sample configuration..."
        source "$VENV_DIR/bin/activate"
        cd "$MEMPOOL_DIR"
        python -c "from config import ConfigManager; ConfigManager().create_sample_config()"
        log_success "Sample configuration created at: $SAMPLE_CONFIG"
    fi
    
    # Create environment template if it doesn't exist
    ENV_TEMPLATE="$CONFIG_DIR/.env.template"
    if [[ ! -f "$ENV_TEMPLATE" ]]; then
        log_info "Creating environment variable template..."
        cat > "$ENV_TEMPLATE" << 'EOF'
# Private Mempool Configuration Template
# Copy to .env and fill in your actual values

# Flashbots Configuration
FLASHBOTS_PRIVATE_KEY=0x1111111111111111111111111111111111111111111111111111111111111111
FLASHBOTS_SIGNATURE_KEY=0x2222222222222222222222222222222222222222222222222222222222222222
FLASHBOTS_RELAY_URL=https://relay.flashbots.net

# BloXroute Configuration
BLOXROUTE_AUTH_HEADER=Bearer YOUR_BLOXROUTE_TOKEN
BLOXROUTE_CLOUD_API_KEY=YOUR_CLOUD_API_KEY

# BuilderNet Configuration (Early Access)
BUILDERNET_PRIVATE_KEY=0x3333333333333333333333333333333333333333333333333333333333333333
BUILDERNET_BUILDER_ID=your_builder_id
BUILDERNET_EARLY_ACCESS_TOKEN=YOUR_EARLY_ACCESS_TOKEN

# Validator Configuration
VALIDATORS_PRIVATE_KEY=0x4444444444444444444444444444444444444444444444444444444444444444

# Example Validator Partnership (JSON format)
VALIDATORS_PARTNERSHIPS_JSON='[
  {
    "validator_id": "coinbase_validator_1",
    "stake_percentage": 8.5,
    "api_endpoint": "https://api.coinbase-validator.com",
    "ws_endpoint": "wss://stream.coinbase-validator.com/priority",
    "revenue_share": 12.0,
    "priority_slots": 10
  }
]'

# MEV Protection Services
MEV_PROTECTION_PRIVATE_KEY=0x5555555555555555555555555555555555555555555555555555555555555555

# Example Protection Clients (JSON format)
MEV_PROTECTION_CLIENTS_JSON='[
  {
    "client_id": "hedge_fund_alpha",
    "organization": "Alpha Capital Management",
    "contact_email": "mev@alphacapital.com",
    "services_requested": ["sandwich_protection", "custom_strategy_execution"],
    "tier": "enterprise",
    "monthly_volume": 1000.0
  }
]'

# Logging Configuration
LOG_LEVEL=INFO
LOG_FILE=/data/blockchain/nodes/logs/private_mempool.log
EOF
        log_success "Environment template created at: $ENV_TEMPLATE"
    fi
    
    # Check for .env file
    ENV_FILE="$CONFIG_DIR/.env"
    if [[ ! -f "$ENV_FILE" ]]; then
        log_warning "No .env file found. Please create one based on the template:"
        log_warning "cp $ENV_TEMPLATE $ENV_FILE"
        log_warning "Then edit $ENV_FILE with your actual configuration values"
    fi
    
    log_success "Environment configuration completed"
}

# Function to create systemd service
create_systemd_service() {
    log_section "🔧 CREATING SYSTEMD SERVICE"
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_warning "Not running as root. Skipping systemd service creation."
        log_info "To create systemd service manually, run with sudo:"
        log_info "sudo $0 --systemd-only"
        return
    fi
    
    SERVICE_FILE="/etc/systemd/system/private-mempool.service"
    
    log_info "Creating systemd service file..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Private Mempool MEV Infrastructure
Documentation=https://github.com/your-org/mev-infrastructure
After=network.target
Wants=network.target

[Service]
Type=simple
User=blockchain
Group=blockchain
WorkingDirectory=$MEMPOOL_DIR
Environment=PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$VENV_DIR/bin/python start_private_mempool.py
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=30
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=private-mempool

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$PROJECT_ROOT
MemoryMax=8G
TasksMax=1000

# Environment
EnvironmentFile=-$CONFIG_DIR/.env

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable private-mempool.service
    
    log_success "Systemd service created and enabled"
    log_info "Service commands:"
    log_info "  Start:   sudo systemctl start private-mempool"
    log_info "  Stop:    sudo systemctl stop private-mempool"
    log_info "  Status:  sudo systemctl status private-mempool"
    log_info "  Logs:    sudo journalctl -u private-mempool -f"
}

# Function to setup log rotation
setup_log_rotation() {
    log_section "📝 SETTING UP LOG ROTATION"
    
    if [[ $EUID -ne 0 ]]; then
        log_warning "Not running as root. Skipping log rotation setup."
        return
    fi
    
    LOGROTATE_FILE="/etc/logrotate.d/private-mempool"
    
    cat > "$LOGROTATE_FILE" << EOF
$LOGS_DIR/private_mempool.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    copytruncate
    notifempty
    create 644 blockchain blockchain
    postrotate
        /bin/systemctl reload private-mempool.service > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log_success "Log rotation configured"
}

# Function to run tests
run_tests() {
    log_section "🧪 RUNNING TESTS"
    
    source "$VENV_DIR/bin/activate"
    cd "$MEMPOOL_DIR"
    
    # Basic import tests
    log_info "Testing Python imports..."
    
    MODULES=("config" "flashbots_client" "bloxroute_client" "buildernet_client" "validator_client" "mev_protection_client" "unified_manager")
    
    for module in "${MODULES[@]}"; do
        if python -c "import $module" &> /dev/null; then
            log_success "✓ $module imports successfully"
        else
            log_error "✗ $module import failed"
            exit 1
        fi
    done
    
    # Configuration test
    log_info "Testing configuration loading..."
    if python -c "
from config import ConfigManager
try:
    manager = ConfigManager()
    manager.create_sample_config()
    print('Configuration test passed')
except Exception as e:
    print(f'Configuration test failed: {e}')
    exit(1)
" &> /dev/null; then
        log_success "✓ Configuration loading works"
    else
        log_error "✗ Configuration loading failed"
        exit 1
    fi
    
    log_success "All tests passed"
}

# Function to display deployment summary
show_deployment_summary() {
    log_section "🎉 DEPLOYMENT SUMMARY"
    
    echo
    echo -e "${GREEN}✅ Private Mempool Infrastructure Deployed Successfully!${NC}"
    echo
    echo -e "${CYAN}📁 Installation Directory:${NC} $MEMPOOL_DIR"
    echo -e "${CYAN}🐍 Python Virtual Environment:${NC} $VENV_DIR"
    echo -e "${CYAN}⚙️  Configuration Directory:${NC} $CONFIG_DIR"
    echo -e "${CYAN}📝 Logs Directory:${NC} $LOGS_DIR"
    echo
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo -e "  1. Configure your environment variables:"
    echo -e "     ${BLUE}cp $CONFIG_DIR/.env.template $CONFIG_DIR/.env${NC}"
    echo -e "     ${BLUE}nano $CONFIG_DIR/.env${NC}"
    echo
    echo -e "  2. Start the service:"
    echo -e "     ${BLUE}cd $MEMPOOL_DIR${NC}"
    echo -e "     ${BLUE}source venv/bin/activate${NC}"
    echo -e "     ${BLUE}python start_private_mempool.py${NC}"
    echo
    echo -e "  3. Or use systemd (if configured):"
    echo -e "     ${BLUE}sudo systemctl start private-mempool${NC}"
    echo -e "     ${BLUE}sudo systemctl status private-mempool${NC}"
    echo
    echo -e "${YELLOW}📚 Configuration Files:${NC}"
    echo -e "  • Sample Config: $CONFIG_DIR/sample_config.json"
    echo -e "  • Environment Template: $CONFIG_DIR/.env.template"
    echo -e "  • Requirements: $MEMPOOL_DIR/requirements.txt"
    echo
    echo -e "${YELLOW}🚀 Service Components:${NC}"
    echo -e "  • Flashbots Private Client"
    echo -e "  • BloXroute MEV Integration"
    echo -e "  • BuilderNet Early Access"
    echo -e "  • Validator Relationships"
    echo -e "  • MEV Protection Services"
    echo -e "  • Unified Manager"
    echo
    echo -e "${GREEN}Ready for world-class MEV operations! 🌟${NC}"
    echo
}

# Function to show help
show_help() {
    echo "Private Mempool Infrastructure Deployment Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help               Show this help message"
    echo "  --systemd-only       Only create systemd service (requires root)"
    echo "  --no-systemd         Skip systemd service creation"
    echo "  --no-tests           Skip running tests"
    echo "  --force              Force reinstallation (removes existing venv)"
    echo
    echo "Environment Variables:"
    echo "  PYTHON_CMD           Python command to use (default: auto-detect)"
    echo "  SKIP_REQUIREMENTS    Skip installing requirements (default: false)"
    echo
}

# Main deployment function
main() {
    local skip_systemd=false
    local skip_tests=false
    local force_install=false
    local systemd_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --systemd-only)
                systemd_only=true
                shift
                ;;
            --no-systemd)
                skip_systemd=true
                shift
                ;;
            --no-tests)
                skip_tests=true
                shift
                ;;
            --force)
                force_install=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Header
    echo
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║          PRIVATE MEMPOOL INFRASTRUCTURE             ║${NC}"
    echo -e "${PURPLE}║             DEPLOYMENT SCRIPT v1.0                  ║${NC}"
    echo -e "${PURPLE}║                                                      ║${NC}"
    echo -e "${PURPLE}║    World-Class MEV Infrastructure Deployment        ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Handle systemd-only mode
    if [[ "$systemd_only" == true ]]; then
        create_systemd_service
        setup_log_rotation
        exit 0
    fi
    
    # Start deployment process
    log_info "Starting deployment process..."
    log_info "Target directory: $MEMPOOL_DIR"
    
    # Run deployment steps
    check_system_requirements
    create_directories
    
    if [[ "$force_install" == true ]] || [[ ! -d "$VENV_DIR" ]]; then
        setup_virtual_environment
        install_dependencies
    else
        log_info "Virtual environment already exists. Use --force to reinstall."
        source "$VENV_DIR/bin/activate"
    fi
    
    configure_environment
    
    if [[ "$skip_tests" != true ]]; then
        run_tests
    fi
    
    if [[ "$skip_systemd" != true ]]; then
        create_systemd_service
        setup_log_rotation
    fi
    
    show_deployment_summary
}

# Run main function
main "$@"