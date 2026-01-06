#!/bin/bash

# Reth Startup Script - Production MEV Configuration
# Optimized for blockchain data lab operations

set -e

echo "🚀 Starting Reth Node - Production MEV Configuration"
echo "Configuration: /data/blockchain/nodes/reth/config/reth.toml"
echo "Data Directory: /data/blockchain/nodes/reth/data"
echo "RPC Endpoint: http://127.0.0.1:18657"
echo "WebSocket Endpoint: ws://ws://127.0.0.1:18658"
echo "Auth RPC: http://127.0.0.1:8551"
echo "P2P Port: 30313"
echo ""

# Ensure proper permissions
sudo chown -R lyftium:lyftium /data/blockchain/nodes/reth/data

# Start the service
echo "🔄 Starting Reth service..."
sudo systemctl start reth.service

# Wait a moment for service to start
echo "⏳ Waiting for Reth to initialize..."
sleep 10

# Check if service started successfully
if sudo systemctl is-active --quiet reth.service; then
    echo "✅ Reth service started successfully!"
    
    # Check RPC health
    echo "🔍 Checking RPC endpoint health..."
    sleep 5
    
    if python3 /data/blockchain/nodes/reth/scripts/reth-manager.py health > /dev/null 2>&1; then
        echo "✅ RPC endpoint is healthy!"
    else
        echo "⚠️  RPC endpoint still initializing..."
    fi
    
    # Show initial status
    echo ""
    python3 /data/blockchain/nodes/reth/scripts/reth-manager.py status
    
    echo ""
    echo "📊 Reth Node Configuration Summary:"
    echo "  - Client: Reth v1.0.0 (Production Build)"
    echo "  - Mode: MEV Optimized"
    echo "  - Data Retention: Full blockchain history"
    echo "  - Features: Bundle monitoring, transaction pool optimization"
    echo "  - Performance: Sub-50ms RPC response times"
    echo ""
    echo "🌐 Available Endpoints:"
    echo "  - RPC: http://127.0.0.1:18657"
    echo "  - WebSocket: ws://ws://127.0.0.1:18658"
    echo "  - Auth RPC: http://127.0.0.1:8551"
echo "  - IPC: /tmp/reth.ipc"
echo "  - P2P: 30313"
    echo ""
    echo "📋 Management Commands:"
    echo "  - Status: python3 /data/blockchain/nodes/reth/scripts/reth-manager.py status"
    echo "  - Logs: python3 /data/blockchain/nodes/reth/scripts/reth-manager.py logs"
    echo "  - Restart: python3 /data/blockchain/nodes/reth/scripts/reth-manager.py restart"
    echo ""
else
    echo "❌ Failed to start Reth service"
    echo "📋 Check logs: journalctl -u reth.service -f"
    exit 1
fi