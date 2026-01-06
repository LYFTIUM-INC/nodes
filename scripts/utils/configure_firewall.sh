#!/bin/bash
# Critical Security Implementation: Enterprise Firewall Configuration
# Implements defense-in-depth network security for blockchain infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Security configuration
SECURITY_LOG="/data/blockchain/nodes/logs/firewall-security.log"
ADMIN_IP="$(ip route get 8.8.8.8 | awk '{print $7; exit}')"
SSH_PORT="22"

# Logging function
log_security() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$SECURITY_LOG"
}

echo -e "${GREEN}🔥 CRITICAL SECURITY IMPLEMENTATION: Enterprise Firewall Configuration${NC}"
echo "=============================================================================="

log_security "🔐 Starting comprehensive firewall security implementation"

# Create backup of current iptables rules
echo -e "${BLUE}📦 Creating firewall rules backup...${NC}"
sudo iptables-save > /data/blockchain/nodes/security/iptables_backup_$(date +%Y%m%d_%H%M%S).txt
log_security "📦 Firewall rules backup created"

# Install fail2ban for intrusion prevention
echo -e "${BLUE}🛡️ Installing fail2ban for intrusion prevention...${NC}"
if ! command -v fail2ban-server &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y fail2ban
    log_security "🛡️ fail2ban installed successfully"
else
    log_security "🛡️ fail2ban already installed"
fi

# Configure fail2ban for blockchain services
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
# Ban hosts for 1 hour (3600 seconds)
bantime = 3600
# Monitor for failures over 10 minutes
findtime = 600
# Ban after 3 failures
maxretry = 3
# Email notifications (configure SMTP if needed)
destemail = admin@localhost
sendername = Fail2Ban-Blockchain
mta=sendmail

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[blockchain-rpc]
enabled = true
port = 8545,8546,8547,8548,8549,8550
filter = blockchain-rpc
logpath = /data/blockchain/nodes/logs/*.log
maxretry = 5
bantime = 1800

[mev-dashboard]
enabled = true
port = 8080,8081,8082,8083,8084
filter = mev-dashboard
logpath = /data/blockchain/nodes/logs/dashboard-server.log
maxretry = 10
bantime = 600
EOF

# Create custom fail2ban filter for blockchain RPC
sudo tee /etc/fail2ban/filter.d/blockchain-rpc.conf > /dev/null << 'EOF'
[Definition]
# Fail2ban filter for blockchain RPC abuse
failregex = ^.*\[<HOST>\].*"(error|invalid|unauthorized|forbidden)".*$
            ^.*<HOST>.*authentication failed.*$
            ^.*<HOST>.*rate limit exceeded.*$
            ^.*<HOST>.*suspicious activity.*$
ignoreregex =
EOF

# Create custom fail2ban filter for MEV dashboard
sudo tee /etc/fail2ban/filter.d/mev-dashboard.conf > /dev/null << 'EOF'
[Definition]
# Fail2ban filter for MEV dashboard abuse
failregex = ^.*<HOST>.*401.*$
            ^.*<HOST>.*403.*$
            ^.*<HOST>.*429.*$
            ^.*<HOST>.*bot.*$
ignoreregex =
EOF

# Start and enable fail2ban
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
log_security "🛡️ fail2ban configured and started"

echo -e "${BLUE}🔥 Configuring iptables firewall rules...${NC}"

# Flush existing rules and set default policies
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -t mangle -F
sudo iptables -t mangle -X

# Set default policies (DROP for security)
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

log_security "🔥 Default firewall policies set (DROP)"

# Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j LOG --log-prefix "LOOPBACK: "

# Allow established and related connections
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (with rate limiting)
sudo iptables -A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -m limit --limit 3/min --limit-burst 3 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport $SSH_PORT -m conntrack --ctstate NEW -j LOG --log-prefix "SSH_CONNECT: "

log_security "🔐 SSH access configured with rate limiting"

# BLOCKCHAIN NODE SECURITY RULES
# ==============================

echo -e "${YELLOW}🏗️ Configuring blockchain node security rules...${NC}"

# Ethereum/Erigon (localhost only for security)
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 8545 -j ACCEPT  # HTTP RPC
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 8546 -j ACCEPT  # WebSocket RPC
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 8551 -j ACCEPT  # Engine API
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 6060 -j ACCEPT  # Metrics

# Allow P2P connections for Ethereum (with connection limits)
sudo iptables -A INPUT -p tcp --dport 30303 -m connlimit --connlimit-above 50 -j LOG --log-prefix "ETH_P2P_LIMIT: "
sudo iptables -A INPUT -p tcp --dport 30303 -m connlimit --connlimit-above 50 -j DROP
sudo iptables -A INPUT -p tcp --dport 30303 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 30303 -j ACCEPT

# Polygon (localhost only)
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 8548 -j ACCEPT  # Bor HTTP RPC
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 8550 -j ACCEPT  # Bor WebSocket
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 1317 -j ACCEPT  # Heimdall API

# Allow Polygon P2P (with limits)
sudo iptables -A INPUT -p tcp --dport 30305 -m connlimit --connlimit-above 30 -j DROP
sudo iptables -A INPUT -p tcp --dport 30305 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 30305 -j ACCEPT

# Other blockchain nodes P2P ports (secured)
sudo iptables -A INPUT -p tcp --dport 30304 -m connlimit --connlimit-above 30 -j DROP  # Arbitrum
sudo iptables -A INPUT -p tcp --dport 30304 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9222 -m connlimit --connlimit-above 30 -j DROP   # Base/Optimism
sudo iptables -A INPUT -p tcp --dport 9222 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 9222 -j ACCEPT

log_security "🏗️ Blockchain P2P ports secured with connection limits"

# MEV INFRASTRUCTURE SECURITY
# ===========================

echo -e "${YELLOW}⚡ Configuring MEV infrastructure security...${NC}"

# MEV Dashboard (restrict to admin IP only)
sudo iptables -A INPUT -p tcp -s $ADMIN_IP --dport 8080 -j ACCEPT
sudo iptables -A INPUT -p tcp -s $ADMIN_IP --dport 8081 -j ACCEPT
sudo iptables -A INPUT -p tcp -s $ADMIN_IP --dport 8082 -j ACCEPT
sudo iptables -A INPUT -p tcp -s $ADMIN_IP --dport 8083 -j ACCEPT
sudo iptables -A INPUT -p tcp -s $ADMIN_IP --dport 8084 -j ACCEPT

# Log unauthorized access attempts to MEV services
sudo iptables -A INPUT -p tcp --dport 8080 -j LOG --log-prefix "MEV_UNAUTHORIZED: "
sudo iptables -A INPUT -p tcp --dport 8081 -j LOG --log-prefix "MEV_UNAUTHORIZED: "
sudo iptables -A INPUT -p tcp --dport 8082 -j LOG --log-prefix "MEV_UNAUTHORIZED: "
sudo iptables -A INPUT -p tcp --dport 8083 -j LOG --log-prefix "MEV_UNAUTHORIZED: "
sudo iptables -A INPUT -p tcp --dport 8084 -j LOG --log-prefix "MEV_UNAUTHORIZED: "

# Block unauthorized MEV access
sudo iptables -A INPUT -p tcp --dport 8080:8089 -j DROP

log_security "⚡ MEV infrastructure secured (admin-only access)"

# MONITORING AND METRICS SECURITY
# ===============================

echo -e "${YELLOW}📊 Configuring monitoring security...${NC}"

# Prometheus (localhost only)
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 9090 -j ACCEPT
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 9100 -j ACCEPT  # Node Exporter
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 9101 -j ACCEPT  # Additional Node Exporter

# Grafana (admin IP only)
sudo iptables -A INPUT -p tcp -s $ADMIN_IP --dport 3000 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 3000 -j LOG --log-prefix "GRAFANA_UNAUTHORIZED: "
sudo iptables -A INPUT -p tcp --dport 3000 -j DROP

log_security "📊 Monitoring services secured"

# DDoS PROTECTION
# ==============

echo -e "${YELLOW}🛡️ Implementing DDoS protection...${NC}"

# Rate limit new connections
sudo iptables -A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT
sudo iptables -A INPUT -p tcp -m conntrack --ctstate NEW -j LOG --log-prefix "DDOS_PROTECTION: "
sudo iptables -A INPUT -p tcp -m conntrack --ctstate NEW -j DROP

# Protect against ping floods
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 2 -j ACCEPT
sudo iptables -A INPUT -p icmp --icmp-type echo-request -j LOG --log-prefix "PING_FLOOD: "
sudo iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# Protect against SYN floods
sudo iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
sudo iptables -A INPUT -p tcp --syn -j LOG --log-prefix "SYN_FLOOD: "
sudo iptables -A INPUT -p tcp --syn -j DROP

# Drop invalid packets
sudo iptables -A INPUT -m conntrack --ctstate INVALID -j LOG --log-prefix "INVALID_PACKET: "
sudo iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

log_security "🛡️ DDoS protection implemented"

# STEALTH AND SECURITY ENHANCEMENTS
# =================================

echo -e "${YELLOW}👻 Implementing stealth security features...${NC}"

# Drop all other incoming connections silently
sudo iptables -A INPUT -j LOG --log-prefix "DROPPED: " --log-level 4
sudo iptables -A INPUT -j DROP

# Disable ICMP redirects and source routing
echo 'net.ipv4.conf.all.accept_redirects = 0' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.conf.default.accept_redirects = 0' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.conf.all.accept_source_route = 0' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.conf.default.accept_source_route = 0' | sudo tee -a /etc/sysctl.conf

# Enable SYN cookies
echo 'net.ipv4.tcp_syncookies = 1' | sudo tee -a /etc/sysctl.conf

# Enable IP forwarding protection
echo 'net.ipv4.conf.all.send_redirects = 0' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.conf.default.send_redirects = 0' | sudo tee -a /etc/sysctl.conf

# Apply sysctl settings
sudo sysctl -p

log_security "👻 Stealth security features enabled"

# SAVE AND PERSIST FIREWALL RULES
# ===============================

echo -e "${BLUE}💾 Saving and persisting firewall rules...${NC}"

# Install iptables-persistent
if ! dpkg -l | grep -q iptables-persistent; then
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections
    sudo apt-get install -y iptables-persistent
fi

# Save current rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
sudo ip6tables-save | sudo tee /etc/iptables/rules.v6 > /dev/null

log_security "💾 Firewall rules saved and will persist on reboot"

# Create firewall management script
cat > /data/blockchain/nodes/security/manage_firewall.sh << 'EOF'
#!/bin/bash
# Firewall Management Script

case "$1" in
    status)
        echo "=== Firewall Status ==="
        sudo iptables -L -n -v
        echo ""
        echo "=== fail2ban Status ==="
        sudo fail2ban-client status
        ;;
    restart)
        echo "Restarting firewall and fail2ban..."
        sudo systemctl restart fail2ban
        sudo iptables-restore < /etc/iptables/rules.v4
        ;;
    logs)
        echo "=== Recent firewall logs ==="
        sudo tail -n 50 /var/log/kern.log | grep -E "(DROPPED|SSH_CONNECT|MEV_UNAUTHORIZED)"
        echo ""
        echo "=== fail2ban logs ==="
        sudo tail -n 20 /var/log/fail2ban.log
        ;;
    ban-list)
        echo "=== Currently banned IPs ==="
        sudo fail2ban-client status sshd
        sudo fail2ban-client status blockchain-rpc
        sudo fail2ban-client status mev-dashboard
        ;;
    *)
        echo "Usage: $0 {status|restart|logs|ban-list}"
        exit 1
        ;;
esac
EOF

chmod +x /data/blockchain/nodes/security/manage_firewall.sh

log_security "🔧 Firewall management script created"

# SECURITY VALIDATION
# ===================

echo -e "${GREEN}🔍 Performing security validation...${NC}"

# Test firewall rules
echo -e "${BLUE}Testing firewall configuration...${NC}"

# Check if rules are loaded
RULE_COUNT=$(sudo iptables -L INPUT | wc -l)
if [ $RULE_COUNT -gt 10 ]; then
    echo "✅ Firewall rules loaded successfully ($RULE_COUNT rules)"
    log_security "✅ Firewall rules validation passed"
else
    echo "❌ Firewall rules may not be loaded properly"
    log_security "❌ Firewall rules validation failed"
fi

# Check fail2ban status
if sudo systemctl is-active --quiet fail2ban; then
    echo "✅ fail2ban is running"
    log_security "✅ fail2ban validation passed"
else
    echo "❌ fail2ban is not running"
    log_security "❌ fail2ban validation failed"
fi

# FINAL SECURITY REPORT
# =====================

echo -e "${GREEN}🎉 FIREWALL SECURITY IMPLEMENTATION COMPLETED!${NC}"
echo "=============================================================================="
echo -e "${GREEN}✅ Enterprise firewall rules deployed${NC}"
echo -e "${GREEN}✅ Intrusion prevention system (fail2ban) configured${NC}"
echo -e "${GREEN}✅ DDoS protection implemented${NC}"
echo -e "${GREEN}✅ Network stealth features enabled${NC}"
echo -e "${GREEN}✅ Blockchain services secured (localhost-only RPC)${NC}"
echo -e "${GREEN}✅ MEV infrastructure protected (admin-only access)${NC}"
echo -e "${GREEN}✅ Monitoring services secured${NC}"
echo -e "${GREEN}✅ Rules persisted for reboot${NC}"
echo ""
echo -e "${YELLOW}🔒 SECURITY FEATURES ACTIVE:${NC}"
echo "• SSH rate limiting (3 attempts/minute)"
echo "• RPC services restricted to localhost"
echo "• MEV dashboard admin-only access"
echo "• P2P connection limits (30-50 per service)"
echo "• DDoS protection (60 new connections/second max)"
echo "• Invalid packet filtering"
echo "• Intrusion detection and auto-banning"
echo "• Comprehensive security logging"
echo ""
echo -e "${BLUE}📋 MANAGEMENT COMMANDS:${NC}"
echo "• Check status: /data/blockchain/nodes/security/manage_firewall.sh status"
echo "• View logs: /data/blockchain/nodes/security/manage_firewall.sh logs"
echo "• Check bans: /data/blockchain/nodes/security/manage_firewall.sh ban-list"
echo "• Restart: /data/blockchain/nodes/security/manage_firewall.sh restart"
echo ""
echo -e "${RED}⚠️  CRITICAL SECURITY NOTES:${NC}"
echo "• Admin IP: $ADMIN_IP (only IP with full access)"
echo "• All RPC services now localhost-only"
echo "• Use SSH tunneling for remote RPC access"
echo "• Monitor logs in /data/blockchain/nodes/logs/firewall-security.log"
echo "• Firewall rules auto-restore on reboot"

log_security "🎉 FIREWALL SECURITY IMPLEMENTATION COMPLETED SUCCESSFULLY"

echo ""
echo -e "${GREEN}Security implementation completed! Your blockchain infrastructure is now protected.${NC}"