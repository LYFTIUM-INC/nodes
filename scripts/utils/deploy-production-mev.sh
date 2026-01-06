#!/bin/bash
set -e

# Production MEV Infrastructure Deployment Script
# Advanced 8-chain arbitrage trading system

echo "🚀 Deploying Production MEV Infrastructure..."
echo "================================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="/data/blockchain/nodes"
MEV_DIR="$PROJECT_DIR/mev"
LOGS_DIR="$PROJECT_DIR/logs"
STORAGE_DIR="/data/blockchain/storage"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root"
    exit 1
fi

# System requirements check
check_system_requirements() {
    print_header "🔍 Checking System Requirements..."
    
    # Check available memory
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -lt 64 ]; then
        print_warning "Recommended minimum RAM: 64GB. Current: ${TOTAL_MEM}GB"
    else
        print_status "Memory check passed: ${TOTAL_MEM}GB available"
    fi
    
    # Check available disk space
    DISK_SPACE=$(df -BG $PROJECT_DIR | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$DISK_SPACE" -lt 2000 ]; then
        print_warning "Recommended minimum disk space: 2TB. Current: ${DISK_SPACE}GB available"
    else
        print_status "Disk space check passed: ${DISK_SPACE}GB available"
    fi
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 16 ]; then
        print_warning "Recommended minimum CPU cores: 16. Current: ${CPU_CORES}"
    else
        print_status "CPU check passed: ${CPU_CORES} cores available"
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed"
        exit 1
    fi
    
    print_status "System requirements check completed"
}

# Create necessary directories
setup_directories() {
    print_header "📁 Setting up directories..."
    
    # Create storage directories
    sudo mkdir -p $STORAGE_DIR/{erigon,arbitrum,optimism,base,polygon,avalanche,bsc,solana}
    sudo mkdir -p $LOGS_DIR
    sudo mkdir -p $MEV_DIR/{logs,config,data}
    
    # Set proper permissions
    sudo chown -R $USER:$USER $STORAGE_DIR
    sudo chown -R $USER:$USER $LOGS_DIR
    sudo chown -R $USER:$USER $MEV_DIR
    
    # Create log files
    touch $LOGS_DIR/{mev-system.log,deployment.log,errors.log}
    
    print_status "Directories created successfully"
}

# Build Docker images
build_docker_images() {
    print_header "🏗️ Building Docker images..."
    
    cd $PROJECT_DIR
    
    # Build MEV-specific images
    print_status "Building MEV Relay Aggregator..."
    docker-compose -f docker-compose-production-mev.yml build mev-relay-aggregator
    
    print_status "Building Flashloan Monitor..."
    docker-compose -f docker-compose-production-mev.yml build flashloan-monitor
    
    print_status "Building Sandwich Detector..."
    docker-compose -f docker-compose-production-mev.yml build sandwich-detector
    
    print_status "Building Arbitrage Detector..."
    docker-compose -f docker-compose-production-mev.yml build arbitrage-detector
    
    print_status "Building MEV Dashboard..."
    docker-compose -f docker-compose-production-mev.yml build mev-dashboard
    
    print_status "Docker images built successfully"
}

# Create Dockerfiles for MEV components
create_dockerfiles() {
    print_header "📝 Creating Dockerfiles for MEV components..."
    
    # Flashloan Monitor Dockerfile
    cat > $MEV_DIR/flashloan_monitor/Dockerfile << 'EOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    gcc g++ curl netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p /app/logs /app/config /app/data
RUN chmod +x /app/entrypoint.sh

EXPOSE 8903

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8903/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
EOF

    # Sandwich Engine Dockerfile
    cat > $MEV_DIR/sandwich_engine/Dockerfile << 'EOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    gcc g++ curl netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p /app/logs /app/config /app/data
RUN chmod +x /app/entrypoint.sh

EXPOSE 8904 8905

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8904/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
EOF

    # Arbitrage Engine Dockerfile
    cat > $MEV_DIR/arbitrage_engine/Dockerfile << 'EOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    gcc g++ curl netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p /app/logs /app/config /app/data
RUN chmod +x /app/entrypoint.sh

EXPOSE 8906 8907

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8906/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
EOF

    # Create requirements files
    cat > $MEV_DIR/flashloan_monitor/requirements.txt << 'EOF'
aiohttp==3.9.1
asyncio-throttle==1.0.2
websockets==12.0
redis==5.0.1
aioredis==2.0.1
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
web3==6.12.0
structlog==23.2.0
prometheus-client==0.19.0
numpy==1.25.2
pandas==2.1.4
pydantic==2.5.0
orjson==3.9.10
EOF

    cat > $MEV_DIR/sandwich_engine/requirements.txt << 'EOF'
aiohttp==3.9.1
asyncio-throttle==1.0.2
websockets==12.0
redis==5.0.1
aioredis==2.0.1
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
web3==6.12.0
structlog==23.2.0
prometheus-client==0.19.0
numpy==1.25.2
pandas==2.1.4
pydantic==2.5.0
orjson==3.9.10
EOF

    cat > $MEV_DIR/arbitrage_engine/requirements.txt << 'EOF'
aiohttp==3.9.1
asyncio-throttle==1.0.2
websockets==12.0
redis==5.0.1
aioredis==2.0.1
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
web3==6.12.0
structlog==23.2.0
prometheus-client==0.19.0
numpy==1.25.2
pandas==2.1.4
pydantic==2.5.0
orjson==3.9.10
ccxt.pro==4.1.40
EOF

    # Create entrypoint scripts
    cat > $MEV_DIR/flashloan_monitor/entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting Flashloan Monitor..."

# Wait for Redis
echo "⏳ Waiting for Redis..."
while ! nc -z redis 6379; do
  sleep 1
done
echo "✅ Redis is ready"

# Start the application
echo "🌟 Starting Flashloan Monitor service..."
python monitor.py
EOF

    cat > $MEV_DIR/sandwich_engine/entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting Sandwich Detector..."

# Wait for Redis
echo "⏳ Waiting for Redis..."
while ! nc -z redis 6379; do
  sleep 1
done
echo "✅ Redis is ready"

# Start the application
echo "🌟 Starting Sandwich Detector service..."
python detector.py
EOF

    cat > $MEV_DIR/arbitrage_engine/entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting Cross-Chain Arbitrage Detector..."

# Wait for Redis
echo "⏳ Waiting for Redis..."
while ! nc -z redis 6379; do
  sleep 1
done
echo "✅ Redis is ready"

# Start the application
echo "🌟 Starting Arbitrage Detector service..."
python cross_chain_detector.py
EOF

    # Make entrypoint scripts executable
    chmod +x $MEV_DIR/flashloan_monitor/entrypoint.sh
    chmod +x $MEV_DIR/sandwich_engine/entrypoint.sh
    chmod +x $MEV_DIR/arbitrage_engine/entrypoint.sh
    
    print_status "Dockerfiles and entrypoint scripts created"
}

# Configure monitoring
setup_monitoring() {
    print_header "📊 Setting up monitoring configuration..."
    
    # Prometheus configuration
    cat > $PROJECT_DIR/monitoring/prometheus-mev.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "mev_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'mev-relay-aggregator'
    static_configs:
      - targets: ['mev-relay-aggregator:8902']

  - job_name: 'flashloan-monitor'
    static_configs:
      - targets: ['flashloan-monitor:8903']

  - job_name: 'sandwich-detector'
    static_configs:
      - targets: ['sandwich-detector:8904']

  - job_name: 'arbitrage-detector'
    static_configs:
      - targets: ['arbitrage-detector:8906']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
EOF

    # Loki configuration
    cat > $PROJECT_DIR/monitoring/loki-config.yml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  wal:
    enabled: true
    dir: /loki/wal
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 1h
  max_chunk_age: 1h
  chunk_target_size: 1048576
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    resync_interval: 5s
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

compactor:
  working_directory: /loki/boltdb-shipper-compactor
  shared_store: filesystem

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s

ruler:
  storage:
    type: local
    local:
      directory: /loki/rules
  rule_path: /loki/rules-temp
  alertmanager_url: http://localhost:9093
  ring:
    kvstore:
      store: inmemory
  enable_api: true
EOF

    # Promtail configuration
    cat > $PROJECT_DIR/monitoring/promtail-config.yml << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: mev-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: mev-system
          __path__: /var/log/mev/*.log

  - job_name: system-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          __path__: /var/log/*.log
EOF

    print_status "Monitoring configuration created"
}

# Deploy services in order
deploy_services() {
    print_header "🚢 Deploying services..."
    
    cd $PROJECT_DIR
    
    # Start infrastructure services first
    print_status "Starting Redis..."
    docker-compose -f docker-compose-production-mev.yml up -d redis
    sleep 10
    
    print_status "Starting blockchain nodes..."
    docker-compose -f docker-compose-production-mev.yml up -d \
        ethereum-erigon \
        arbitrum-node \
        optimism-node \
        base-node \
        polygon-node \
        avalanche-node \
        bsc-node \
        solana-dev
    
    # Wait for nodes to be ready
    print_status "Waiting for blockchain nodes to be ready..."
    sleep 60
    
    # Start MEV-Boost
    print_status "Starting MEV-Boost..."
    docker-compose -f docker-compose-production-mev.yml up -d mev-boost-advanced
    sleep 10
    
    # Start MEV services
    print_status "Starting MEV services..."
    docker-compose -f docker-compose-production-mev.yml up -d \
        mev-relay-aggregator \
        flashloan-monitor \
        sandwich-detector \
        arbitrage-detector
    
    # Wait for MEV services
    sleep 30
    
    # Start monitoring
    print_status "Starting monitoring services..."
    docker-compose -f docker-compose-production-mev.yml up -d \
        prometheus \
        grafana \
        loki \
        promtail \
        node-exporter \
        cadvisor
    
    # Start dashboard and risk manager
    print_status "Starting dashboard and risk management..."
    docker-compose -f docker-compose-production-mev.yml up -d \
        mev-dashboard \
        risk-manager
    
    print_status "All services deployed successfully"
}

# Health checks
run_health_checks() {
    print_header "🏥 Running health checks..."
    
    # Wait for services to be ready
    sleep 30
    
    # Check blockchain nodes
    print_status "Checking blockchain nodes..."
    
    NODES=(
        "ethereum-erigon:8545"
        "arbitrum-node:8549"
        "optimism-node:8551"
        "base-node:8547"
        "polygon-node:8553"
        "avalanche-node:9650"
        "bsc-node:8555"
        "solana-dev:8899"
    )
    
    for node in "${NODES[@]}"; do
        IFS=':' read -r container port <<< "$node"
        if curl -s -f "http://localhost:$port" > /dev/null 2>&1; then
            print_status "$container is healthy"
        else
            print_warning "$container may not be ready yet"
        fi
    done
    
    # Check MEV services
    print_status "Checking MEV services..."
    
    MEV_SERVICES=(
        "mev-boost-advanced:18550"
        "mev-relay-aggregator:8900"
        "flashloan-monitor:8903"
        "sandwich-detector:8904"
        "arbitrage-detector:8906"
        "mev-dashboard:8080"
        "risk-manager:8908"
    )
    
    for service in "${MEV_SERVICES[@]}"; do
        IFS=':' read -r container port <<< "$service"
        if curl -s -f "http://localhost:$port/health" > /dev/null 2>&1; then
            print_status "$container is healthy"
        else
            print_warning "$container may not be ready yet"
        fi
    done
    
    # Check monitoring
    print_status "Checking monitoring services..."
    
    if curl -s -f "http://localhost:9090" > /dev/null 2>&1; then
        print_status "Prometheus is healthy"
    else
        print_warning "Prometheus may not be ready yet"
    fi
    
    if curl -s -f "http://localhost:3000" > /dev/null 2>&1; then
        print_status "Grafana is healthy"
    else
        print_warning "Grafana may not be ready yet"
    fi
    
    print_status "Health checks completed"
}

# Generate summary report
generate_summary() {
    print_header "📋 Deployment Summary"
    
    echo "================================================"
    echo "🎉 MEV Infrastructure Deployment Complete!"
    echo "================================================"
    echo
    echo "🔗 ACCESS POINTS:"
    echo "  • MEV Dashboard:     http://localhost:8080"
    echo "  • Grafana:           http://localhost:3000 (admin/mev_production_2024)"
    echo "  • Prometheus:        http://localhost:9090"
    echo "  • MEV-Boost:         http://localhost:18550"
    echo
    echo "🌐 BLOCKCHAIN NODES:"
    echo "  • Ethereum:          http://localhost:8545"
    echo "  • Arbitrum:          http://localhost:8549"
    echo "  • Optimism:          http://localhost:8551"
    echo "  • Base:              http://localhost:8547"
    echo "  • Polygon:           http://localhost:8553"
    echo "  • Avalanche:         http://localhost:9650"
    echo "  • BSC:               http://localhost:8555"
    echo "  • Solana:            http://localhost:8899"
    echo
    echo "⚡ MEV SERVICES:"
    echo "  • Relay Aggregator:  http://localhost:8900"
    echo "  • Flashloan Monitor: http://localhost:8903"
    echo "  • Sandwich Detector: http://localhost:8904"
    echo "  • Arbitrage Engine:  http://localhost:8906"
    echo "  • Risk Manager:      http://localhost:8908"
    echo
    echo "📊 MONITORING:"
    echo "  • System Metrics:    http://localhost:9100"
    echo "  • Container Metrics: http://localhost:8083"
    echo "  • Logs:              http://localhost:3100"
    echo
    echo "📁 DATA LOCATIONS:"
    echo "  • Storage:           $STORAGE_DIR"
    echo "  • Logs:              $LOGS_DIR"
    echo "  • MEV Config:        $MEV_DIR"
    echo
    echo "🔧 MANAGEMENT COMMANDS:"
    echo "  • View logs:         docker-compose -f docker-compose-production-mev.yml logs -f [service]"
    echo "  • Stop all:          docker-compose -f docker-compose-production-mev.yml down"
    echo "  • Restart service:   docker-compose -f docker-compose-production-mev.yml restart [service]"
    echo "  • Scale service:     docker-compose -f docker-compose-production-mev.yml up -d --scale [service]=N"
    echo
    echo "⚠️  IMPORTANT NOTES:"
    echo "  • Initial sync may take several hours"
    echo "  • Monitor disk space and memory usage"
    echo "  • Check logs regularly for any issues"
    echo "  • Configure firewall rules for production"
    echo "  • Set up SSL certificates for external access"
    echo "  • Review and adjust risk management parameters"
    echo
    echo "🚀 The MEV infrastructure is now ready for production trading!"
    echo "================================================"
}

# Main execution
main() {
    echo "Starting MEV Infrastructure Deployment..."
    echo "This will deploy a world-class 8-chain arbitrage trading system"
    echo
    
    read -p "Are you ready to proceed? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    
    # Log deployment start
    echo "$(date): Starting MEV Infrastructure Deployment" >> $LOGS_DIR/deployment.log
    
    # Execute deployment steps
    check_system_requirements
    setup_directories
    create_dockerfiles
    setup_monitoring
    build_docker_images
    deploy_services
    run_health_checks
    generate_summary
    
    # Log deployment completion
    echo "$(date): MEV Infrastructure Deployment Completed Successfully" >> $LOGS_DIR/deployment.log
}

# Error handling
trap 'print_error "Deployment failed at line $LINENO. Check logs for details."; exit 1' ERR

# Run main function
main "$@"