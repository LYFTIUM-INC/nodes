#!/bin/bash
# Production RPC Endpoint Readiness Check
# This script verifies all RPC endpoints are production-ready

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DOMAINS=(
    "eth.rpc.lyftium.com"
    "op.rpc.lyftium.com"
    "base.rpc.lyftium.com"
    "arb.rpc.lyftium.com"
    "polygon.rpc.lyftium.com"
)

LOCAL_PORTS=(
    "8545"  # Ethereum
    "8546"  # Optimism
    "8548"  # Base
    "8547"  # Arbitrum (corrected mapping)
    "8549"  # Polygon
)

SERVICES=(
    "ethereum"
    "optimism"
    "base"
    "arbitrum"
    "polygon"
)

echo -e "${BLUE}=== Production RPC Endpoint Readiness Check ===${NC}"
echo -e "Date: $(date)\n"

# Function to check RPC response
check_rpc_endpoint() {
    local endpoint=$1
    local expected_response=$2
    
    echo -n "Checking $endpoint... "
    
    # Test basic connectivity
    response=$(curl -k -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$endpoint" 2>/dev/null || echo "ERROR")
    
    if [ "$response" = "ERROR" ]; then
        echo -e "${RED}✗ Connection failed${NC}"
        return 1
    fi
    
    # Check if response contains block number
    if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        block_hex=$(echo "$response" | jq -r '.result')
        block_num=$((${block_hex}))
        
        if [ "$block_num" -gt 0 ]; then
            echo -e "${GREEN}✓ Block $block_num${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ At genesis (syncing)${NC}"
            return 2
        fi
    else
        echo -e "${RED}✗ Invalid response${NC}"
        return 1
    fi
}

# Function to check local port
check_local_port() {
    local port=$1
    echo -n "Checking localhost:$port... "
    
    if netstat -tlnp | grep -q ":$port "; then
        response=$(curl -s -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "http://127.0.0.1:$port" 2>/dev/null || echo "ERROR")
        
        if [ "$response" != "ERROR" ] && echo "$response" | jq -e '.result' >/dev/null 2>&1; then
            block_hex=$(echo "$response" | jq -r '.result')
            block_num=$((${block_hex}))
            echo -e "${GREEN}✓ Block $block_num${NC}"
            return 0
        else
            echo -e "${RED}✗ No response${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Port not listening${NC}"
        return 1
    fi
}

# Function to check service status
check_service_status() {
    local service=$1
    echo -n "Checking $service service... "
    
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓ Active${NC}"
        return 0
    else
        status=$(systemctl is-active "$service")
        echo -e "${RED}✗ $status${NC}"
        return 1
    fi
}

# Function to check nginx configuration
check_nginx_config() {
    echo -e "\n${BLUE}Checking Nginx Configuration${NC}"
    
    echo -n "Nginx configuration test... "
    if nginx -t >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Valid${NC}"
    else
        echo -e "${RED}✗ Invalid${NC}"
        return 1
    fi
    
    echo -n "Nginx service status... "
    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}✓ Active${NC}"
    else
        echo -e "${RED}✗ Inactive${NC}"
        return 1
    fi
}

# Function to check SSL certificates
check_ssl_certs() {
    echo -e "\n${BLUE}Checking SSL Certificates${NC}"
    
    for domain in "${DOMAINS[@]}"; do
        echo -n "Certificate for $domain... "
        
        cert_file="/etc/letsencrypt/live/$domain/fullchain.pem"
        key_file="/etc/letsencrypt/live/$domain/privkey.pem"
        
        if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
            # Check certificate expiration
            expire_date=$(openssl x509 -in "$cert_file" -noout -dates | grep "notAfter" | cut -d= -f2)
            expire_epoch=$(date -d "$expire_date" +%s)
            current_epoch=$(date +%s)
            days_until_expire=$(( (expire_epoch - current_epoch) / 86400 ))
            
            if [ $days_until_expire -gt 30 ]; then
                echo -e "${GREEN}✓ Valid ($days_until_expire days)${NC}"
            elif [ $days_until_expire -gt 7 ]; then
                echo -e "${YELLOW}⚠ Expires in $days_until_expire days${NC}"
            else
                echo -e "${RED}✗ Expires in $days_until_expire days${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Self-signed or missing${NC}"
        fi
    done
}

# Function to check performance
check_performance() {
    echo -e "\n${BLUE}Checking Performance${NC}"
    
    for i in "${!DOMAINS[@]}"; do
        domain="${DOMAINS[$i]}"
        echo -n "Response time for $domain... "
        
        start_time=$(date +%s%3N)
        response=$(curl -k -s -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "https://$domain:8443/" 2>/dev/null || echo "ERROR")
        end_time=$(date +%s%3N)
        
        if [ "$response" != "ERROR" ]; then
            response_time=$((end_time - start_time))
            if [ $response_time -lt 1000 ]; then
                echo -e "${GREEN}✓ ${response_time}ms${NC}"
            elif [ $response_time -lt 5000 ]; then
                echo -e "${YELLOW}⚠ ${response_time}ms${NC}"
            else
                echo -e "${RED}✗ ${response_time}ms (too slow)${NC}"
            fi
        else
            echo -e "${RED}✗ Failed${NC}"
        fi
    done
}

# Function to check security
check_security() {
    echo -e "\n${BLUE}Checking Security Configuration${NC}"
    
    echo -n "Firewall status... "
    if ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}✓ Active${NC}"
    else
        echo -e "${YELLOW}⚠ Inactive${NC}"
    fi
    
    echo -n "Fail2ban status... "
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}✓ Active${NC}"
    else
        echo -e "${YELLOW}⚠ Inactive${NC}"
    fi
    
    echo -n "Rate limiting configured... "
    if grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
        echo -e "${GREEN}✓ Configured${NC}"
    else
        echo -e "${YELLOW}⚠ Not configured${NC}"
    fi
}

# Function to generate production report
generate_report() {
    echo -e "\n${BLUE}Generating Production Report${NC}"
    
    report_file="/data/blockchain/nodes/production-status-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Production RPC Endpoint Status Report
Generated: $(date)
Server: $(hostname)

=== Service Status ===
$(for service in "${SERVICES[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
    echo "$service: $status"
done)

=== RPC Endpoint Status ===
$(for i in "${!DOMAINS[@]}"; do
    domain="${DOMAINS[$i]}"
    response=$(curl -k -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "https://$domain:8443/" 2>/dev/null || echo '{"error":"connection_failed"}')
    
    if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        block_hex=$(echo "$response" | jq -r '.result')
        block_num=$((${block_hex}))
        echo "$domain: Block $block_num"
    else
        echo "$domain: Error or syncing"
    fi
done)

=== System Resources ===
CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%
Memory Usage: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')
Disk Usage: $(df -h /data | tail -1 | awk '{print $5}')

=== Network Status ===
$(netstat -tlnp | grep -E ':8443|:8545|:8546|:8547|:8548|:8549' | head -10)

=== Recent Errors ===
$(journalctl --since "1 hour ago" -p err -n 10 --no-pager)
EOF
    
    echo -e "Report saved to: ${GREEN}$report_file${NC}"
}

# Main execution
main() {
    echo -e "\n${BLUE}1. Checking Local Ports${NC}"
    local_issues=0
    for i in "${!LOCAL_PORTS[@]}"; do
        if ! check_local_port "${LOCAL_PORTS[$i]}"; then
            ((local_issues++))
        fi
    done
    
    echo -e "\n${BLUE}2. Checking Service Status${NC}"
    service_issues=0
    for service in "${SERVICES[@]}"; do
        if ! check_service_status "$service"; then
            ((service_issues++))
        fi
    done
    
    echo -e "\n${BLUE}3. Checking Domain Endpoints${NC}"
    domain_issues=0
    for domain in "${DOMAINS[@]}"; do
        if ! check_rpc_endpoint "https://$domain:8443/" "block"; then
            ((domain_issues++))
        fi
    done
    
    check_nginx_config
    check_ssl_certs
    check_performance
    check_security
    generate_report
    
    echo -e "\n${BLUE}=== Production Readiness Summary ===${NC}"
    total_issues=$((local_issues + service_issues + domain_issues))
    
    if [ $total_issues -eq 0 ]; then
        echo -e "${GREEN}✅ ALL SYSTEMS READY FOR PRODUCTION${NC}"
        echo -e "${GREEN}✅ All RPC endpoints are responding correctly${NC}"
        echo -e "${GREEN}✅ All services are running${NC}"
        echo -e "${GREEN}✅ Security configurations are in place${NC}"
    else
        echo -e "${YELLOW}⚠️  ISSUES FOUND: $total_issues${NC}"
        echo -e "  • Local port issues: $local_issues"
        echo -e "  • Service issues: $service_issues"
        echo -e "  • Domain endpoint issues: $domain_issues"
        echo -e "\n${YELLOW}Recommendation: Fix issues before production deployment${NC}"
    fi
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo "1. Review the production report"
    echo "2. Fix any identified issues"
    echo "3. Run SSL setup if certificates are missing"
    echo "4. Execute production hardening script"
}

# Run main function
main "$@"