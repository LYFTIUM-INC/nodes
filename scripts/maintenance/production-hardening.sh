#!/bin/bash
# Production Hardening Script for Blockchain MEV Infrastructure
# This script implements all critical security and operational fixes

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Blockchain MEV Infrastructure Production Hardening ===${NC}"
echo -e "Starting at: $(date)\n"

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

# Function to create backup
backup_config() {
    echo -e "${YELLOW}Creating configuration backups...${NC}"
    BACKUP_DIR="/data/blockchain/nodes/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup critical configurations
    cp -r /etc/nginx/sites-available "$BACKUP_DIR/" 2>/dev/null || true
    cp -r /data/blockchain/nodes/config "$BACKUP_DIR/" 2>/dev/null || true
    cp -r /data/blockchain/nodes/mev-infra/config "$BACKUP_DIR/" 2>/dev/null || true
    
    echo -e "${GREEN}✓ Backups created in $BACKUP_DIR${NC}"
}

# 1. Fix Systemd Service Configurations
fix_systemd_services() {
    echo -e "\n${BLUE}1. Fixing Systemd Service Configurations${NC}"
    
    # Create production-ready service override directory
    mkdir -p /etc/systemd/system/{ethereum,optimism,base,polygon,arbitrum}.service.d
    
    # Ethereum service hardening
    cat > /etc/systemd/system/ethereum.service.d/production.conf << 'EOF'
[Service]
# Resource Limits
LimitNOFILE=1000000
LimitNPROC=512000
LimitCORE=infinity

# Restart Policy
Restart=always
RestartSec=10
StartLimitInterval=600
StartLimitBurst=5

# Security Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/data/blockchain/nodes/ethereum

# Environment
Environment="GOGC=100"
Environment="GOMEMLIMIT=30GiB"
EOF

    # Apply similar configuration to all blockchain services
    for service in optimism base polygon arbitrum; do
        cp /etc/systemd/system/ethereum.service.d/production.conf \
           /etc/systemd/system/${service}.service.d/production.conf
        sed -i "s/ethereum/${service}/g" /etc/systemd/system/${service}.service.d/production.conf
    done
    
    # MEV services hardening
    for service in mev-boost mev-infra mev-artemis; do
        mkdir -p /etc/systemd/system/${service}.service.d
        cat > /etc/systemd/system/${service}.service.d/production.conf << EOF
[Service]
Restart=always
RestartSec=5
StartLimitInterval=300
StartLimitBurst=3
LimitNOFILE=65536
Environment="NODE_ENV=production"
EOF
    done
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ Systemd services hardened${NC}"
}

# 2. Setup Firewall Rules
setup_firewall() {
    echo -e "\n${BLUE}2. Setting up Firewall Rules${NC}"
    
    # Install ufw if not present
    if ! command -v ufw &> /dev/null; then
        apt-get update && apt-get install -y ufw
    fi
    
    # Reset to defaults
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (adjust port as needed)
    ufw allow 22/tcp comment 'SSH'
    
    # Allow HTTPS for RPC endpoints
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 8443/tcp comment 'HTTPS Alternative'
    
    # Allow blockchain P2P ports (only from specific IPs in production)
    ufw allow 30303/tcp comment 'Ethereum P2P'
    ufw allow 9000/tcp comment 'Lighthouse P2P'
    
    # Rate limiting for RPC
    ufw limit 443/tcp
    ufw limit 8443/tcp
    
    # Enable firewall
    ufw --force enable
    
    echo -e "${GREEN}✓ Firewall configured${NC}"
}

# 3. Setup Fail2ban
setup_fail2ban() {
    echo -e "\n${BLUE}3. Setting up Fail2ban${NC}"
    
    # Install fail2ban
    apt-get update && apt-get install -y fail2ban
    
    # Create jail for nginx
    cat > /etc/fail2ban/jail.d/nginx-ratelimit.conf << 'EOF'
[nginx-ratelimit]
enabled = true
filter = nginx-ratelimit
logpath = /var/log/nginx/access.log
maxretry = 100
findtime = 60
bantime = 600
action = iptables-multiport[name=nginx-ratelimit, port="80,443,8443"]

[nginx-4xx]
enabled = true
filter = nginx-4xx
logpath = /var/log/nginx/access.log
maxretry = 50
findtime = 300
bantime = 3600
EOF

    # Create filters
    cat > /etc/fail2ban/filter.d/nginx-ratelimit.conf << 'EOF'
[Definition]
failregex = ^<HOST>.*"(GET|POST).*HTTP.*" 429
ignoreregex =
EOF

    cat > /etc/fail2ban/filter.d/nginx-4xx.conf << 'EOF'
[Definition]
failregex = ^<HOST>.*"(GET|POST).*HTTP.*" 4\d\d
ignoreregex = .*(robots\.txt|favicon\.ico).*
EOF

    systemctl restart fail2ban
    echo -e "${GREEN}✓ Fail2ban configured${NC}"
}

# 4. Setup Monitoring and Alerting
setup_monitoring() {
    echo -e "\n${BLUE}4. Setting up Enhanced Monitoring${NC}"
    
    # Install required packages
    apt-get update && apt-get install -y prometheus-node-exporter
    
    # Create alerting rules
    mkdir -p /etc/prometheus/rules
    cat > /etc/prometheus/rules/blockchain-alerts.yml << 'EOF'
groups:
  - name: blockchain_alerts
    interval: 30s
    rules:
      - alert: NodeDown
        expr: up{job="blockchain"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Blockchain node {{ $labels.instance }} is down"
          
      - alert: HighCPUUsage
        expr: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.lxcfs"} / node_filesystem_size_bytes) * 100 < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
EOF

    # Setup Grafana dashboards
    mkdir -p /var/lib/grafana/dashboards
    
    echo -e "${GREEN}✓ Monitoring enhanced${NC}"
}

# 5. Setup Automated Backups
setup_backups() {
    echo -e "\n${BLUE}5. Setting up Automated Backups${NC}"
    
    # Create backup script
    cat > /data/blockchain/nodes/scripts/backup-blockchain.sh << 'EOF'
#!/bin/bash
# Automated Backup Script for Blockchain Infrastructure

BACKUP_BASE="/data/blockchain/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Backup configurations
echo "Backing up configurations..."
rsync -av --exclude='*.log' --exclude='*.tmp' \
    /data/blockchain/nodes/config/ \
    "${BACKUP_DIR}/config/"

rsync -av --exclude='*.log' \
    /data/blockchain/nodes/mev-infra/config/ \
    "${BACKUP_DIR}/mev-infra-config/"

# Backup critical data (excluding full blockchain data)
echo "Backing up critical data..."
for service in ethereum optimism base polygon arbitrum; do
    if [ -d "/data/blockchain/nodes/${service}/keystore" ]; then
        rsync -av "/data/blockchain/nodes/${service}/keystore/" \
            "${BACKUP_DIR}/${service}-keystore/"
    fi
done

# Backup nginx configuration
rsync -av /etc/nginx/sites-available/ "${BACKUP_DIR}/nginx/"

# Create backup manifest
cat > "${BACKUP_DIR}/manifest.txt" << MANIFEST
Backup Timestamp: ${TIMESTAMP}
Backup Host: $(hostname)
Backup User: $(whoami)
Services Status:
$(systemctl status ethereum optimism base polygon arbitrum mev-boost mev-infra nginx | grep -E "Active:|Main PID:")
MANIFEST

# Compress backup
cd "${BACKUP_BASE}"
tar -czf "blockchain-backup-${TIMESTAMP}.tar.gz" "${TIMESTAMP}/"
rm -rf "${TIMESTAMP}"

# Clean old backups (keep last 30 days)
find "${BACKUP_BASE}" -name "blockchain-backup-*.tar.gz" -mtime +30 -delete

echo "Backup completed: ${BACKUP_BASE}/blockchain-backup-${TIMESTAMP}.tar.gz"
EOF

    chmod +x /data/blockchain/nodes/scripts/backup-blockchain.sh
    
    # Create cron job for daily backups
    cat > /etc/cron.d/blockchain-backup << 'EOF'
# Daily blockchain infrastructure backup at 3 AM
0 3 * * * root /data/blockchain/nodes/scripts/backup-blockchain.sh >> /var/log/blockchain-backup.log 2>&1
EOF

    echo -e "${GREEN}✓ Automated backups configured${NC}"
}

# 6. Setup Log Rotation
setup_log_rotation() {
    echo -e "\n${BLUE}6. Setting up Log Rotation${NC}"
    
    cat > /etc/logrotate.d/blockchain << 'EOF'
/data/blockchain/nodes/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0644 lyftium lyftium
    sharedscripts
    postrotate
        # Signal services to reopen log files
        systemctl reload ethereum optimism base polygon arbitrum || true
    endscript
}

/var/log/blockchain-*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

    echo -e "${GREEN}✓ Log rotation configured${NC}"
}

# 7. Security Hardening
security_hardening() {
    echo -e "\n${BLUE}7. Applying Security Hardening${NC}"
    
    # Kernel parameters for production
    cat > /etc/sysctl.d/99-blockchain-security.conf << 'EOF'
# Network Security
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.ip_forward = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Performance Tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_tw_buckets = 1440000
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# File Descriptors
fs.file-max = 2097152
EOF

    sysctl -p /etc/sysctl.d/99-blockchain-security.conf
    
    # Secure shared memory
    echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab
    
    echo -e "${GREEN}✓ Security hardening applied${NC}"
}

# 8. Create Production Checklist
create_checklist() {
    echo -e "\n${BLUE}8. Creating Production Checklist${NC}"
    
    cat > /data/blockchain/nodes/PRODUCTION_CHECKLIST.md << 'EOF'
# Production Deployment Checklist

## Pre-Deployment
- [ ] All services tested in staging environment
- [ ] SSL certificates obtained and configured
- [ ] DNS records updated and propagated
- [ ] Firewall rules reviewed and tested
- [ ] Backup procedure tested and verified
- [ ] Monitoring alerts configured and tested
- [ ] Load testing completed
- [ ] Security audit completed

## Deployment
- [ ] Maintenance window scheduled and communicated
- [ ] Current state backed up
- [ ] Services deployed with zero-downtime strategy
- [ ] Health checks passing
- [ ] SSL certificates valid and auto-renewal working
- [ ] Monitoring dashboards showing healthy metrics

## Post-Deployment
- [ ] All endpoints responding correctly
- [ ] Performance metrics within acceptable range
- [ ] No critical errors in logs
- [ ] Alerting working correctly
- [ ] Documentation updated
- [ ] Team briefed on any changes

## Emergency Contacts
- Infrastructure Lead: [CONTACT]
- Security Team: [CONTACT]
- On-Call Engineer: [CONTACT]

## Rollback Procedure
1. Stop affected services: `systemctl stop [service]`
2. Restore from backup: `/data/blockchain/nodes/scripts/restore-backup.sh [timestamp]`
3. Start services: `systemctl start [service]`
4. Verify health: `/data/blockchain/nodes/scripts/health-check.sh`
EOF

    echo -e "${GREEN}✓ Production checklist created${NC}"
}

# Main execution
main() {
    check_root
    backup_config
    fix_systemd_services
    setup_firewall
    setup_fail2ban
    setup_monitoring
    setup_backups
    setup_log_rotation
    security_hardening
    create_checklist
    
    echo -e "\n${GREEN}=== Production Hardening Complete ===${NC}"
    echo -e "Completed at: $(date)"
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "1. Run SSL setup: sudo /data/blockchain/nodes/setup-ssl-production.sh"
    echo "2. Update environment variables in /etc/environment"
    echo "3. Review and test all services"
    echo "4. Complete the production checklist"
}

# Run main function
main "$@"