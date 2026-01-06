#!/bin/bash
set -e

echo "🚀 Starting MEV Production Services..."

# Set MEV database password if not set
if [ -z "$MEV_DB_PASSWORD" ]; then
    export MEV_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '=' '>')
    echo "Generated secure database password"
fi

# Set other critical environment variables
export MEV_API_PORT=8082
export MEV_DASHBOARD_PORT=8080
export MEV_WEBSOCKET_PORT=8081
export FLASK_ENV=production
export MIN_PROFIT_THRESHOLD_USD=25.0
export MAX_GAS_PRICE_GWEI=100
export MAX_POSITION_SIZE_ETH=5.0

# Start services in dependency order
echo "🔄 Phase 1: Starting infrastructure services..."
docker-compose -f docker/services/docker-compose-production-mev-corrected.yml up -d redis

echo "🔄 Phase 2: Starting database..."
docker-compose -f docker/services/docker-compose-production-mev-corrected.yml up -d postgres

echo "🔄 Phase 3: Starting MEV core services..."
docker-compose -f docker/services/docker-compose-production-mev-corrected.yml up -d kafka zookeeper

echo "🔄 Phase 4: Starting MEV trading services..."
docker-compose -f docker/services/docker-compose-mev-corrected.yml up -d mev-api mev-websocket mev-dashboard

echo "🎯 All MEV services started successfully!"
echo "📊 Dashboard: http://localhost:8080"
echo "📡 API: http://localhost:8082"
echo "📈 WebSocket: ws://localhost:8083"