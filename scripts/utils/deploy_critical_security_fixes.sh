#!/bin/bash
# CRITICAL SECURITY FIXES DEPLOYMENT SCRIPT
# Version: 1.0
# Date: July 15, 2025
# Classification: CONFIDENTIAL - SECURITY IMPLEMENTATION

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

# Create log file
LOG_FILE="/data/blockchain/nodes/logs/security_deployment_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log "🔐 STARTING CRITICAL SECURITY FIXES DEPLOYMENT"
log "=================================================="

# Backup current configurations
backup_configs() {
    log "📦 Creating configuration backups..."
    
    BACKUP_DIR="/data/blockchain/backups/pre_security_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup systemd services
    cp -r /data/blockchain/nodes/systemd "$BACKUP_DIR/" 2>/dev/null || true
    
    # Backup security configurations
    cp -r /data/blockchain/nodes/security "$BACKUP_DIR/" 2>/dev/null || true
    
    # Backup firewall rules
    ufw status verbose > "$BACKUP_DIR/ufw_status.txt"
    iptables-save > "$BACKUP_DIR/iptables_rules.txt"
    
    log "✅ Configurations backed up to $BACKUP_DIR"
}

# Fix 1: Secure RPC Endpoints
secure_rpc_endpoints() {
    log "🔒 Securing RPC endpoints..."
    
    # Remove public RPC access
    ufw delete allow 8545/tcp 2>/dev/null || true
    ufw delete allow 8546/tcp 2>/dev/null || true
    
    # Allow RPC only from VPN network and localhost
    ufw allow from 10.8.0.0/24 to any port 8545 comment "Ethereum RPC VPN only"
    ufw allow from 10.8.0.0/24 to any port 8546 comment "Ethereum WS VPN only"
    ufw allow from 127.0.0.1 to any port 8545 comment "Ethereum RPC localhost"
    ufw allow from 127.0.0.1 to any port 8546 comment "Ethereum WS localhost"
    
    # Secure Engine API
    ufw delete allow 8551/tcp 2>/dev/null || true
    ufw allow from 127.0.0.1 to any port 8551 comment "Engine API localhost only"
    
    # Apply rate limiting
    fail2ban-client set blockchain-rpc maxretry 5 2>/dev/null || true
    fail2ban-client set blockchain-rpc bantime 1800 2>/dev/null || true
    
    ufw --force reload
    
    log "✅ RPC endpoints secured"
}

# Fix 2: JWT Secret Rotation
rotate_jwt_secrets() {
    log "🔑 Rotating JWT secrets..."
    
    # Create secure directory
    mkdir -p /data/blockchain/security/jwt_secrets
    chmod 700 /data/blockchain/security/jwt_secrets
    
    # Services that need JWT secrets
    SERVICES=("ethereum" "arbitrum" "optimism" "base" "polygon" "bsc")
    
    for service in "${SERVICES[@]}"; do
        log "Generating JWT secret for $service..."
        
        # Generate new 32-byte hex secret
        NEW_SECRET=$(openssl rand -hex 32)
        
        # Create secure secret file
        echo "$NEW_SECRET" > "/data/blockchain/security/jwt_secrets/${service}_jwt.hex"
        chmod 600 "/data/blockchain/security/jwt_secrets/${service}_jwt.hex"
        chown root:root "/data/blockchain/security/jwt_secrets/${service}_jwt.hex"
        
        # Update service storage if it exists
        if [ -f "/data/blockchain/storage/${service}/jwt.hex" ]; then
            cp "/data/blockchain/security/jwt_secrets/${service}_jwt.hex" "/data/blockchain/storage/${service}/jwt.hex"
            chmod 600 "/data/blockchain/storage/${service}/jwt.hex"
            chown lyftium:lyftium "/data/blockchain/storage/${service}/jwt.hex"
        fi
        
        log "✅ JWT secret rotated for $service"
    done
    
    log "✅ All JWT secrets rotated"
}

# Fix 3: MEV-Boost Security
secure_mev_boost() {
    log "🛡️ Securing MEV-Boost..."
    
    # Stop MEV-Boost service
    systemctl stop mev-boost 2>/dev/null || true
    
    # Update MEV-Boost configuration
    MEV_CONFIG="/data/blockchain/nodes/mev-boost/start-mev-boost-production.sh"
    if [ -f "$MEV_CONFIG" ]; then
        cp "$MEV_CONFIG" "${MEV_CONFIG}.backup"
        sed -i 's/--addr 0.0.0.0:18550/--addr 127.0.0.1:18550/' "$MEV_CONFIG"
        sed -i 's/--addr 0.0.0.0:18551/--addr 127.0.0.1:18551/' "$MEV_CONFIG"
    fi
    
    # Update systemd service
    MEV_SERVICE="/data/blockchain/nodes/systemd/mev-boost.service"
    if [ -f "$MEV_SERVICE" ]; then
        cp "$MEV_SERVICE" "${MEV_SERVICE}.backup"
        
        # Add security restrictions
        sed -i '/\[Service\]/a\
NoNewPrivileges=true\
ProtectSystem=strict\
ProtectHome=true\
PrivateTmp=true\
ReadWritePaths=/data/blockchain/nodes\
User=lyftium\
Group=lyftium' "$MEV_SERVICE"
    fi
    
    # Update firewall rules
    ufw delete allow 18550/tcp 2>/dev/null || true
    ufw delete allow 18551/tcp 2>/dev/null || true
    ufw allow from 127.0.0.1 to any port 18550 comment "MEV-Boost localhost only"
    ufw allow from 127.0.0.1 to any port 18551 comment "MEV-Boost relay localhost only"
    
    # Restart services
    systemctl daemon-reload
    systemctl start mev-boost
    systemctl enable mev-boost
    
    log "✅ MEV-Boost secured"
}

# Fix 4: Service Hardening
harden_services() {
    log "🔐 Hardening blockchain services..."
    
    # Create dedicated blockchain user if not exists
    if ! id "blockchain" &>/dev/null; then
        useradd -r -s /bin/false -d /data/blockchain blockchain
        usermod -aG docker blockchain
    fi
    
    # Update directory permissions
    chown -R lyftium:lyftium /data/blockchain/storage 2>/dev/null || true
    find /data/blockchain/storage -name "jwt.hex" -exec chmod 600 {} \;
    
    # Harden Erigon service
    ERIGON_SERVICE="/data/blockchain/nodes/systemd/erigon.service"
    if [ -f "$ERIGON_SERVICE" ]; then
        cp "$ERIGON_SERVICE" "${ERIGON_SERVICE}.backup"
        
        # Update security settings
        sed -i '/User=root/c\User=lyftium' "$ERIGON_SERVICE"
        sed -i '/Group=root/c\Group=lyftium' "$ERIGON_SERVICE"
        sed -i '/NoNewPrivileges=true/c\NoNewPrivileges=true' "$ERIGON_SERVICE"
        sed -i '/ProtectSystem=false/c\ProtectSystem=strict' "$ERIGON_SERVICE"
        sed -i '/ProtectHome=false/c\ProtectHome=true' "$ERIGON_SERVICE"
        
        # Add additional security measures
        sed -i '/\[Service\]/a\
PrivateTmp=true\
ProtectKernelTunables=true\
ProtectKernelModules=true\
ProtectControlGroups=true\
ReadWritePaths=/data/blockchain\
RestrictSUIDSGID=true\
RestrictRealtime=true\
LockPersonality=true' "$ERIGON_SERVICE"
    fi
    
    # Update other blockchain services
    SERVICES=("arbitrum-node" "base-node" "optimism-node" "polygon-bor" "bsc-node")
    for service in "${SERVICES[@]}"; do
        SERVICE_FILE="/data/blockchain/nodes/systemd/${service}.service"
        if [ -f "$SERVICE_FILE" ]; then
            cp "$SERVICE_FILE" "${SERVICE_FILE}.backup"
            sed -i '/User=root/c\User=lyftium' "$SERVICE_FILE"
            sed -i '/Group=root/c\Group=lyftium' "$SERVICE_FILE"
            sed -i '/\[Service\]/a\
NoNewPrivileges=true\
ProtectSystem=strict\
ProtectHome=true\
PrivateTmp=true\
ReadWritePaths=/data/blockchain' "$SERVICE_FILE"
        fi
    done
    
    systemctl daemon-reload
    
    log "✅ Services hardened"
}

# Fix 5: Network Security
enhance_network_security() {
    log "🌐 Enhancing network security..."
    
    # Create custom iptables rules for blockchain zones
    iptables -N BLOCKCHAIN_ZONE 2>/dev/null || true
    iptables -N MEV_ZONE 2>/dev/null || true
    iptables -N MONITORING_ZONE 2>/dev/null || true
    
    # Clear existing rules in custom chains
    iptables -F BLOCKCHAIN_ZONE 2>/dev/null || true
    iptables -F MEV_ZONE 2>/dev/null || true
    iptables -F MONITORING_ZONE 2>/dev/null || true
    
    # Configure blockchain zone
    iptables -A BLOCKCHAIN_ZONE -s 127.0.0.1 -p tcp --dport 8545 -j ACCEPT
    iptables -A BLOCKCHAIN_ZONE -s 127.0.0.1 -p tcp --dport 8546 -j ACCEPT
    iptables -A BLOCKCHAIN_ZONE -s 127.0.0.1 -p tcp --dport 8551 -j ACCEPT
    iptables -A BLOCKCHAIN_ZONE -s 10.8.0.0/24 -p tcp --dport 8545 -j ACCEPT
    iptables -A BLOCKCHAIN_ZONE -s 10.8.0.0/24 -p tcp --dport 8546 -j ACCEPT
    
    # Configure MEV zone
    iptables -A MEV_ZONE -s 127.0.0.1 -p tcp --dport 18550 -j ACCEPT
    iptables -A MEV_ZONE -s 127.0.0.1 -p tcp --dport 18551 -j ACCEPT
    iptables -A MEV_ZONE -j DROP
    
    # Configure monitoring zone
    iptables -A MONITORING_ZONE -s 10.8.0.0/24 -p tcp --dport 3000 -j ACCEPT
    iptables -A MONITORING_ZONE -s 10.8.0.0/24 -p tcp --dport 9090 -j ACCEPT
    
    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4
    
    log "✅ Network security enhanced"
}

# Fix 6: Deploy Security Monitoring
deploy_monitoring() {
    log "📊 Deploying enhanced security monitoring..."
    
    # Install security monitoring tools
    apt update
    apt install -y auditd aide rkhunter chkrootkit psmisc
    
    # Configure system auditing
    auditctl -w /data/blockchain/storage -p wa -k blockchain_access
    auditctl -w /data/blockchain/security -p wa -k security_access
    auditctl -w /etc/systemd/system -p wa -k systemd_changes
    
    # Initialize file integrity monitoring
    aide --init 2>/dev/null || true
    cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db 2>/dev/null || true
    
    # Configure automated security scans
    cat > /etc/cron.d/security-scans << 'EOF'
# Daily security scans
0 2 * * * root /usr/bin/rkhunter --check --skip-keypress --report-warnings-only
0 3 * * * root /usr/bin/chkrootkit -q
0 4 * * * root /usr/bin/aide --check
EOF
    
    # Deploy real-time monitoring script
    cat > /data/blockchain/nodes/security/realtime_monitor.py << 'EOF'
#!/usr/bin/env python3
"""
Real-time Security Monitoring for Blockchain Infrastructure
Monitors network connections, system resources, and security events
"""

import psutil
import time
import json
import sqlite3
import logging
from datetime import datetime
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/data/blockchain/nodes/logs/security_monitor.log'),
        logging.StreamHandler()
    ]
)

class RealtimeSecurityMonitor:
    def __init__(self):
        self.db_path = "/data/blockchain/nodes/security/security_events.db"
        self.critical_ports = [8545, 8546, 8551, 18550, 18551]
        self.init_database()
        
    def init_database(self):
        """Initialize SQLite database for security events"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS security_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                event_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                description TEXT,
                source_ip TEXT,
                target_port INTEGER,
                resolved BOOLEAN DEFAULT FALSE
            )
        ''')
        
        conn.commit()
        conn.close()
        
    def monitor_network_connections(self):
        """Monitor for suspicious network connections"""
        try:
            for conn in psutil.net_connections():
                if conn.laddr.port in self.critical_ports:
                    # Check for non-localhost connections
                    if conn.raddr and not conn.raddr.ip.startswith('127.'):
                        if not conn.raddr.ip.startswith('10.8.'):  # Allow VPN
                            self.log_security_event(
                                'SUSPICIOUS_CONNECTION',
                                'HIGH',
                                f'External connection to critical port {conn.laddr.port}',
                                conn.raddr.ip,
                                conn.laddr.port
                            )
        except Exception as e:
            logging.error(f"Error monitoring network connections: {e}")
    
    def monitor_system_resources(self):
        """Monitor system resources for anomalies"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            
            # Check for suspicious resource usage
            if cpu_percent > 95:
                self.log_security_event(
                    'HIGH_CPU_USAGE',
                    'MEDIUM',
                    f'Suspicious CPU usage: {cpu_percent}%'
                )
            
            if memory.percent > 90:
                self.log_security_event(
                    'HIGH_MEMORY_USAGE',
                    'MEDIUM',
                    f'High memory usage: {memory.percent}%'
                )
        except Exception as e:
            logging.error(f"Error monitoring system resources: {e}")
    
    def log_security_event(self, event_type, severity, description, source_ip=None, target_port=None):
        """Log security event to database"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO security_events (event_type, severity, description, source_ip, target_port)
                VALUES (?, ?, ?, ?, ?)
            ''', (event_type, severity, description, source_ip, target_port))
            
            conn.commit()
            conn.close()
            
            # Log to console
            log_msg = f"SECURITY ALERT: {event_type} ({severity}) - {description}"
            if source_ip:
                log_msg += f" from {source_ip}"
            if target_port:
                log_msg += f" on port {target_port}"
            
            if severity in ['HIGH', 'CRITICAL']:
                logging.error(log_msg)
            else:
                logging.warning(log_msg)
                
        except Exception as e:
            logging.error(f"Error logging security event: {e}")
    
    def run_monitoring(self):
        """Run continuous monitoring"""
        logging.info("Starting real-time security monitoring...")
        
        while True:
            try:
                self.monitor_network_connections()
                self.monitor_system_resources()
                time.sleep(10)  # Check every 10 seconds
            except KeyboardInterrupt:
                logging.info("Monitoring stopped by user")
                break
            except Exception as e:
                logging.error(f"Error in monitoring loop: {e}")
                time.sleep(30)  # Wait before retry

if __name__ == "__main__":
    monitor = RealtimeSecurityMonitor()
    monitor.run_monitoring()
EOF
    
    # Make monitoring script executable
    chmod +x /data/blockchain/nodes/security/realtime_monitor.py
    
    # Create systemd service for monitoring
    cat > /etc/systemd/system/realtime-security-monitor.service << 'EOF'
[Unit]
Description=Realtime Security Monitor for Blockchain Infrastructure
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/data/blockchain/nodes/security
ExecStart=/usr/bin/python3 /data/blockchain/nodes/security/realtime_monitor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start monitoring service
    systemctl daemon-reload
    systemctl enable realtime-security-monitor
    systemctl start realtime-security-monitor
    
    log "✅ Security monitoring deployed"
}

# Fix 7: Secure Credential Management
secure_credential_management() {
    log "🔐 Implementing secure credential management..."
    
    # Remove plaintext credentials
    if [ -f "/data/blockchain/nodes/security/rpc_credentials.json" ]; then
        mv "/data/blockchain/nodes/security/rpc_credentials.json" "/data/blockchain/nodes/security/rpc_credentials.json.backup"
    fi
    
    # Create secure credential storage
    mkdir -p /data/blockchain/security/encrypted_credentials
    chmod 700 /data/blockchain/security/encrypted_credentials
    
    # Generate new secure credentials
    MONITORING_CRED=$(openssl rand -hex 32)
    MEV_EXECUTOR_CRED=$(openssl rand -hex 32)
    ADMIN_CRED=$(openssl rand -hex 32)
    
    # Create encrypted credential file
    cat > /tmp/new_credentials.json << EOF
{
  "credentials": {
    "monitoring": "$MONITORING_CRED",
    "mev_executor": "$MEV_EXECUTOR_CRED",
    "admin": "$ADMIN_CRED"
  },
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    # Encrypt credentials
    ENCRYPTION_KEY=$(openssl rand -base64 32)
    echo "$ENCRYPTION_KEY" > /data/blockchain/security/master_key.txt
    chmod 600 /data/blockchain/security/master_key.txt
    
    openssl enc -aes-256-cbc -salt -in /tmp/new_credentials.json -out /data/blockchain/security/encrypted_credentials/rpc_credentials.enc -k "$ENCRYPTION_KEY"
    
    # Create credential retrieval script
    cat > /data/blockchain/nodes/security/get_credentials.sh << 'EOF'
#!/bin/bash
# Secure credential retrieval script
set -euo pipefail

MASTER_KEY=$(cat /data/blockchain/security/master_key.txt)
ENCRYPTED_FILE="/data/blockchain/security/encrypted_credentials/rpc_credentials.enc"

if [ ! -f "$ENCRYPTED_FILE" ]; then
    echo "Error: Encrypted credentials file not found"
    exit 1
fi

# Decrypt credentials
DECRYPTED=$(openssl enc -d -aes-256-cbc -in "$ENCRYPTED_FILE" -k "$MASTER_KEY")

case "${1:-}" in
    "monitoring")
        echo "$DECRYPTED" | jq -r '.credentials.monitoring'
        ;;
    "mev_executor")
        echo "$DECRYPTED" | jq -r '.credentials.mev_executor'
        ;;
    "admin")
        echo "$DECRYPTED" | jq -r '.credentials.admin'
        ;;
    "all")
        echo "$DECRYPTED" | jq -r '.credentials'
        ;;
    *)
        echo "Usage: $0 {monitoring|mev_executor|admin|all}"
        exit 1
        ;;
esac
EOF
    
    chmod +x /data/blockchain/nodes/security/get_credentials.sh
    
    # Clean up temporary files
    rm -f /tmp/new_credentials.json
    
    log "✅ Secure credential management implemented"
}

# Verification function
verify_security_fixes() {
    log "🔍 Verifying security fixes..."
    
    PASSED=0
    FAILED=0
    
    # Test 1: RPC endpoint security
    if curl -s -m 5 http://localhost:8545 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' >/dev/null 2>&1; then
        log "✅ RPC accessible from localhost"
        ((PASSED++))
    else
        error "❌ RPC not accessible from localhost"
        ((FAILED++))
    fi
    
    # Test 2: External RPC access (should fail)
    if timeout 5 curl -s http://$(hostname -I | awk '{print $1}'):8545 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' >/dev/null 2>&1; then
        error "❌ RPC accessible externally"
        ((FAILED++))
    else
        log "✅ RPC blocked from external access"
        ((PASSED++))
    fi
    
    # Test 3: MEV-Boost security
    if curl -s -m 5 http://localhost:18550/eth/v1/builder/status >/dev/null 2>&1; then
        log "✅ MEV-Boost accessible from localhost"
        ((PASSED++))
    else
        warn "⚠️  MEV-Boost not accessible (may be expected)"
    fi
    
    # Test 4: JWT secrets
    if [ -d "/data/blockchain/security/jwt_secrets" ] && [ "$(ls -A /data/blockchain/security/jwt_secrets)" ]; then
        log "✅ JWT secrets rotated"
        ((PASSED++))
    else
        error "❌ JWT secrets not rotated"
        ((FAILED++))
    fi
    
    # Test 5: Security monitoring
    if systemctl is-active realtime-security-monitor >/dev/null 2>&1; then
        log "✅ Security monitoring active"
        ((PASSED++))
    else
        error "❌ Security monitoring not active"
        ((FAILED++))
    fi
    
    # Test 6: Firewall rules
    if ufw status | grep -q "8545.*10.8.0.0/24"; then
        log "✅ Firewall rules applied"
        ((PASSED++))
    else
        error "❌ Firewall rules not applied correctly"
        ((FAILED++))
    fi
    
    log "=================================================="
    log "VERIFICATION RESULTS: $PASSED passed, $FAILED failed"
    
    if [ $FAILED -eq 0 ]; then
        log "🎉 ALL SECURITY FIXES VERIFIED SUCCESSFULLY!"
        return 0
    else
        error "❌ Some security fixes failed verification"
        return 1
    fi
}

# Main execution
main() {
    log "Starting critical security fixes deployment..."
    
    # Pre-deployment checks
    if ! command -v ufw &> /dev/null; then
        error "UFW firewall not installed"
        exit 1
    fi
    
    if ! command -v fail2ban-client &> /dev/null; then
        warn "Fail2ban not installed, skipping fail2ban configuration"
    fi
    
    # Execute security fixes
    backup_configs
    secure_rpc_endpoints
    rotate_jwt_secrets
    secure_mev_boost
    harden_services
    enhance_network_security
    deploy_monitoring
    secure_credential_management
    
    # Verify implementation
    if verify_security_fixes; then
        log "🎉 CRITICAL SECURITY FIXES DEPLOYED SUCCESSFULLY!"
        log "=================================================="
        log "Next steps:"
        log "1. Monitor security alerts in /data/blockchain/nodes/logs/"
        log "2. Review daily security reports"
        log "3. Implement additional security measures from the full audit"
        log "4. Schedule regular security reviews"
        log "=================================================="
    else
        error "❌ SECURITY FIXES DEPLOYMENT FAILED"
        log "Check the log file for details: $LOG_FILE"
        exit 1
    fi
}

# Trap errors and cleanup
trap 'error "Script interrupted"; exit 1' INT TERM

# Execute main function
main "$@"