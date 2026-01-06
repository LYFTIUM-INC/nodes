# MEV Infrastructure: Operations & Deployment Guide

## Pre-Production Checklist

### Infrastructure Requirements ✅

#### Hardware Specifications
- [ ] **CPU**: Intel Xeon or AMD EPYC (32+ cores recommended)
- [ ] **Memory**: 128GB RAM minimum (256GB for high-frequency trading)
- [ ] **Storage**: 4TB NVMe SSD in RAID 10 configuration
- [ ] **Network**: 10Gbps dedicated connection with low latency routing
- [ ] **GPU**: Optional NVIDIA RTX 4090 for ML acceleration
- [ ] **Power**: Redundant power supplies with UPS backup

#### Software Environment
- [ ] **OS**: Ubuntu 22.04 LTS with kernel 5.15+
- [ ] **Docker**: Version 24.0+ with buildx support
- [ ] **Kubernetes**: Version 1.28+ with ingress controller
- [ ] **Database**: PostgreSQL 15+ with TimescaleDB extension
- [ ] **Cache**: Redis 7.2+ cluster mode
- [ ] **Monitoring**: Prometheus + Grafana stack

### Security Configuration ✅

#### Network Security
- [ ] **Firewall**: UFW configured with minimal open ports
- [ ] **VPN**: WireGuard VPN for secure administrative access
- [ ] **DDoS Protection**: Cloudflare Enterprise with custom rules
- [ ] **SSL/TLS**: Let's Encrypt with automatic renewal
- [ ] **IP Whitelisting**: Configured for API access

#### Application Security
- [ ] **API Keys**: Generated with proper scoping and rotation
- [ ] **JWT Secrets**: 256-bit entropy, rotated monthly
- [ ] **Database**: Encrypted at rest with TDE
- [ ] **Secrets Management**: HashiCorp Vault integration
- [ ] **Audit Logging**: Centralized logging with retention policy

#### Smart Contract Security
- [ ] **Contract Audits**: Completed by 3 independent firms
- [ ] **Multi-sig Wallets**: 3-of-5 multi-signature configuration
- [ ] **Emergency Pause**: Circuit breaker mechanisms tested
- [ ] **Upgrade Mechanism**: Transparent proxy pattern implemented
- [ ] **Insurance**: Smart contract insurance coverage

### Blockchain Node Configuration ✅

#### Primary Nodes
```yaml
ethereum_node:
  provider: "Alchemy/Infura"
  endpoint: "wss://eth-mainnet.g.alchemy.com/v2/{API_KEY}"
  backup_endpoint: "wss://mainnet.infura.io/ws/v3/{PROJECT_ID}"
  sync_mode: "full"
  pruning: false
  cache_size: "16GB"

polygon_node:
  provider: "QuickNode"
  endpoint: "wss://polygon-mainnet.quicknode.com/{TOKEN}"
  backup_endpoint: "wss://polygon-rpc.com"
  sync_mode: "full"
  pruning: true
  cache_size: "8GB"

arbitrum_node:
  provider: "Alchemy"
  endpoint: "wss://arb-mainnet.g.alchemy.com/v2/{API_KEY}"
  backup_endpoint: "wss://arb1.arbitrum.io/ws"
  sync_mode: "full"
  pruning: true
  cache_size: "4GB"
```

#### Node Monitoring
- [ ] **Health Checks**: Every 30 seconds with auto-failover
- [ ] **Sync Status**: Real-time monitoring of block height
- [ ] **Connection Pool**: Managed connections with circuit breakers
- [ ] **Rate Limiting**: Configured per provider limits
- [ ] **Backup Strategy**: Automatic failover to backup providers

## Deployment Procedures

### 1. Database Setup

```bash
#!/bin/bash
# Database initialization script

set -euo pipefail

# Create TimescaleDB instance
docker run -d \
  --name mev-postgres \
  -e POSTGRES_DB=mev_infrastructure \
  -e POSTGRES_USER=mev_user \
  -e POSTGRES_PASSWORD=${DB_PASSWORD} \
  -v /data/postgres:/var/lib/postgresql/data \
  -p 5432:5432 \
  timescale/timescaledb:latest-pg15

# Wait for database to be ready
until docker exec mev-postgres pg_isready -U mev_user -d mev_infrastructure; do
  echo "Waiting for database..."
  sleep 2
done

# Run migrations
cd /opt/mev-infrastructure
npm run migrate:production

# Create partitions
psql -h localhost -U mev_user -d mev_infrastructure << EOF
-- Create monthly partitions for opportunities table
SELECT create_monthly_partitions('opportunities', '2024-01-01', '2025-12-31');

-- Create indexes
CREATE INDEX CONCURRENTLY opportunities_profit_idx 
ON opportunities (profit_estimate DESC, created_at DESC)
WHERE status = 'detected';

-- Set up automated partition management
SELECT add_retention_policy('market_data', INTERVAL '30 days');
EOF

echo "Database setup completed successfully"
```

### 2. Backend Deployment

```bash
#!/bin/bash
# OCaml backend deployment

set -euo pipefail

echo "Building OCaml MEV Engine..."

cd /opt/mev-infrastructure/backend/ocaml

# Install dependencies
opam install --deps-only .

# Build with optimizations
dune build --profile=release

# Run tests
dune test

# Create systemd service
sudo tee /etc/systemd/system/mev-engine.service > /dev/null << EOF
[Unit]
Description=MEV Engine Backend
After=network.target postgresql.service redis.service
Requires=postgresql.service redis.service

[Service]
Type=simple
User=mev
Group=mev
WorkingDirectory=/opt/mev-infrastructure/backend/ocaml
ExecStart=/opt/mev-infrastructure/backend/ocaml/_build/default/bin/main.exe
Restart=always
RestartSec=10
Environment=OCAMLRUNPARAM=h=1G,s=4M
Environment=MALLOC_ARENA_MAX=2
LimitNOFILE=65536
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable mev-engine
sudo systemctl start mev-engine

echo "OCaml backend deployed successfully"
```

### 3. API Proxy Deployment

```bash
#!/bin/bash
# FastAPI proxy deployment

set -euo pipefail

echo "Deploying FastAPI Proxy..."

cd /opt/mev-infrastructure/api

# Build Docker image
docker build -t mev-api:latest .

# Deploy with Docker Compose
cat > docker-compose.prod.yml << EOF
version: '3.8'

services:
  mev-api:
    image: mev-api:latest
    restart: always
    ports:
      - "8091:8000"
    environment:
      - ENVIRONMENT=production
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_URL=${REDIS_URL}
      - JWT_SECRET=${JWT_SECRET}
      - LOG_LEVEL=info
    depends_on:
      - redis
    volumes:
      - ./logs:/app/logs
    networks:
      - mev-network

  redis:
    image: redis:7.2-alpine
    restart: always
    command: redis-server --appendonly yes --maxmemory 4gb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    networks:
      - mev-network

volumes:
  redis_data:

networks:
  mev-network:
    driver: bridge
EOF

docker-compose -f docker-compose.prod.yml up -d

echo "FastAPI proxy deployed successfully"
```

### 4. Frontend Deployment

```bash
#!/bin/bash
# Next.js frontend deployment

set -euo pipefail

echo "Building and deploying Next.js frontend..."

cd /opt/mev-infrastructure/ui

# Install dependencies
npm ci --production

# Build application
npm run build

# Configure Nginx
sudo tee /etc/nginx/sites-available/mev-frontend > /dev/null << EOF
server {
    listen 80;
    listen [::]:80;
    server_name mev-dashboard.yourdomain.com;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name mev-dashboard.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/mev-dashboard.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mev-dashboard.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    location /ws {
        proxy_pass http://localhost:8091;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable site
sudo ln -sf /etc/nginx/sites-available/mev-frontend /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Create PM2 ecosystem file
cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'mev-frontend',
    script: 'npm',
    args: 'start',
    cwd: '/opt/mev-infrastructure/ui',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    log_file: '/var/log/mev-frontend.log',
    error_file: '/var/log/mev-frontend-error.log',
    out_file: '/var/log/mev-frontend-out.log',
    merge_logs: true,
    max_memory_restart: '1G'
  }]
};
EOF

# Start with PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup

echo "Frontend deployed successfully"
```

## Monitoring Setup

### 1. Prometheus Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "mev_alerts.yml"

scrape_configs:
  - job_name: 'mev-api'
    static_configs:
      - targets: ['localhost:8091']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'mev-engine'
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['localhost:9187']

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093
```

### 2. Grafana Dashboards

```json
{
  "dashboard": {
    "title": "MEV Infrastructure Overview",
    "panels": [
      {
        "title": "MEV Opportunities Detected",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(mev_opportunities_total[5m])",
            "legendFormat": "{{strategy}}"
          }
        ]
      },
      {
        "title": "Execution Success Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(mev_executions_success_total[5m]) / rate(mev_executions_total[5m]) * 100"
          }
        ]
      },
      {
        "title": "Profit Over Time",
        "type": "graph",
        "targets": [
          {
            "expr": "increase(mev_profit_usd_total[1h])",
            "legendFormat": "Hourly Profit"
          }
        ]
      },
      {
        "title": "API Response Times",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(api_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      }
    ]
  }
}
```

### 3. Alert Rules

```yaml
# mev_alerts.yml
groups:
  - name: mev.rules
    rules:
      - alert: HighErrorRate
        expr: rate(api_requests_failed_total[5m]) / rate(api_requests_total[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }}% over the last 5 minutes"

      - alert: LowProfitability
        expr: rate(mev_profit_usd_total[1h]) < 1000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Profitability below threshold"
          description: "Hourly profit is ${{ $value }}, below $1000 threshold"

      - alert: DatabaseConnectionIssue
        expr: up{job="postgres-exporter"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Database connection lost"
          description: "PostgreSQL database is not responding"

      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(api_request_duration_seconds_bucket[5m])) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High API latency"
          description: "95th percentile latency is {{ $value }}s"
```

## Operational Procedures

### Daily Operations Checklist

#### Morning Checks (9:00 AM UTC)
- [ ] **System Health**: Verify all services are running
- [ ] **Node Status**: Check blockchain node synchronization
- [ ] **Database**: Review performance metrics and slow queries
- [ ] **Profit Analysis**: Review previous 24h performance
- [ ] **Error Logs**: Check for any critical errors or warnings

#### Afternoon Review (2:00 PM UTC)
- [ ] **Market Analysis**: Review market conditions and opportunities
- [ ] **Performance**: Check API response times and throughput
- [ ] **Security**: Review access logs for suspicious activity
- [ ] **Capacity**: Monitor resource utilization trends

#### Evening Wrap-up (8:00 PM UTC)
- [ ] **Backup Verification**: Ensure database backups completed
- [ ] **Strategy Performance**: Analyze strategy effectiveness
- [ ] **Tomorrow's Prep**: Review scheduled maintenance or updates

### Incident Response Procedures

#### Severity Classification

**Critical (P1)**
- System completely down
- Security breach detected
- Data corruption/loss
- Major profit loss (>$10k/hour)

**High (P2)**
- Significant performance degradation
- Single service failure with workaround
- Moderate profit impact ($1k-$10k)

**Medium (P3)**
- Minor performance issues
- Non-critical feature failure
- Alert threshold breached

**Low (P4)**
- Cosmetic issues
- Documentation updates
- Enhancement requests

#### Response Procedures

```bash
#!/bin/bash
# Emergency response script

INCIDENT_TYPE=$1
SEVERITY=$2

case $SEVERITY in
  "P1")
    echo "CRITICAL INCIDENT - Immediate response required"
    # Alert on-call team
    curl -X POST ${PAGERDUTY_URL} -d "{\"incident_key\": \"$(date +%s)\", \"service_key\": \"${SERVICE_KEY}\", \"event_type\": \"trigger\", \"description\": \"Critical MEV Infrastructure Issue\"}"
    
    # Emergency pause trading
    curl -X POST ${API_BASE_URL}/emergency/pause -H "Authorization: Bearer ${EMERGENCY_TOKEN}"
    
    # Capture system state
    docker ps > /tmp/incident_containers.log
    systemctl status > /tmp/incident_services.log
    ;;
    
  "P2")
    echo "HIGH PRIORITY - Response within 30 minutes"
    # Slack notification
    curl -X POST ${SLACK_WEBHOOK} -d "{\"text\": \"High priority MEV incident: ${INCIDENT_TYPE}\"}"
    ;;
    
  *)
    echo "Standard incident response"
    ;;
esac
```

### Backup and Recovery

#### Automated Backup Script

```bash
#!/bin/bash
# Daily backup script

BACKUP_DIR="/backup/$(date +%Y-%m-%d)"
mkdir -p ${BACKUP_DIR}

# Database backup
pg_dump -h localhost -U mev_user mev_infrastructure | gzip > ${BACKUP_DIR}/database.sql.gz

# Configuration backup
tar -czf ${BACKUP_DIR}/config.tar.gz /opt/mev-infrastructure/config/

# Log backup
tar -czf ${BACKUP_DIR}/logs.tar.gz /var/log/mev-*

# Upload to S3
aws s3 sync ${BACKUP_DIR} s3://mev-infrastructure-backups/$(date +%Y-%m-%d)/

# Cleanup old backups (keep 30 days)
find /backup/ -type d -mtime +30 -exec rm -rf {} \;

echo "Backup completed: ${BACKUP_DIR}"
```

#### Recovery Procedures

```bash
#!/bin/bash
# Recovery script

BACKUP_DATE=$1

if [ -z "$BACKUP_DATE" ]; then
  echo "Usage: $0 YYYY-MM-DD"
  exit 1
fi

echo "Starting recovery from backup: $BACKUP_DATE"

# Stop services
systemctl stop mev-engine
docker-compose down

# Download backup from S3
aws s3 sync s3://mev-infrastructure-backups/${BACKUP_DATE}/ /tmp/recovery/

# Restore database
dropdb mev_infrastructure
createdb mev_infrastructure
gunzip -c /tmp/recovery/database.sql.gz | psql -h localhost -U mev_user mev_infrastructure

# Restore configuration
tar -xzf /tmp/recovery/config.tar.gz -C /

# Start services
docker-compose up -d
systemctl start mev-engine

echo "Recovery completed successfully"
```

## Performance Optimization

### System Tuning

```bash
#!/bin/bash
# System optimization script

# Kernel parameters for high-performance networking
cat >> /etc/sysctl.conf << EOF
# Network optimization
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 65536 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000

# File system optimization
fs.file-max = 2097152
fs.nr_open = 1048576

# Virtual memory optimization
vm.swappiness = 1
vm.dirty_ratio = 80
vm.dirty_background_ratio = 5
EOF

sysctl -p

# Increase file descriptor limits
cat >> /etc/security/limits.conf << EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
EOF

# CPU frequency scaling
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Disable unnecessary services
systemctl disable bluetooth
systemctl disable cups
systemctl disable avahi-daemon

echo "System optimization completed"
```

### Database Optimization

```sql
-- PostgreSQL optimization for MEV workload

-- Connection settings
ALTER SYSTEM SET max_connections = 1000;
ALTER SYSTEM SET shared_buffers = '32GB';
ALTER SYSTEM SET effective_cache_size = '96GB';
ALTER SYSTEM SET work_mem = '256MB';
ALTER SYSTEM SET maintenance_work_mem = '2GB';

-- Write optimization
ALTER SYSTEM SET wal_buffers = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET max_wal_size = '16GB';
ALTER SYSTEM SET min_wal_size = '4GB';

-- Query optimization
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET max_worker_processes = 16;
ALTER SYSTEM SET max_parallel_workers_per_gather = 8;

-- Logging optimization
ALTER SYSTEM SET log_min_duration_statement = 1000;
ALTER SYSTEM SET log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ';
ALTER SYSTEM SET log_checkpoints = on;
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;

-- Reload configuration
SELECT pg_reload_conf();

-- Create optimized indexes
CREATE INDEX CONCURRENTLY opportunities_strategy_profit_idx 
ON opportunities (strategy_type, profit_estimate DESC, created_at DESC) 
WHERE status = 'detected';

CREATE INDEX CONCURRENTLY market_data_time_token_idx 
ON market_data (time DESC, token_address, dex_address);

-- Set up automatic vacuum
ALTER TABLE opportunities SET (
  autovacuum_vacuum_scale_factor = 0.1,
  autovacuum_analyze_scale_factor = 0.05
);
```

This comprehensive operations guide provides everything needed to deploy, monitor, and maintain the MEV infrastructure in production. The procedures ensure maximum uptime, performance, and security while providing clear escalation paths for incident response.