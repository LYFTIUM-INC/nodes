#!/bin/bash
# Production SSL Certificate Setup Script
# This script configures Let's Encrypt SSL certificates for production deployment

set -euo pipefail

# Configuration
DOMAIN_BASE="${DOMAIN_BASE:-rpc.lyftium.com}"
EMAIL="${SSL_EMAIL:-contact@lyftium.com}"
NGINX_DIR="/etc/nginx"
CERT_DIR="/etc/letsencrypt/live"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Production SSL Certificate Setup${NC}"
echo "=================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Install certbot if not present
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
fi

# Stop nginx temporarily for standalone mode
echo "Stopping nginx for certificate generation..."
systemctl stop nginx || true

# Generate certificates for each subdomain
DOMAINS=(
    "eth.${DOMAIN_BASE}"
    "op.${DOMAIN_BASE}"
    "base.${DOMAIN_BASE}"
    "arb.${DOMAIN_BASE}"
    "polygon.${DOMAIN_BASE}"
    "mev.${DOMAIN_BASE}"
)

for domain in "${DOMAINS[@]}"; do
    echo -e "\n${YELLOW}Generating certificate for ${domain}...${NC}"
    
    if [ -d "${CERT_DIR}/${domain}" ]; then
        echo "Certificate already exists for ${domain}, skipping..."
        continue
    fi
    
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "${EMAIL}" \
        -d "${domain}" \
        --rsa-key-size 4096 \
        --must-staple \
        --staple-ocsp
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Certificate generated for ${domain}${NC}"
    else
        echo -e "${RED}✗ Failed to generate certificate for ${domain}${NC}"
    fi
done

# Update nginx configuration to use real certificates
echo -e "\n${YELLOW}Updating nginx configuration...${NC}"

# Backup current nginx config
cp /etc/nginx/sites-available/mev-infrastructure /etc/nginx/sites-available/mev-infrastructure.bak

# Add production SSL configuration
cat > /etc/nginx/snippets/ssl-params.conf << 'EOF'
# Production SSL Parameters
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

# SSL Session
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;

# Security Headers
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Frame-Options "DENY" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
EOF

# Test nginx configuration
nginx -t

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Nginx configuration is valid${NC}"
    systemctl start nginx
    systemctl reload nginx
else
    echo -e "${RED}✗ Nginx configuration test failed${NC}"
    exit 1
fi

# Setup auto-renewal
echo -e "\n${YELLOW}Setting up auto-renewal...${NC}"
cat > /etc/systemd/system/certbot-renewal.service << 'EOF'
[Unit]
Description=Certbot Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --pre-hook "systemctl stop nginx" --post-hook "systemctl start nginx"
EOF

cat > /etc/systemd/system/certbot-renewal.timer << 'EOF'
[Unit]
Description=Run certbot twice daily

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable certbot-renewal.timer
systemctl start certbot-renewal.timer

echo -e "\n${GREEN}✓ SSL certificate setup complete!${NC}"
echo -e "${GREEN}✓ Auto-renewal configured${NC}"
echo -e "\nNext steps:"
echo "1. Update DNS records to point to this server"
echo "2. Test SSL configuration at: https://www.ssllabs.com/ssltest/"
echo "3. Monitor certificate expiration with: certbot certificates"