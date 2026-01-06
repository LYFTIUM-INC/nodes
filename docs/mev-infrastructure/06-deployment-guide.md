# Deployment Guide - MEV Infrastructure Platform

## Overview

This comprehensive deployment guide provides step-by-step instructions for deploying the MEV Infrastructure Platform in production environments. Following Fortune 500 deployment standards, this guide ensures reliable, secure, and scalable deployment.

## Prerequisites

### Hardware Requirements

#### Minimum Production Specifications

```
Production Server Requirements:
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│ Component       │ Minimum         │ Recommended     │ Enterprise      │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ CPU             │ 16 cores        │ 32 cores        │ 64 cores        │
│ RAM             │ 64 GB           │ 128 GB          │ 256 GB          │
│ Storage (SSD)   │ 2 TB NVMe       │ 4 TB NVMe       │ 8 TB NVMe       │
│ Network         │ 1 Gbps         │ 10 Gbps        │ 25 Gbps        │
│ Redundancy      │ Single          │ Hot standby     │ Active-active   │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

#### Network Requirements

- **Latency**: <5ms to major cloud providers (AWS, GCP, Azure)
- **Bandwidth**: Minimum 1Gbps sustained, 10Gbps burst
- **Peering**: Direct connection to blockchain infrastructure providers
- **Redundancy**: Multiple ISP connections for failover

### Software Dependencies

#### Base System Requirements

```bash
# Operating System
Ubuntu 22.04 LTS (recommended) or CentOS 8+

# Docker & Container Runtime
Docker Engine 24.0+
Docker Compose 2.20+

# Programming Languages
Python 3.11+
Node.js 18 LTS+
Go 1.21+ (for some utilities)

# Database Systems
PostgreSQL 15+
Redis 7.0+
InfluxDB 2.7+

# Monitoring Stack
Prometheus 2.45+
Grafana 10.0+
AlertManager 0.26+
```

## Environment Setup

### 1. System Preparation

#### Initial Server Configuration

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y curl wget git vim htop iotop nethogs \
    build-essential software-properties-common apt-transport-https \
    ca-certificates gnupg lsb-release

# Configure system limits
cat >> /etc/security/limits.conf << EOF
*               soft    nofile          65536
*               hard    nofile          65536
*               soft    nproc           32768
*               hard    nproc           32768
EOF

# Configure kernel parameters for high-performance networking
cat >> /etc/sysctl.conf << EOF
# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
EOF

# Apply kernel parameters
sudo sysctl -p
```

#### Docker Installation

```bash
# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Docker daemon for production
sudo mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "127.0.0.1:9323",
  "default-ulimits": {
    "nofile": {
      "Hard": 64000,
      "Name": "nofile",
      "Soft": 64000
    }
  }
}
EOF

sudo systemctl enable docker
sudo systemctl restart docker
```

### 2. Directory Structure Setup

```bash
# Create application directory structure
sudo mkdir -p /opt/mev-platform/{
  config,
  data/{postgresql,redis,influxdb,logs},
  scripts,
  backups,
  ssl,
  monitoring
}

# Set proper permissions
sudo chown -R $USER:docker /opt/mev-platform
sudo chmod -R 755 /opt/mev-platform
```

## Configuration Management

### 1. Environment Configuration

#### Production Environment Variables

```bash
# Create environment configuration
cat > /opt/mev-platform/config/.env.production << EOF
# Application Configuration
ENV=production
DEBUG=false
LOG_LEVEL=INFO

# Database Configuration
DATABASE_URL=postgresql://mev_user:secure_password@localhost:5432/mev_production
REDIS_URL=redis://localhost:6379/0
INFLUXDB_URL=http://localhost:8086
INFLUXDB_TOKEN=your_influxdb_token
INFLUXDB_ORG=mev-platform
INFLUXDB_BUCKET=mev-metrics

# Blockchain Configuration
ETHEREUM_RPC_URL=http://localhost:8545
ARBITRUM_RPC_URL=http://localhost:8590
OPTIMISM_RPC_URL=http://localhost:8546
POLYGON_RPC_URL=http://localhost:8551
BASE_RPC_URL=http://localhost:8552

# MEV Configuration
MEV_PRIVATE_KEY=your_private_key_here
FLASHBOTS_RELAY_URL=https://relay.flashbots.net
BUILDER_API_URL=https://api.blocknative.com

# Security Configuration
JWT_SECRET=your_jwt_secret_here
API_RATE_LIMIT=1000
CORS_ORIGINS=https://dashboard.yourdomain.com

# Monitoring Configuration
PROMETHEUS_URL=http://localhost:9090
GRAFANA_URL=http://localhost:3000
ALERT_WEBHOOK_URL=https://hooks.slack.com/your-webhook

# Performance Configuration
MAX_WORKERS=8
POOL_SIZE=20
CACHE_TTL=300
BATCH_SIZE=100
EOF

# Secure the environment file
chmod 600 /opt/mev-platform/config/.env.production
```

#### Application Configuration

```bash
# Create main configuration file
cat > /opt/mev-platform/config/production.toml << EOF
[application]
name = "MEV Infrastructure Platform"
version = "2.1.4"
environment = "production"
debug = false

[server]
host = "0.0.0.0"
port = 8080
workers = 8
max_connections = 1000
timeout = 30
keepalive = 60

[database]
url = "postgresql://mev_user:secure_password@postgres:5432/mev_production"
pool_size = 20
max_overflow = 30
pool_timeout = 30
pool_recycle = 3600

[redis]
url = "redis://redis:6379/0"
pool_size = 10
socket_timeout = 5
socket_connect_timeout = 5

[blockchain]
ethereum = { rpc_url = "http://ethereum:8545", ws_url = "ws://ethereum:8546", chain_id = 1 }
arbitrum = { rpc_url = "http://arbitrum:8590", ws_url = "ws://arbitrum:8591", chain_id = 42161 }
optimism = { rpc_url = "http://optimism:8546", ws_url = "ws://optimism:8547", chain_id = 10 }

[mev]
strategies = ["arbitrage", "liquidation"]
max_position_size = 10.0
min_profit_threshold = 50.0
gas_price_multiplier = 1.1
slippage_tolerance = 0.005

[monitoring]
metrics_interval = 5
health_check_interval = 10
alert_threshold = 0.9
prometheus_enabled = true
grafana_enabled = true

[security]
jwt_expiration = 900
max_login_attempts = 5
rate_limit_per_minute = 1000
cors_allowed_origins = ["https://dashboard.yourdomain.com"]
EOF
```

### 2. Docker Compose Configuration

#### Main Docker Compose File

```yaml
# /opt/mev-platform/docker-compose.yml
version: '3.8'

services:
  # MEV Application Services
  mev-api:
    image: mev-platform/api:2.1.4
    container_name: mev-api
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - ENV=production
    env_file:
      - ./config/.env.production
    volumes:
      - ./config:/app/config:ro
      - ./data/logs:/app/logs
    depends_on:
      - postgres
      - redis
      - influxdb
    networks:
      - mev-network
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
        reservations:
          cpus: '2.0'
          memory: 4G
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  mev-engine:
    image: mev-platform/engine:2.1.4
    container_name: mev-engine
    restart: unless-stopped
    environment:
      - ENV=production
    env_file:
      - ./config/.env.production
    volumes:
      - ./config:/app/config:ro
      - ./data/logs:/app/logs
    depends_on:
      - postgres
      - redis
    networks:
      - mev-network
    deploy:
      resources:
        limits:
          cpus: '8.0'
          memory: 16G
        reservations:
          cpus: '4.0'
          memory: 8G

  mev-monitor:
    image: mev-platform/monitor:2.1.4
    container_name: mev-monitor
    restart: unless-stopped
    environment:
      - ENV=production
    env_file:
      - ./config/.env.production
    volumes:
      - ./config:/app/config:ro
      - ./data/logs:/app/logs
    depends_on:
      - postgres
      - redis
      - influxdb
    networks:
      - mev-network
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G

  # Database Services
  postgres:
    image: postgres:15-alpine
    container_name: mev-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: mev_production
      POSTGRES_USER: mev_user
      POSTGRES_PASSWORD: secure_password
    volumes:
      - ./data/postgresql:/var/lib/postgresql/data
      - ./scripts/init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro
    networks:
      - mev-network
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
        reservations:
          cpus: '2.0'
          memory: 4G
    command: >
      postgres
      -c shared_buffers=2GB
      -c effective_cache_size=6GB
      -c maintenance_work_mem=512MB
      -c checkpoint_completion_target=0.9
      -c wal_buffers=16MB
      -c default_statistics_target=100
      -c random_page_cost=1.1
      -c effective_io_concurrency=200
      -c work_mem=4MB
      -c min_wal_size=1GB
      -c max_wal_size=4GB

  redis:
    image: redis:7-alpine
    container_name: mev-redis
    restart: unless-stopped
    command: >
      redis-server
      --maxmemory 4gb
      --maxmemory-policy allkeys-lru
      --appendonly yes
      --appendfsync everysec
    volumes:
      - ./data/redis:/data
    networks:
      - mev-network
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G

  influxdb:
    image: influxdb:2.7-alpine
    container_name: mev-influxdb
    restart: unless-stopped
    environment:
      DOCKER_INFLUXDB_INIT_MODE: setup
      DOCKER_INFLUXDB_INIT_USERNAME: admin
      DOCKER_INFLUXDB_INIT_PASSWORD: secure_password
      DOCKER_INFLUXDB_INIT_ORG: mev-platform
      DOCKER_INFLUXDB_INIT_BUCKET: mev-metrics
    volumes:
      - ./data/influxdb:/var/lib/influxdb2
    networks:
      - mev-network
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G

  # Monitoring Services
  prometheus:
    image: prom/prometheus:v2.45.0
    container_name: mev-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./data/prometheus:/prometheus
    networks:
      - mev-network
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=90d'
      - '--web.enable-lifecycle'

  grafana:
    image: grafana/grafana:10.0.0
    container_name: mev-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: secure_password
      GF_INSTALL_PLUGINS: grafana-clock-panel,grafana-simple-json-datasource
    volumes:
      - ./data/grafana:/var/lib/grafana
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./monitoring/grafana/datasources:/etc/grafana/provisioning/datasources
    networks:
      - mev-network

  # Load Balancer
  nginx:
    image: nginx:alpine
    container_name: mev-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - mev-api
    networks:
      - mev-network

networks:
  mev-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  postgres_data:
  redis_data:
  influxdb_data:
  prometheus_data:
  grafana_data:
```

## Deployment Process

### 1. Initial Deployment

#### Clone and Setup Repository

```bash
# Clone the MEV platform repository
git clone https://github.com/your-org/mev-infrastructure.git /opt/mev-platform
cd /opt/mev-platform

# Checkout production branch
git checkout production

# Copy environment configuration
cp config/.env.example config/.env.production
# Edit the configuration file with production values
vim config/.env.production
```

#### Database Initialization

```bash
# Create database initialization script
cat > /opt/mev-platform/scripts/init-db.sql << EOF
-- Create application database
CREATE DATABASE mev_production;

-- Create application user
CREATE USER mev_user WITH PASSWORD 'secure_password';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE mev_production TO mev_user;

-- Connect to application database
\c mev_production;

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS trading;
CREATE SCHEMA IF NOT EXISTS monitoring;
CREATE SCHEMA IF NOT EXISTS audit;

-- Grant schema privileges
GRANT ALL ON SCHEMA trading TO mev_user;
GRANT ALL ON SCHEMA monitoring TO mev_user;
GRANT ALL ON SCHEMA audit TO mev_user;
EOF
```

#### SSL Certificate Setup

```bash
# Generate SSL certificates (or use your existing certificates)
mkdir -p /opt/mev-platform/ssl

# Self-signed certificate for testing (replace with proper certificates in production)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/mev-platform/ssl/private.key \
  -out /opt/mev-platform/ssl/certificate.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=yourdomain.com"

# Set proper permissions
chmod 600 /opt/mev-platform/ssl/private.key
chmod 644 /opt/mev-platform/ssl/certificate.crt
```

### 2. Configuration Files

#### Nginx Configuration

```bash
cat > /opt/mev-platform/config/nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream mev_api {
        least_conn;
        server mev-api:8080 max_fails=3 fail_timeout=30s;
    }

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;

    server {
        listen 80;
        server_name yourdomain.com;
        return 301 https://\$server_name\$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name yourdomain.com;

        ssl_certificate /etc/nginx/ssl/certificate.crt;
        ssl_certificate_key /etc/nginx/ssl/private.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
        ssl_prefer_server_ciphers off;

        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";

        location / {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://mev_api;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
        }

        location /ws {
            proxy_pass http://mev_api;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location /health {
            access_log off;
            proxy_pass http://mev_api/health;
        }
    }
}
EOF
```

#### Prometheus Configuration

```bash
mkdir -p /opt/mev-platform/monitoring
cat > /opt/mev-platform/monitoring/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  - job_name: 'mev-platform'
    static_configs:
      - targets: ['mev-api:8080', 'mev-engine:8081', 'mev-monitor:8082']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis-exporter'
    static_configs:
      - targets: ['redis-exporter:9121']
EOF
```

### 3. Service Deployment

#### Deploy Infrastructure Services

```bash
# Start infrastructure services first
cd /opt/mev-platform
docker-compose up -d postgres redis influxdb

# Wait for databases to be ready
sleep 30

# Check database connectivity
docker-compose exec postgres pg_isready -U mev_user
docker-compose exec redis redis-cli ping
```

#### Deploy Application Services

```bash
# Build application images
docker-compose build

# Start application services
docker-compose up -d mev-api mev-engine mev-monitor

# Start monitoring services
docker-compose up -d prometheus grafana

# Start load balancer
docker-compose up -d nginx

# Verify all services are running
docker-compose ps
```

### 4. Post-Deployment Verification

#### Health Checks

```bash
# API health check
curl -f http://localhost:8080/health

# Database connectivity
docker-compose exec mev-api python -c "
import psycopg2
conn = psycopg2.connect('postgresql://mev_user:secure_password@postgres:5432/mev_production')
print('Database connection successful')
conn.close()
"

# Redis connectivity
docker-compose exec mev-api python -c "
import redis
r = redis.Redis(host='redis', port=6379, db=0)
r.ping()
print('Redis connection successful')
"

# Check all service logs
docker-compose logs -f --tail=50
```

#### Performance Validation

```bash
# Load test script
cat > /opt/mev-platform/scripts/load-test.sh << EOF
#!/bin/bash
echo "Running load tests..."

# API endpoint tests
for i in {1..100}; do
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/v1/status
done | sort | uniq -c

# WebSocket connection test
wscat -c ws://localhost:8080/ws

echo "Load test completed"
EOF

chmod +x /opt/mev-platform/scripts/load-test.sh
./scripts/load-test.sh
```

## High Availability Setup

### 1. Multi-Region Deployment

#### Primary Region Configuration

```yaml
# docker-compose.primary.yml
version: '3.8'

services:
  postgres-primary:
    image: postgres:15-alpine
    environment:
      POSTGRES_REPLICATION_MODE: master
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: replication_password
    command: >
      postgres
      -c wal_level=replica
      -c max_wal_senders=3
      -c max_replication_slots=3
      -c hot_standby=on
```

#### Secondary Region Configuration

```yaml
# docker-compose.secondary.yml
version: '3.8'

services:
  postgres-secondary:
    image: postgres:15-alpine
    environment:
      POSTGRES_REPLICATION_MODE: slave
      POSTGRES_MASTER_SERVICE: primary-postgres
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: replication_password
```

### 2. Load Balancer Configuration

#### HAProxy Setup

```bash
cat > /opt/mev-platform/config/haproxy.cfg << EOF
global
    daemon
    maxconn 4096

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend mev_frontend
    bind *:80
    bind *:443 ssl crt /etc/ssl/certs/mev-platform.pem
    redirect scheme https if !{ ssl_fc }
    default_backend mev_backend

backend mev_backend
    balance roundrobin
    option httpchk GET /health
    server api1 mev-api-1:8080 check
    server api2 mev-api-2:8080 check
    server api3 mev-api-3:8080 check backup
EOF
```

## Backup & Recovery

### 1. Database Backup Strategy

#### Automated Backup Script

```bash
cat > /opt/mev-platform/scripts/backup.sh << EOF
#!/bin/bash

BACKUP_DIR="/opt/mev-platform/backups"
DATE=\$(date +%Y%m%d_%H%M%S)

# PostgreSQL backup
docker-compose exec -T postgres pg_dump -U mev_user mev_production | gzip > \$BACKUP_DIR/postgres_\$DATE.sql.gz

# Redis backup
docker-compose exec -T redis redis-cli --rdb - | gzip > \$BACKUP_DIR/redis_\$DATE.rdb.gz

# InfluxDB backup
docker-compose exec -T influxdb influx backup --bucket mev-metrics /tmp/backup_\$DATE
docker-compose cp influxdb:/tmp/backup_\$DATE \$BACKUP_DIR/influxdb_\$DATE

# Configuration backup
tar -czf \$BACKUP_DIR/config_\$DATE.tar.gz -C /opt/mev-platform config

# Cleanup old backups (keep 30 days)
find \$BACKUP_DIR -name "*.gz" -mtime +30 -delete
find \$BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "Backup completed: \$DATE"
EOF

chmod +x /opt/mev-platform/scripts/backup.sh

# Schedule daily backups
echo "0 2 * * * /opt/mev-platform/scripts/backup.sh" | crontab -
```

### 2. Disaster Recovery Procedure

#### Recovery Script

```bash
cat > /opt/mev-platform/scripts/restore.sh << EOF
#!/bin/bash

if [ -z "\$1" ]; then
    echo "Usage: \$0 <backup_date>"
    echo "Example: \$0 20250715_020000"
    exit 1
fi

BACKUP_DATE=\$1
BACKUP_DIR="/opt/mev-platform/backups"

echo "Starting disaster recovery for backup: \$BACKUP_DATE"

# Stop all services
docker-compose down

# Restore PostgreSQL
zcat \$BACKUP_DIR/postgres_\$BACKUP_DATE.sql.gz | docker-compose exec -T postgres psql -U mev_user mev_production

# Restore Redis
zcat \$BACKUP_DIR/redis_\$BACKUP_DATE.rdb.gz | docker-compose exec -T redis redis-cli --pipe

# Restore configuration
tar -xzf \$BACKUP_DIR/config_\$BACKUP_DATE.tar.gz -C /opt/mev-platform

# Start services
docker-compose up -d

echo "Disaster recovery completed"
EOF

chmod +x /opt/mev-platform/scripts/restore.sh
```

## Monitoring & Maintenance

### 1. Health Monitoring

#### System Health Script

```bash
cat > /opt/mev-platform/scripts/health-check.sh << EOF
#!/bin/bash

echo "=== MEV Platform Health Check ==="
echo "Date: \$(date)"
echo

# Check container status
echo "Container Status:"
docker-compose ps

echo
echo "Service Health Checks:"

# API health
if curl -f -s http://localhost:8080/health > /dev/null; then
    echo "✓ API service is healthy"
else
    echo "✗ API service is unhealthy"
fi

# Database connectivity
if docker-compose exec -T postgres pg_isready -U mev_user > /dev/null 2>&1; then
    echo "✓ PostgreSQL is healthy"
else
    echo "✗ PostgreSQL is unhealthy"
fi

# Redis connectivity
if docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; then
    echo "✓ Redis is healthy"
else
    echo "✗ Redis is unhealthy"
fi

echo
echo "Resource Usage:"
echo "CPU: \$(top -bn1 | grep "Cpu(s)" | awk '{print \$2 + \$4}')%"
echo "Memory: \$(free | grep Mem | awk '{printf(\"%.1f%%\", \$3/\$2 * 100.0)}')"
echo "Disk: \$(df -h / | awk 'NR==2{printf \"%s\", \$5}')"

echo
echo "=== Health Check Complete ==="
EOF

chmod +x /opt/mev-platform/scripts/health-check.sh

# Schedule health checks every 5 minutes
echo "*/5 * * * * /opt/mev-platform/scripts/health-check.sh >> /var/log/mev-health.log" | crontab -
```

### 2. Log Management

#### Log Rotation Configuration

```bash
cat > /etc/logrotate.d/mev-platform << EOF
/opt/mev-platform/data/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    postrotate
        docker-compose exec mev-api kill -USR1 1
    endscript
}
EOF
```

## Security Hardening

### 1. Firewall Configuration

```bash
# Configure UFW firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow ssh

# Allow HTTP/HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Allow monitoring (restrict to monitoring networks)
sudo ufw allow from 10.0.0.0/8 to any port 9090
sudo ufw allow from 10.0.0.0/8 to any port 3000

# Enable firewall
sudo ufw enable
```

### 2. Container Security

```bash
# Create non-root user for containers
cat > /opt/mev-platform/Dockerfile.security << EOF
FROM python:3.11-alpine

# Create non-root user
RUN addgroup -g 1000 mev && adduser -u 1000 -G mev -s /bin/sh -D mev

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Change ownership
RUN chown -R mev:mev /app

# Switch to non-root user
USER mev

EXPOSE 8080
CMD ["python", "app.py"]
EOF
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Service Won't Start

```bash
# Check logs
docker-compose logs service_name

# Check resource usage
docker stats

# Restart specific service
docker-compose restart service_name
```

#### 2. Database Connection Issues

```bash
# Test database connectivity
docker-compose exec postgres psql -U mev_user -d mev_production -c "SELECT version();"

# Check connection limits
docker-compose exec postgres psql -U mev_user -d mev_production -c "SHOW max_connections;"

# Monitor active connections
docker-compose exec postgres psql -U mev_user -d mev_production -c "SELECT count(*) FROM pg_stat_activity;"
```

#### 3. Performance Issues

```bash
# Monitor container resources
docker-compose exec mev-api top

# Check network connectivity
docker-compose exec mev-api ping postgres

# Analyze slow queries
docker-compose logs postgres | grep "slow query"
```

---

*This deployment guide provides a comprehensive foundation for enterprise-grade MEV infrastructure deployment. For additional support, consult the troubleshooting section or contact technical support.*