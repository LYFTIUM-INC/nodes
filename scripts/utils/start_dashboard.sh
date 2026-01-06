#!/bin/bash
# MEV Labs Dashboard Startup Script

set -e

echo "🚀 Starting MEV Labs Infrastructure Dashboard..."
echo "================================================"

# Check if blockchain nodes are running
echo "📊 Checking blockchain node status..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(ethereum|arbitrum|optimism|base|polygon|bsc|avalanche|solana)" || echo "⚠️  Some blockchain nodes may not be running"

echo ""
echo "🌐 Starting dashboard web server..."

# Find available port
for port in {8090..8100}; do
    if ! netstat -tln | grep ":$port " > /dev/null 2>&1; then
        echo "✅ Found available port: $port"
        
        # Kill any existing server processes
        pkill -f "http.server" 2>/dev/null || true
        
        # Start HTTP server
        cd "$(dirname "$0")"
        python3 -m http.server $port > /dev/null 2>&1 &
        SERVER_PID=$!
        
        sleep 2
        
        if ps -p $SERVER_PID > /dev/null; then
            echo "✅ Dashboard server started successfully (PID: $SERVER_PID)"
            echo ""
            echo "🎯 Dashboard Access Information:"
            echo "================================"
            echo "📱 Local URL:     http://localhost:$port/mev-labs-dashboard.html"
            echo "🌍 Network URL:   http://$(hostname -I | cut -d' ' -f1):$port/mev-labs-dashboard.html"
            echo ""
            echo "📋 Features:"
            echo "- Real-time blockchain node monitoring"
            echo "- Support for 8 blockchains (Ethereum, Arbitrum, Optimism, Base, Polygon, BSC, Avalanche, Solana)"
            echo "- Live RPC endpoint testing"
            echo "- MEV infrastructure status"
            echo "- System resource monitoring"
            echo ""
            echo "🔄 The dashboard auto-refreshes every 10 seconds"
            echo "⏹️  To stop the server: kill $SERVER_PID"
            
            # Save PID for easy cleanup
            echo $SERVER_PID > dashboard.pid
            
            break
        else
            echo "❌ Failed to start server on port $port"
        fi
    else
        echo "⚠️  Port $port is in use, trying next..."
    fi
done

echo ""
echo "🎉 MEV Labs Dashboard is ready!"
echo "================================================"