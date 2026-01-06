# Compliance and Audit Documentation: MEV Infrastructure
**Version**: 2.0  
**Last Updated**: July 11, 2025  
**Classification**: Compliance Documentation  
**Standards**: SOX, SOC 2, ISO 27001, GDPR

---

## 📋 Table of Contents

1. [Compliance Overview](#compliance-overview)
2. [Regulatory Framework](#regulatory-framework)
3. [Audit Trail Documentation](#audit-trail-documentation)
4. [Access Control & Security](#access-control--security)
5. [Data Protection & Privacy](#data-protection--privacy)
6. [Risk Management](#risk-management)
7. [Compliance Monitoring](#compliance-monitoring)
8. [Incident Management](#incident-management)
9. [Business Continuity](#business-continuity)
10. [Audit Procedures](#audit-procedures)

---

## 🏛️ Compliance Overview

### Compliance Scope

The MEV Infrastructure operates under multiple compliance frameworks to ensure:
- **Financial Integrity**: Accurate transaction recording and reporting
- **Data Security**: Protection of sensitive trading data
- **Operational Excellence**: Reliable and auditable operations
- **Regulatory Adherence**: Compliance with relevant financial regulations

### Applicable Standards

| Standard | Scope | Certification Status | Last Audit |
|----------|-------|---------------------|------------|
| SOC 2 Type II | Security, Availability | In Progress | Q2 2025 |
| ISO 27001 | Information Security | Planned | Q4 2025 |
| PCI DSS | Payment Processing | N/A | - |
| GDPR | Data Privacy | Compliant | Q1 2025 |

---

## 📜 Regulatory Framework

### Financial Regulations

#### Market Manipulation Prevention
```yaml
anti_manipulation_controls:
  - control: "Automated detection of wash trading patterns"
    implementation: "Real-time transaction analysis"
    frequency: "Continuous"
    
  - control: "Price impact limitations"
    implementation: "Maximum 2% price movement per trade"
    frequency: "Per transaction"
    
  - control: "Competitor analysis restrictions"
    implementation: "No targeting of specific traders"
    frequency: "Continuous"
```

#### Transaction Reporting Requirements
```python
# Automated compliance reporting
class ComplianceReporter:
    def __init__(self):
        self.reporting_threshold = 10000  # USD
        self.regulatory_api = "https://regulatory-api.example.com"
    
    def report_transaction(self, transaction):
        """Report transactions above threshold"""
        if transaction['usd_value'] >= self.reporting_threshold:
            report = {
                'transaction_id': transaction['id'],
                'timestamp': transaction['timestamp'],
                'value_usd': transaction['usd_value'],
                'type': 'MEV_EXTRACTION',
                'chain': transaction['chain'],
                'profit': transaction['profit'],
                'reporting_entity': 'COMPANY_NAME',
                'jurisdiction': 'US'
            }
            
            # Submit to regulatory reporting system
            self.submit_report(report)
            
            # Log for audit trail
            self.log_compliance_event(report)
```

### Know Your Transaction (KYT)

```sql
-- Transaction monitoring queries
-- Identify suspicious patterns

-- Large value transactions
SELECT 
    transaction_id,
    timestamp,
    chain,
    profit_usd,
    gas_cost_usd,
    wallet_address
FROM mev_transactions
WHERE profit_usd > 50000
    OR gas_cost_usd > 1000
ORDER BY timestamp DESC;

-- Unusual trading patterns
WITH hourly_stats AS (
    SELECT 
        DATE_TRUNC('hour', timestamp) as hour,
        COUNT(*) as tx_count,
        SUM(profit_usd) as total_profit,
        AVG(profit_usd) as avg_profit
    FROM mev_transactions
    GROUP BY DATE_TRUNC('hour', timestamp)
)
SELECT * FROM hourly_stats
WHERE tx_count > (SELECT AVG(tx_count) * 3 FROM hourly_stats)
    OR total_profit > (SELECT AVG(total_profit) * 5 FROM hourly_stats);
```

---

## 📊 Audit Trail Documentation

### Comprehensive Audit Logging

```python
import json
import hashlib
from datetime import datetime
from cryptography.fernet import Fernet

class AuditLogger:
    def __init__(self, encryption_key):
        self.cipher = Fernet(encryption_key)
        self.log_path = "/secure/audit/logs/"
        
    def log_event(self, event_type, details, user=None):
        """Create tamper-proof audit log entry"""
        entry = {
            'id': self.generate_event_id(),
            'timestamp': datetime.utcnow().isoformat(),
            'event_type': event_type,
            'user': user or 'system',
            'details': details,
            'system_state': self.capture_system_state()
        }
        
        # Create hash for integrity
        entry['hash'] = self.calculate_hash(entry)
        
        # Encrypt sensitive data
        encrypted_entry = self.encrypt_entry(entry)
        
        # Store in multiple locations
        self.store_audit_entry(encrypted_entry)
        
        return entry['id']
    
    def calculate_hash(self, entry):
        """Calculate SHA-256 hash of entry"""
        entry_str = json.dumps(entry, sort_keys=True)
        return hashlib.sha256(entry_str.encode()).hexdigest()
    
    def verify_integrity(self, entry):
        """Verify audit log hasn't been tampered with"""
        stored_hash = entry.pop('hash')
        calculated_hash = self.calculate_hash(entry)
        return stored_hash == calculated_hash
```

### Audit Event Categories

| Category | Events | Retention | Encryption |
|----------|--------|-----------|------------|
| Authentication | Login, Logout, Failed attempts | 7 years | Yes |
| Configuration | Changes to system config | 7 years | Yes |
| Transactions | All MEV transactions | 7 years | Yes |
| Access Control | Permission changes | 7 years | Yes |
| System Events | Start, Stop, Errors | 3 years | No |
| Monitoring | Health checks, Alerts | 1 year | No |

### Audit Log Schema

```sql
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    event_type VARCHAR(50) NOT NULL,
    user_id VARCHAR(100),
    ip_address INET,
    user_agent TEXT,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    old_value JSONB,
    new_value JSONB,
    result VARCHAR(20) NOT NULL,
    error_message TEXT,
    metadata JSONB,
    hash VARCHAR(64) NOT NULL,
    
    -- Indexes for compliance queries
    INDEX idx_audit_timestamp (timestamp),
    INDEX idx_audit_user (user_id),
    INDEX idx_audit_event_type (event_type),
    INDEX idx_audit_resource (resource_type, resource_id)
);

-- Audit log integrity table
CREATE TABLE audit_log_integrity (
    id SERIAL PRIMARY KEY,
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end TIMESTAMP WITH TIME ZONE NOT NULL,
    record_count INTEGER NOT NULL,
    hash_chain VARCHAR(64) NOT NULL,
    verified_at TIMESTAMP WITH TIME ZONE,
    verified_by VARCHAR(100),
    
    UNIQUE(period_start, period_end)
);
```

---

## 🔐 Access Control & Security

### Role-Based Access Control (RBAC)

```yaml
roles:
  - name: mev_operator
    permissions:
      - view_opportunities
      - execute_trades
      - view_performance
    restrictions:
      - max_trade_size: 10 ETH
      - require_2fa: true
      
  - name: mev_admin
    permissions:
      - all_operator_permissions
      - modify_strategies
      - view_wallets
      - configure_system
    restrictions:
      - require_hardware_key: true
      - ip_whitelist: ["10.0.0.0/8"]
      
  - name: compliance_officer
    permissions:
      - view_all_logs
      - generate_reports
      - freeze_operations
    restrictions:
      - read_only: true
      - audit_trail: enhanced
      
  - name: external_auditor
    permissions:
      - view_audit_logs
      - view_transactions
      - view_configurations
    restrictions:
      - time_based_access: true
      - data_export_disabled: true
```

### Authentication & Authorization

```python
# Multi-factor authentication implementation
import pyotp
import jwt
from datetime import datetime, timedelta

class SecureAuthManager:
    def __init__(self, secret_key):
        self.secret_key = secret_key
        self.token_expiry = timedelta(hours=8)
        
    def authenticate_user(self, username, password, totp_code, hardware_key=None):
        """Multi-factor authentication"""
        # Step 1: Validate credentials
        user = self.validate_credentials(username, password)
        if not user:
            self.log_failed_attempt(username)
            return None
            
        # Step 2: Validate TOTP
        if not self.validate_totp(user, totp_code):
            self.log_failed_mfa(user)
            return None
            
        # Step 3: Hardware key for admin roles
        if user['role'] in ['mev_admin', 'compliance_officer']:
            if not self.validate_hardware_key(user, hardware_key):
                self.log_failed_hardware_auth(user)
                return None
        
        # Generate session token
        token = self.generate_token(user)
        
        # Log successful authentication
        self.log_successful_auth(user)
        
        return token
    
    def generate_token(self, user):
        """Generate JWT token with claims"""
        payload = {
            'user_id': user['id'],
            'username': user['username'],
            'role': user['role'],
            'permissions': user['permissions'],
            'exp': datetime.utcnow() + self.token_expiry,
            'iat': datetime.utcnow(),
            'session_id': self.generate_session_id()
        }
        
        return jwt.encode(payload, self.secret_key, algorithm='HS256')
```

### Security Controls Matrix

| Control | Implementation | Monitoring | Testing Frequency |
|---------|---------------|------------|------------------|
| Encryption at Rest | AES-256 | Daily scans | Quarterly |
| Encryption in Transit | TLS 1.3 | Continuous | Monthly |
| Access Logging | All actions logged | Real-time alerts | Weekly |
| Vulnerability Scanning | Automated + Manual | Weekly reports | Weekly |
| Penetration Testing | Third-party | Annual report | Annually |
| Code Review | Peer review required | PR metrics | Per change |

---

## 🛡️ Data Protection & Privacy

### Data Classification

```yaml
data_classification:
  public:
    - description: "Non-sensitive operational data"
    - examples: ["System status", "Public blockchain data"]
    - controls: ["Basic access control"]
    
  internal:
    - description: "Internal operational data"
    - examples: ["Performance metrics", "Strategy names"]
    - controls: ["Authentication required", "Audit logging"]
    
  confidential:
    - description: "Sensitive business data"
    - examples: ["Profit data", "Strategy logic", "Wallet addresses"]
    - controls: ["Encryption", "Need-to-know access", "Enhanced logging"]
    
  restricted:
    - description: "Highly sensitive data"
    - examples: ["Private keys", "User credentials", "Compliance data"]
    - controls: ["HSM storage", "Multi-person control", "Continuous monitoring"]
```

### GDPR Compliance

```python
class GDPRCompliance:
    def __init__(self):
        self.retention_periods = {
            'transaction_data': 7 * 365,  # 7 years
            'log_data': 3 * 365,          # 3 years
            'user_data': 30,              # 30 days after deletion request
        }
    
    def handle_data_request(self, request_type, user_id):
        """Handle GDPR data requests"""
        if request_type == 'access':
            return self.export_user_data(user_id)
        elif request_type == 'deletion':
            return self.delete_user_data(user_id)
        elif request_type == 'portability':
            return self.export_portable_data(user_id)
        else:
            raise ValueError(f"Unknown request type: {request_type}")
    
    def anonymize_old_data(self):
        """Anonymize data past retention period"""
        cutoff_dates = {
            table: datetime.now() - timedelta(days=days)
            for table, days in self.retention_periods.items()
        }
        
        for table, cutoff in cutoff_dates.items():
            self.anonymize_table_data(table, cutoff)
    
    def anonymize_table_data(self, table, cutoff_date):
        """Anonymize PII in old records"""
        sql = f"""
        UPDATE {table}
        SET 
            user_id = 'ANONYMIZED_' || MD5(user_id::text),
            ip_address = '0.0.0.0',
            wallet_address = 'ANONYMIZED_' || SUBSTRING(wallet_address, 1, 10)
        WHERE created_at < %s
            AND anonymized = FALSE;
        """
        # Execute anonymization
```

---

## ⚠️ Risk Management

### Risk Register

| Risk ID | Category | Description | Impact | Likelihood | Mitigation |
|---------|----------|-------------|--------|------------|------------|
| R001 | Regulatory | New regulations limiting MEV | High | Medium | Legal monitoring, adaptable architecture |
| R002 | Technical | Smart contract vulnerability | Critical | Low | Audits, bug bounties, insurance |
| R003 | Operational | Key person dependency | High | Medium | Documentation, cross-training |
| R004 | Financial | Large trading loss | High | Low | Position limits, stop-loss mechanisms |
| R005 | Security | Private key compromise | Critical | Low | HSM, multi-sig, key rotation |
| R006 | Compliance | Audit failure | Medium | Low | Continuous monitoring, regular reviews |

### Risk Monitoring Dashboard

```python
class RiskMonitor:
    def __init__(self):
        self.risk_thresholds = {
            'max_position_size': 100,  # ETH
            'max_daily_loss': 10,      # ETH
            'min_success_rate': 0.8,   # 80%
            'max_gas_spend': 5,        # ETH per day
        }
        
    def continuous_risk_assessment(self):
        """Real-time risk monitoring"""
        while True:
            metrics = self.collect_metrics()
            
            # Check position size
            if metrics['current_position'] > self.risk_thresholds['max_position_size']:
                self.trigger_alert('POSITION_SIZE_EXCEEDED', metrics)
                self.enforce_position_limit()
            
            # Check daily P&L
            if metrics['daily_loss'] > self.risk_thresholds['max_daily_loss']:
                self.trigger_alert('DAILY_LOSS_LIMIT', metrics)
                self.pause_trading()
            
            # Check success rate
            if metrics['success_rate'] < self.risk_thresholds['min_success_rate']:
                self.trigger_alert('LOW_SUCCESS_RATE', metrics)
                self.review_strategies()
            
            time.sleep(60)  # Check every minute
```

---

## 📊 Compliance Monitoring

### Automated Compliance Checks

```sql
-- Daily compliance monitoring queries

-- 1. Check for unusual trading patterns
CREATE VIEW compliance_daily_summary AS
SELECT 
    DATE(timestamp) as trade_date,
    COUNT(*) as total_trades,
    SUM(profit_usd) as total_profit,
    AVG(profit_usd) as avg_profit,
    MAX(profit_usd) as max_profit,
    COUNT(DISTINCT wallet_address) as unique_wallets,
    COUNT(DISTINCT strategy_id) as strategies_used,
    SUM(CASE WHEN profit_usd > 10000 THEN 1 ELSE 0 END) as large_trades
FROM mev_transactions
WHERE timestamp >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(timestamp);

-- 2. Monitor access patterns
CREATE VIEW compliance_access_summary AS
SELECT 
    DATE(timestamp) as access_date,
    user_id,
    COUNT(*) as total_actions,
    COUNT(DISTINCT ip_address) as unique_ips,
    COUNT(DISTINCT action) as unique_actions,
    SUM(CASE WHEN result = 'failure' THEN 1 ELSE 0 END) as failed_actions
FROM audit_logs
WHERE timestamp >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(timestamp), user_id;

-- 3. Configuration change tracking
CREATE VIEW compliance_config_changes AS
SELECT 
    timestamp,
    user_id,
    resource_type,
    resource_id,
    old_value,
    new_value,
    pg_catalog.json_object_keys(new_value) as changed_keys
FROM audit_logs
WHERE event_type = 'configuration_change'
    AND timestamp >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY timestamp DESC;
```

### Compliance Dashboard

```html
<!DOCTYPE html>
<html>
<head>
    <title>MEV Compliance Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="dashboard">
        <h1>Compliance Monitoring Dashboard</h1>
        
        <!-- Risk Indicators -->
        <div class="risk-indicators">
            <div class="indicator" id="regulatory-risk">
                <h3>Regulatory Risk</h3>
                <span class="status">LOW</span>
            </div>
            <div class="indicator" id="operational-risk">
                <h3>Operational Risk</h3>
                <span class="status">MEDIUM</span>
            </div>
            <div class="indicator" id="security-risk">
                <h3>Security Risk</h3>
                <span class="status">LOW</span>
            </div>
        </div>
        
        <!-- Compliance Metrics -->
        <div class="metrics">
            <canvas id="complianceChart"></canvas>
        </div>
        
        <!-- Recent Alerts -->
        <div class="alerts">
            <h3>Recent Compliance Alerts</h3>
            <ul id="alert-list"></ul>
        </div>
    </div>
    
    <script>
    // Real-time compliance monitoring
    async function updateComplianceDashboard() {
        const response = await fetch('/api/compliance/metrics');
        const data = await response.json();
        
        // Update risk indicators
        updateRiskIndicators(data.risks);
        
        // Update charts
        updateComplianceChart(data.metrics);
        
        // Update alerts
        updateAlertsList(data.alerts);
    }
    
    // Update every 30 seconds
    setInterval(updateComplianceDashboard, 30000);
    </script>
</body>
</html>
```

---

## 🚨 Incident Management

### Incident Response Plan

```yaml
incident_response_plan:
  classification:
    - level: "Critical"
      description: "Service outage, data breach, major financial loss"
      response_time: "< 15 minutes"
      escalation: "Immediate to C-level"
      
    - level: "High"
      description: "Performance degradation, security alert"
      response_time: "< 1 hour"
      escalation: "Director level"
      
    - level: "Medium"
      description: "Non-critical issues, minor losses"
      response_time: "< 4 hours"
      escalation: "Team lead"
      
    - level: "Low"
      description: "Minor issues, no impact"
      response_time: "< 24 hours"
      escalation: "On-call engineer"
  
  procedures:
    - step: "Detection"
      actions:
        - "Automated monitoring alerts"
        - "Manual report submission"
        - "Audit log anomaly detection"
        
    - step: "Triage"
      actions:
        - "Assess impact and severity"
        - "Assign incident commander"
        - "Begin evidence collection"
        
    - step: "Containment"
      actions:
        - "Isolate affected systems"
        - "Prevent further damage"
        - "Maintain evidence integrity"
        
    - step: "Resolution"
      actions:
        - "Fix root cause"
        - "Verify resolution"
        - "Document actions taken"
        
    - step: "Recovery"
      actions:
        - "Restore normal operations"
        - "Monitor for recurrence"
        - "Update documentation"
        
    - step: "Post-Mortem"
      actions:
        - "Root cause analysis"
        - "Lessons learned"
        - "Process improvements"
```

### Incident Documentation Template

```markdown
# Incident Report

**Incident ID**: INC-2025-001
**Date**: July 11, 2025
**Severity**: High
**Status**: Resolved

## Summary
Brief description of the incident and its impact.

## Timeline
- **10:30 UTC**: Initial detection
- **10:35 UTC**: Incident confirmed
- **10:45 UTC**: Containment measures applied
- **11:30 UTC**: Root cause identified
- **12:00 UTC**: Fix deployed
- **12:30 UTC**: Normal operations restored

## Impact
- **Duration**: 2 hours
- **Affected Services**: MEV Detection Engine
- **Financial Impact**: $0 (prevented loss: ~$50,000)
- **Users Affected**: 0 (internal system)

## Root Cause
Detailed explanation of what caused the incident.

## Resolution
Steps taken to resolve the incident.

## Lessons Learned
1. What went well
2. What could be improved
3. Action items for prevention

## Follow-up Actions
- [ ] Update monitoring thresholds
- [ ] Implement additional safeguards
- [ ] Team training on scenario
```

---

## 🔄 Business Continuity

### Business Continuity Plan

```python
class BusinessContinuityManager:
    def __init__(self):
        self.rto_targets = {  # Recovery Time Objectives
            'critical': timedelta(minutes=15),
            'high': timedelta(hours=1),
            'medium': timedelta(hours=4),
            'low': timedelta(hours=24)
        }
        
        self.rpo_targets = {  # Recovery Point Objectives
            'transaction_data': timedelta(minutes=1),
            'configuration': timedelta(hours=1),
            'logs': timedelta(hours=24)
        }
    
    def disaster_recovery_test(self):
        """Quarterly DR test procedure"""
        test_results = {
            'test_id': f"DR-TEST-{datetime.now().strftime('%Y%m%d')}",
            'start_time': datetime.now(),
            'steps': []
        }
        
        # 1. Simulate primary site failure
        step1 = self.simulate_failure('primary_datacenter')
        test_results['steps'].append(step1)
        
        # 2. Activate secondary site
        step2 = self.activate_secondary_site()
        test_results['steps'].append(step2)
        
        # 3. Verify data integrity
        step3 = self.verify_data_integrity()
        test_results['steps'].append(step3)
        
        # 4. Test transaction processing
        step4 = self.test_transaction_processing()
        test_results['steps'].append(step4)
        
        # 5. Failback to primary
        step5 = self.failback_to_primary()
        test_results['steps'].append(step5)
        
        test_results['end_time'] = datetime.now()
        test_results['duration'] = test_results['end_time'] - test_results['start_time']
        
        return test_results
```

### Backup and Recovery Matrix

| Data Type | Backup Frequency | Retention | Storage Location | Recovery Method |
|-----------|-----------------|-----------|------------------|-----------------|
| Transaction Data | Real-time | 7 years | S3 + Glacier | Automated restore |
| Configuration | Hourly | 30 days | Git + S3 | Manual restore |
| Audit Logs | Real-time | 7 years | S3 + Glacier | Automated restore |
| System State | Daily | 7 days | EBS Snapshots | EC2 restore |
| Wallets/Keys | On change | Forever | HSM + Cold storage | Multi-party restore |

---

## 📋 Audit Procedures

### Internal Audit Schedule

```yaml
audit_schedule:
  daily:
    - name: "Access review"
      scope: "Failed login attempts, privilege escalations"
      automated: true
      
    - name: "Transaction monitoring"
      scope: "Large trades, unusual patterns"
      automated: true
      
  weekly:
    - name: "Configuration audit"
      scope: "System configurations, strategy parameters"
      automated: false
      reviewer: "Team Lead"
      
    - name: "Security scan"
      scope: "Vulnerabilities, patches"
      automated: true
      
  monthly:
    - name: "Compliance review"
      scope: "Regulatory requirements, policies"
      automated: false
      reviewer: "Compliance Officer"
      
    - name: "Access certification"
      scope: "User permissions, role assignments"
      automated: false
      reviewer: "Security Team"
      
  quarterly:
    - name: "Full system audit"
      scope: "Complete infrastructure and processes"
      automated: false
      reviewer: "Internal Audit Team"
      
    - name: "DR test"
      scope: "Disaster recovery procedures"
      automated: false
      reviewer: "Operations Team"
      
  annually:
    - name: "External audit"
      scope: "SOC 2, financial controls"
      automated: false
      reviewer: "External Auditor"
```

### Audit Checklist

```python
class AuditChecklist:
    def __init__(self):
        self.checks = {
            'access_control': [
                "Verify all users have appropriate roles",
                "Check for orphaned accounts",
                "Review privileged access",
                "Validate MFA enforcement"
            ],
            'data_security': [
                "Verify encryption at rest",
                "Check TLS configurations",
                "Review key rotation logs",
                "Validate backup encryption"
            ],
            'operational': [
                "Review change management logs",
                "Check monitoring coverage",
                "Validate alert configurations",
                "Review incident responses"
            ],
            'compliance': [
                "Check regulatory reporting",
                "Review audit log integrity",
                "Validate retention policies",
                "Check data anonymization"
            ]
        }
    
    def execute_audit(self, audit_type):
        """Execute audit checklist"""
        results = {
            'audit_id': self.generate_audit_id(),
            'type': audit_type,
            'date': datetime.now(),
            'findings': []
        }
        
        for category, checks in self.checks.items():
            for check in checks:
                result = self.perform_check(category, check)
                results['findings'].append({
                    'category': category,
                    'check': check,
                    'result': result['status'],
                    'details': result['details'],
                    'evidence': result['evidence']
                })
        
        # Generate audit report
        self.generate_report(results)
        
        return results
```

### Compliance Reporting

```sql
-- Generate compliance reports

-- Monthly compliance summary
CREATE OR REPLACE FUNCTION generate_compliance_report(
    report_month DATE
) RETURNS TABLE (
    metric_name TEXT,
    metric_value NUMERIC,
    status TEXT,
    notes TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH monthly_metrics AS (
        SELECT
            COUNT(*) as total_transactions,
            SUM(profit_usd) as total_profit,
            AVG(success_rate) as avg_success_rate,
            COUNT(DISTINCT user_id) as unique_users,
            SUM(CASE WHEN profit_usd > 10000 THEN 1 ELSE 0 END) as large_trades
        FROM mev_transactions
        WHERE DATE_TRUNC('month', timestamp) = DATE_TRUNC('month', report_month)
    ),
    security_metrics AS (
        SELECT
            COUNT(*) as total_incidents,
            SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) as critical_incidents,
            AVG(resolution_time_hours) as avg_resolution_time
        FROM security_incidents
        WHERE DATE_TRUNC('month', timestamp) = DATE_TRUNC('month', report_month)
    )
    SELECT 
        'Total Transactions' as metric_name,
        total_transactions as metric_value,
        CASE WHEN total_transactions > 0 THEN 'PASS' ELSE 'FAIL' END as status,
        'Monthly transaction volume' as notes
    FROM monthly_metrics
    
    UNION ALL
    
    SELECT 
        'Reportable Trades',
        large_trades,
        'INFO',
        'Trades over $10,000 requiring reporting'
    FROM monthly_metrics
    
    UNION ALL
    
    SELECT 
        'Security Incidents',
        total_incidents,
        CASE WHEN critical_incidents = 0 THEN 'PASS' ELSE 'FAIL' END,
        'Total security incidents in period'
    FROM security_metrics;
END;
$$ LANGUAGE plpgsql;
```

---

## 📊 Compliance Metrics Dashboard

### Key Compliance Indicators

```python
class ComplianceMetrics:
    def __init__(self):
        self.kpis = {
            'audit_completion_rate': {
                'target': 100,
                'calculation': 'completed_audits / scheduled_audits * 100'
            },
            'incident_response_time': {
                'target': 15,  # minutes for critical
                'calculation': 'average(detection_time, response_start)'
            },
            'access_review_completion': {
                'target': 100,
                'calculation': 'reviewed_accounts / total_accounts * 100'
            },
            'training_completion': {
                'target': 100,
                'calculation': 'trained_employees / total_employees * 100'
            },
            'data_retention_compliance': {
                'target': 100,
                'calculation': 'compliant_records / total_records * 100'
            }
        }
    
    def calculate_compliance_score(self):
        """Calculate overall compliance score"""
        scores = []
        
        for kpi, config in self.kpis.items():
            actual = self.get_actual_value(kpi)
            target = config['target']
            score = min(100, (actual / target) * 100)
            scores.append(score)
        
        overall_score = sum(scores) / len(scores)
        
        return {
            'overall_score': overall_score,
            'individual_scores': dict(zip(self.kpis.keys(), scores)),
            'rating': self.get_rating(overall_score)
        }
    
    def get_rating(self, score):
        """Convert score to rating"""
        if score >= 95:
            return 'Excellent'
        elif score >= 85:
            return 'Good'
        elif score >= 75:
            return 'Satisfactory'
        else:
            return 'Needs Improvement'
```

---

## 📝 Compliance Certification

### Attestation Statement

> I hereby certify that the MEV Infrastructure has been designed, implemented, and is operated in accordance with applicable compliance requirements including but not limited to:
> 
> - Financial regulatory requirements
> - Data protection regulations (GDPR)
> - Security best practices (ISO 27001)
> - Internal control frameworks (SOC 2)
> 
> All controls described in this documentation are operational and effective as of the date of this certification.
> 
> **Certified by**: Chief Compliance Officer
> **Date**: July 11, 2025
> **Next Review**: October 11, 2025

---

*This compliance and audit documentation provides comprehensive coverage of regulatory requirements, security controls, and operational procedures for the MEV infrastructure. Regular reviews and updates ensure continued compliance with evolving regulations and industry standards.*