# Security Procedures - Critical Vulnerability Remediation & Ongoing Operations
**Version 3.6.5 | July 2025**

## Table of Contents
1. [Critical Vulnerability Overview](#critical-vulnerability-overview)
2. [Immediate Security Actions](#immediate-security-actions)
3. [Security Monitoring Workflows](#security-monitoring-workflows)
4. [Access Control Management](#access-control-management)
5. [Incident Response Protocols](#incident-response-protocols)
6. [Security Audit Procedures](#security-audit-procedures)
7. [Threat Intelligence Integration](#threat-intelligence-integration)

---

## Critical Vulnerability Overview

### Current Security Posture
- **Overall Score**: 79.6/100 (ACCEPTABLE - Improvements Required)
- **Critical Findings**: 2 HIGH, 3 MEDIUM, 3 LOW severity issues
- **Compliance Gap**: 29% below enterprise requirements

### Priority Remediation Items

| Finding | Severity | Impact | Remediation Timeline |
|---------|----------|---------|---------------------|
| MEV Dashboard Exposure (ports 8080-8084) | MEDIUM | Data leakage risk | Immediate |
| Hardcoded IPs in security monitoring | MEDIUM | Reduced flexibility | 24 hours |
| Limited input sanitization | LOW | Potential injection | 48 hours |
| Port 3000 exposed | LOW | Development leak | Immediate |
| Compliance documentation gaps | MEDIUM | Audit failure risk | 7 days |

---

## Immediate Security Actions

### Step 1: Secure MEV Dashboard Access

```bash
# 1. Restrict dashboard to VPN-only access
sudo iptables -I INPUT -p tcp --dport 8080:8084 ! -s 10.0.0.0/8 -j DROP
sudo iptables -I INPUT -p tcp --dport 3000 -j DROP

# 2. Add authentication layer
cat > /etc/nginx/sites-available/mev-dashboard-secure << EOF
server {
    listen 8080 ssl;
    server_name mev-dashboard.internal;
    
    ssl_certificate /etc/ssl/certs/mev-dashboard.crt;
    ssl_certificate_key /etc/ssl/private/mev-dashboard.key;
    
    auth_basic "MEV Dashboard Access";
    auth_basic_user_file /etc/nginx/.htpasswd;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# 3. Create secure credentials
htpasswd -c /etc/nginx/.htpasswd mev_operator

# 4. Save firewall rules
sudo iptables-save > /etc/iptables/rules.v4
```

### Step 2: Fix Hardcoded Security Parameters

```python
# Create dynamic security configuration
cat > /data/blockchain/nodes/security/dynamic_security_config.py << 'EOF'
#!/usr/bin/env python3
import json
import os
from typing import Dict, List

class DynamicSecurityConfig:
    def __init__(self):
        self.config_file = "/data/blockchain/nodes/config/security_config.json"
        self.load_config()
    
    def load_config(self):
        """Load security configuration from file"""
        if os.path.exists(self.config_file):
            with open(self.config_file, 'r') as f:
                self.config = json.load(f)
        else:
            self.config = self.get_default_config()
            self.save_config()
    
    def get_default_config(self) -> Dict:
        """Default security configuration"""
        return {
            "malicious_ips": [],
            "suspicious_patterns": [
                r"(\.\./){2,}",
                r"<script[^>]*>",
                r"union.*select",
                r"exec\s*\(",
                r"eval\s*\("
            ],
            "rate_limits": {
                "api_calls_per_minute": 60,
                "login_attempts": 5,
                "transaction_requests": 100
            },
            "monitoring": {
                "log_retention_days": 90,
                "alert_thresholds": {
                    "failed_auth": 10,
                    "high_cpu": 90,
                    "suspicious_activity": 5
                }
            }
        }
    
    def update_malicious_ips(self, ips: List[str]):
        """Update malicious IP list"""
        self.config["malicious_ips"] = list(set(self.config["malicious_ips"] + ips))
        self.save_config()
    
    def save_config(self):
        """Save configuration to file"""
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, indent=2)

if __name__ == "__main__":
    config = DynamicSecurityConfig()
    # Update with threat intelligence feeds
    config.update_malicious_ips(["192.168.1.100", "10.0.0.50"])
EOF

chmod +x /data/blockchain/nodes/security/dynamic_security_config.py
```

### Step 3: Enhanced Input Sanitization

```python
# Create input validation module
cat > /data/blockchain/nodes/security/input_validator.py << 'EOF'
#!/usr/bin/env python3
import re
import html
from typing import Any, Optional

class InputValidator:
    """Enhanced input validation and sanitization"""
    
    @staticmethod
    def sanitize_string(input_str: str, max_length: int = 1000) -> str:
        """Sanitize string input"""
        if not isinstance(input_str, str):
            return ""
        
        # Remove null bytes
        input_str = input_str.replace('\x00', '')
        
        # HTML escape
        input_str = html.escape(input_str)
        
        # Truncate to max length
        return input_str[:max_length]
    
    @staticmethod
    def validate_address(address: str) -> bool:
        """Validate Ethereum address"""
        pattern = r'^0x[a-fA-F0-9]{40}$'
        return bool(re.match(pattern, address))
    
    @staticmethod
    def validate_transaction_hash(tx_hash: str) -> bool:
        """Validate transaction hash"""
        pattern = r'^0x[a-fA-F0-9]{64}$'
        return bool(re.match(pattern, tx_hash))
    
    @staticmethod
    def validate_numeric(value: Any, min_val: float = 0, max_val: float = float('inf')) -> Optional[float]:
        """Validate numeric input"""
        try:
            num = float(value)
            if min_val <= num <= max_val:
                return num
        except (ValueError, TypeError):
            pass
        return None
    
    @staticmethod
    def sanitize_sql_identifier(identifier: str) -> str:
        """Sanitize SQL identifiers"""
        # Only allow alphanumeric and underscore
        return re.sub(r'[^a-zA-Z0-9_]', '', identifier)

# Integration with existing security monitoring
def enhance_security_monitoring():
    from input_validator import InputValidator
    validator = InputValidator()
    
    # Use in API endpoints
    def validate_api_input(data):
        if 'address' in data:
            if not validator.validate_address(data['address']):
                raise ValueError("Invalid address format")
        
        if 'amount' in data:
            amount = validator.validate_numeric(data['amount'], 0, 1000000)
            if amount is None:
                raise ValueError("Invalid amount")
        
        return True
EOF
```

---

## Security Monitoring Workflows

### Real-Time Security Monitoring

#### 1. Launch Security Dashboard
```bash
# Start enhanced security monitoring
cd /data/blockchain/nodes/security
python3 security_monitoring_fixed.py --enhanced &

# Access security dashboard
echo "Security Dashboard: http://localhost:9999"
```

#### 2. Configure Security Alerts
```yaml
# /data/blockchain/nodes/config/security_alerts.yaml
alerts:
  critical:
    - name: "Unauthorized Access Attempt"
      condition: "failed_auth_count > 10"
      action: "block_ip && notify_security"
    
    - name: "Potential DDoS Attack"
      condition: "request_rate > 1000/min"
      action: "enable_rate_limiting && alert_ops"
    
    - name: "Suspicious MEV Activity"
      condition: "unusual_gas_price || failed_transactions > 5"
      action: "pause_mev_engine && investigate"
  
  high:
    - name: "Resource Exhaustion"
      condition: "cpu > 95 || memory > 95"
      action: "scale_resources && notify_ops"
```

### Continuous Security Scanning

```bash
# Create automated security scanner
cat > /data/blockchain/nodes/security/continuous_scanner.sh << 'EOF'
#!/bin/bash

while true; do
    echo "=== Security Scan $(date) ==="
    
    # Check for exposed ports
    echo "Checking exposed ports..."
    netstat -tuln | grep -E "0.0.0.0:|::::" | grep -v "127.0.0.1"
    
    # Scan for vulnerable dependencies
    echo "Scanning dependencies..."
    pip3 list --outdated
    npm audit
    
    # Check file permissions
    echo "Verifying file permissions..."
    find /data/blockchain -type f -perm 0777 -ls
    find /data/blockchain -type d -perm 0777 -ls
    
    # Monitor suspicious processes
    echo "Checking processes..."
    ps aux | grep -E "nc |netcat|wget|curl" | grep -v grep
    
    # Check for unauthorized SSH keys
    echo "Auditing SSH keys..."
    for user in $(ls /home); do
        if [ -f /home/$user/.ssh/authorized_keys ]; then
            echo "Keys for $user:"
            wc -l /home/$user/.ssh/authorized_keys
        fi
    done
    
    sleep 3600  # Run hourly
done
EOF

chmod +x /data/blockchain/nodes/security/continuous_scanner.sh
nohup /data/blockchain/nodes/security/continuous_scanner.sh &
```

---

## Access Control Management

### Role-Based Access Control (RBAC)

#### 1. Define Security Roles
```bash
# Create RBAC configuration
cat > /data/blockchain/nodes/security/rbac_config.json << EOF
{
  "roles": {
    "mev_operator": {
      "description": "MEV system operator",
      "permissions": [
        "mev:read",
        "mev:execute",
        "monitoring:read",
        "logs:read"
      ]
    },
    "security_admin": {
      "description": "Security administrator",
      "permissions": [
        "security:*",
        "audit:*",
        "users:manage",
        "system:configure"
      ]
    },
    "auditor": {
      "description": "Compliance auditor",
      "permissions": [
        "audit:read",
        "logs:read",
        "monitoring:read",
        "compliance:read"
      ]
    },
    "readonly": {
      "description": "Read-only access",
      "permissions": [
        "monitoring:read",
        "status:read"
      ]
    }
  },
  "users": {
    "operator1": ["mev_operator"],
    "security1": ["security_admin"],
    "auditor1": ["auditor"]
  }
}
EOF
```

#### 2. Implement Access Controls
```python
# Access control enforcement
cat > /data/blockchain/nodes/security/access_control.py << 'EOF'
#!/usr/bin/env python3
import json
import functools
from flask import request, abort

class AccessControl:
    def __init__(self):
        with open('/data/blockchain/nodes/security/rbac_config.json') as f:
            self.rbac = json.load(f)
    
    def require_permission(self, permission):
        def decorator(f):
            @functools.wraps(f)
            def decorated_function(*args, **kwargs):
                user = self.get_current_user()
                if not self.has_permission(user, permission):
                    abort(403, f"Permission denied: {permission}")
                return f(*args, **kwargs)
            return decorated_function
        return decorator
    
    def get_current_user(self):
        # Extract from JWT token or session
        return request.headers.get('X-User-ID', 'anonymous')
    
    def has_permission(self, user, permission):
        if user not in self.rbac['users']:
            return False
        
        user_roles = self.rbac['users'][user]
        for role in user_roles:
            if permission in self.rbac['roles'][role]['permissions']:
                return True
            # Check wildcard permissions
            perm_parts = permission.split(':')
            wildcard = f"{perm_parts[0]}:*"
            if wildcard in self.rbac['roles'][role]['permissions']:
                return True
        
        return False

# Usage example
access_control = AccessControl()

@app.route('/api/mev/execute', methods=['POST'])
@access_control.require_permission('mev:execute')
def execute_mev_strategy():
    # Protected endpoint
    pass
EOF
```

### Multi-Factor Authentication (MFA)

```bash
# Setup Google Authenticator for operators
apt-get install -y libpam-google-authenticator

# Configure for each operator
for user in operator1 security1 auditor1; do
    su - $user -c "google-authenticator -t -d -f -r 3 -R 30 -W"
done

# Update SSH configuration
echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config
echo "ChallengeResponseAuthentication yes" >> /etc/ssh/sshd_config

# Configure PAM
echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
systemctl restart sshd
```

---

## Incident Response Protocols

### Security Incident Classification

| Level | Type | Response Time | Escalation |
|-------|------|---------------|------------|
| P0 | Active Breach | Immediate | CEO, CISO |
| P1 | Attempted Breach | < 15 min | Security Team |
| P2 | Vulnerability Found | < 1 hour | Security Lead |
| P3 | Suspicious Activity | < 4 hours | On-call Engineer |

### Incident Response Runbook

#### Phase 1: Detection & Analysis (0-15 minutes)
```bash
# 1. Confirm incident
./security/verify_incident.sh [incident_id]

# 2. Assess scope
python3 security/incident_analyzer.py --incident [incident_id]

# 3. Preserve evidence
./security/preserve_evidence.sh [incident_id]
```

#### Phase 2: Containment (15-30 minutes)
```bash
# 1. Isolate affected systems
./security/isolate_system.sh [system_name]

# 2. Block malicious IPs
./security/block_ips.sh [ip_list]

# 3. Disable compromised accounts
./security/disable_accounts.sh [account_list]
```

#### Phase 3: Eradication (30-60 minutes)
```bash
# 1. Remove malicious artifacts
./security/clean_system.sh [system_name]

# 2. Patch vulnerabilities
./security/apply_patches.sh

# 3. Update security rules
./security/update_rules.sh
```

#### Phase 4: Recovery (1-4 hours)
```bash
# 1. Restore from clean backup
./security/restore_system.sh [system_name]

# 2. Verify system integrity
./security/verify_integrity.sh

# 3. Resume operations
./security/resume_operations.sh
```

#### Phase 5: Post-Incident (24-48 hours)
```bash
# 1. Generate incident report
./security/generate_report.sh [incident_id]

# 2. Update security procedures
./security/update_procedures.sh

# 3. Conduct lessons learned
./security/lessons_learned.sh [incident_id]
```

---

## Security Audit Procedures

### Weekly Security Audit Checklist

#### 1. Access Review
```bash
# Review user access
./security/audit_access.sh > /tmp/access_audit_$(date +%Y%m%d).log

# Check for dormant accounts
lastlog -b 30 | grep -v "Never logged in"

# Verify SSH key usage
./security/audit_ssh_keys.sh
```

#### 2. Configuration Audit
```bash
# Check security configurations
./security/audit_configs.sh

# Verify firewall rules
iptables -L -n -v > /tmp/firewall_audit_$(date +%Y%m%d).log

# Review service configurations
for service in nginx sshd postgresql redis; do
    echo "=== $service configuration ==="
    grep -E "^[^#]" /etc/$service/*.conf
done
```

#### 3. Log Analysis
```bash
# Analyze security logs
python3 << EOF
import re
from collections import Counter

# Read security logs
with open('/var/log/auth.log') as f:
    logs = f.readlines()

# Find failed authentications
failed_auths = [line for line in logs if 'Failed password' in line]
ips = [re.search(r'from (\d+\.\d+\.\d+\.\d+)', line).group(1) 
       for line in failed_auths if re.search(r'from (\d+\.\d+\.\d+\.\d+)', line)]

# Count by IP
ip_counts = Counter(ips)
print("Top failed auth IPs:")
for ip, count in ip_counts.most_common(10):
    print(f"{ip}: {count} attempts")
EOF
```

### Monthly Compliance Audit

```bash
# Create compliance audit script
cat > /data/blockchain/nodes/security/compliance_audit.sh << 'EOF'
#!/bin/bash

AUDIT_DATE=$(date +%Y%m%d)
AUDIT_DIR="/data/blockchain/audits/$AUDIT_DATE"
mkdir -p $AUDIT_DIR

echo "=== MEV Infrastructure Compliance Audit ==="
echo "Date: $(date)"
echo "Auditor: $USER"

# 1. Data Protection Compliance
echo -e "\n[1] Data Protection Checks"
find /data -name "*.key" -o -name "*.pem" -exec ls -la {} \; > $AUDIT_DIR/encryption_keys.log
grep -r "password\|secret\|key" /data/blockchain/nodes/config/ > $AUDIT_DIR/hardcoded_secrets.log

# 2. Access Control Compliance
echo -e "\n[2] Access Control Verification"
cat /etc/passwd | grep -E ":[0-9]{4}:" > $AUDIT_DIR/user_audit.log
find / -perm -4000 2>/dev/null > $AUDIT_DIR/suid_files.log

# 3. Logging Compliance
echo -e "\n[3] Logging Configuration"
ls -la /var/log/ > $AUDIT_DIR/log_files.log
du -sh /var/log/* > $AUDIT_DIR/log_sizes.log

# 4. Network Security Compliance
echo -e "\n[4] Network Security"
ss -tuln > $AUDIT_DIR/listening_ports.log
iptables-save > $AUDIT_DIR/firewall_rules.log

# 5. Generate Report
cat > $AUDIT_DIR/compliance_report.md << REPORT
# Compliance Audit Report
Date: $(date)

## Summary
- Total users: $(cat /etc/passwd | wc -l)
- Open ports: $(ss -tuln | grep LISTEN | wc -l)
- Firewall rules: $(iptables -L | grep -c "^Chain")
- Log retention: $(find /var/log -mtime +90 | wc -l) files older than 90 days

## Recommendations
[To be filled by auditor]

## Sign-off
Auditor: ________________
Date: ________________
REPORT

echo "Audit complete. Report saved to: $AUDIT_DIR/compliance_report.md"
EOF

chmod +x /data/blockchain/nodes/security/compliance_audit.sh
```

---

## Threat Intelligence Integration

### Automated Threat Feed Integration

```python
# Create threat intelligence integration
cat > /data/blockchain/nodes/security/threat_intelligence.py << 'EOF'
#!/usr/bin/env python3
import requests
import json
import sqlite3
from datetime import datetime
import logging

class ThreatIntelligence:
    def __init__(self):
        self.db_path = "/data/blockchain/nodes/security/threat_intel.db"
        self.setup_database()
        self.feeds = {
            "abuse_ipdb": "https://api.abuseipdb.com/api/v2/blacklist",
            "emergingthreats": "https://rules.emergingthreats.net/blockrules/compromised-ips.txt",
            "blockchain_threat_intel": "https://api.chainanalysis.com/api/v1/addresses/risky"
        }
    
    def setup_database(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS threats (
                indicator TEXT PRIMARY KEY,
                threat_type TEXT,
                confidence REAL,
                source TEXT,
                first_seen TIMESTAMP,
                last_seen TIMESTAMP,
                metadata TEXT
            )
        ''')
        conn.commit()
        conn.close()
    
    def update_threat_feeds(self):
        """Update threat intelligence from all feeds"""
        for feed_name, feed_url in self.feeds.items():
            try:
                self.update_feed(feed_name, feed_url)
            except Exception as e:
                logging.error(f"Failed to update {feed_name}: {e}")
    
    def update_feed(self, feed_name, feed_url):
        """Update specific threat feed"""
        # Implementation depends on feed format
        if feed_name == "abuse_ipdb":
            headers = {"Key": "YOUR_API_KEY"}
            response = requests.get(feed_url, headers=headers)
            data = response.json()
            
            conn = sqlite3.connect(self.db_path)
            for item in data.get('data', []):
                conn.execute('''
                    INSERT OR REPLACE INTO threats 
                    (indicator, threat_type, confidence, source, first_seen, last_seen, metadata)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ''', (
                    item['ipAddress'],
                    'malicious_ip',
                    item['abuseConfidenceScore'] / 100.0,
                    feed_name,
                    datetime.now(),
                    datetime.now(),
                    json.dumps(item)
                ))
            conn.commit()
            conn.close()
    
    def check_threat(self, indicator):
        """Check if an indicator is a known threat"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.execute(
            "SELECT * FROM threats WHERE indicator = ?", 
            (indicator,)
        )
        result = cursor.fetchone()
        conn.close()
        return result

# Integration with security monitoring
def enhance_security_with_threat_intel():
    threat_intel = ThreatIntelligence()
    
    # Update feeds every hour
    import schedule
    schedule.every().hour.do(threat_intel.update_threat_feeds)
    
    # Check incoming connections
    def check_connection(ip_address):
        threat = threat_intel.check_threat(ip_address)
        if threat and threat[2] > 0.7:  # High confidence threat
            # Block the IP
            os.system(f"iptables -A INPUT -s {ip_address} -j DROP")
            logging.warning(f"Blocked threat: {ip_address}")
EOF
```

### MEV-Specific Threat Detection

```python
# MEV threat detection module
cat > /data/blockchain/nodes/security/mev_threat_detection.py << 'EOF'
#!/usr/bin/env python3
import json
from web3 import Web3
from typing import Dict, List

class MEVThreatDetector:
    def __init__(self, web3_provider: str):
        self.w3 = Web3(Web3.HTTPProvider(web3_provider))
        self.known_attacks = {
            "sandwich": self.detect_sandwich_attack,
            "frontrun": self.detect_frontrunning,
            "backrun": self.detect_backrunning,
            "uncle_bandit": self.detect_uncle_bandit
        }
    
    def analyze_transaction(self, tx_hash: str) -> Dict:
        """Analyze transaction for MEV threats"""
        tx = self.w3.eth.get_transaction(tx_hash)
        receipt = self.w3.eth.get_transaction_receipt(tx_hash)
        block = self.w3.eth.get_block(tx.blockNumber, full_transactions=True)
        
        threats = []
        for attack_type, detector in self.known_attacks.items():
            if detector(tx, block):
                threats.append(attack_type)
        
        return {
            "tx_hash": tx_hash,
            "threats": threats,
            "risk_score": len(threats) / len(self.known_attacks),
            "block": tx.blockNumber,
            "gas_price": tx.gasPrice
        }
    
    def detect_sandwich_attack(self, tx, block) -> bool:
        """Detect potential sandwich attacks"""
        tx_index = None
        for i, btx in enumerate(block.transactions):
            if btx.hash == tx.hash:
                tx_index = i
                break
        
        if tx_index is None or tx_index == 0 or tx_index == len(block.transactions) - 1:
            return False
        
        # Check for similar transactions before and after
        before_tx = block.transactions[tx_index - 1]
        after_tx = block.transactions[tx_index + 1]
        
        # Simple heuristic: same from address and interacting with same contract
        if (before_tx['from'] == after_tx['from'] and 
            before_tx['to'] == tx['to'] and 
            after_tx['to'] == tx['to']):
            return True
        
        return False
    
    def detect_frontrunning(self, tx, block) -> bool:
        """Detect potential frontrunning"""
        # Check if transaction was included with significantly higher gas than average
        avg_gas = sum(t.gasPrice for t in block.transactions) / len(block.transactions)
        return tx.gasPrice > avg_gas * 1.5

# Monitor for MEV threats in real-time
def monitor_mev_threats():
    detector = MEVThreatDetector("http://localhost:8545")
    
    def on_new_block(block_number):
        block = detector.w3.eth.get_block(block_number, full_transactions=True)
        for tx in block.transactions:
            analysis = detector.analyze_transaction(tx.hash)
            if analysis['risk_score'] > 0.5:
                logging.warning(f"High-risk MEV activity detected: {analysis}")
EOF
```

---

## Appendix: Security Quick Reference

### Emergency Security Commands
```bash
# Block all incoming connections (emergency)
iptables -P INPUT DROP

# Enable emergency mode
./security/emergency-lockdown.sh

# Rotate all secrets
./security/rotate_all_secrets.sh

# Check for rootkits
rkhunter --check

# Scan for vulnerabilities
nikto -h localhost
```

### Security Monitoring URLs
- Security Dashboard: http://localhost:9999
- Threat Intelligence: http://localhost:9998
- Audit Reports: http://localhost:9997

### Security Contacts
- CISO: ciso@company.com
- Security Team: security@company.com
- Incident Response: incident-response@company.com

---

**Document Classification**: CONFIDENTIAL - SECURITY SENSITIVE  
**Last Updated**: July 17, 2025  
**Next Review**: July 24, 2025