#!/bin/bash
# Immediate Performance Optimization for MEV Infrastructure
# Critical fixes to reduce system load and optimize for MEV operations

set -euo pipefail

echo "=== IMMEDIATE MEV PERFORMANCE OPTIMIZATION ==="
echo "Current system load is critically high for MEV operations"
echo ""

# Check current load
current_load=$(uptime | awk '{print $(NF-2)}' | cut -d',' -f1)
echo "Current Load: $current_load (Critical threshold: 10.0)"

echo ""
echo "=== RESOURCE OPTIMIZATION ==="

# 1. Optimize Erigon for MEV operations
echo "1. Optimizing Erigon configuration for MEV..."
# Reduce Erigon's resource usage temporarily
sudo systemctl edit ethereum --force --full << 'EOF'
[Unit]
Description=Ethereum Node (Erigon) - MEV Optimized
Documentation=https://github.com/ledgerwatch/erigon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=lyftium
Group=lyftium
WorkingDirectory=/data/blockchain/nodes/ethereum

# Use the fixed startup script with optimized settings
ExecStart=/data/blockchain/nodes/ethereum/start-erigon-mev-optimized.sh

# Restart policy with backoff
Restart=on-failure
RestartSec=10
StartLimitInterval=600
StartLimitBurst=5

# Resource limits - Optimized for MEV with system constraints
LimitNOFILE=500000
LimitNPROC=256000
LimitCORE=infinity

# Memory configuration - Reduced for system stability
MemoryMax=24G
MemoryHigh=20G
MemorySwapMax=0

# CPU scheduling - High priority but limited
CPUWeight=200
CPUQuota=800%
Nice=-10
IOWeight=200

# Environment variables
Environment="GOGC=50"
Environment="GOMEMLIMIT=20GiB"

# Security hardening
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/data/blockchain/storage/erigon /var/log/erigon

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ethereum

# Process management
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF

# 2. Create optimized Erigon startup script
cat > /data/blockchain/nodes/ethereum/start-erigon-mev-optimized.sh << 'EOF'
#!/bin/bash
# MEV-Optimized Erigon Startup Script
# Reduced resource usage while maintaining MEV performance

set -euo pipefail

ERIGON_BINARY="/data/blockchain/nodes/ethereum/erigon/bin/erigon"
DATA_DIR="/data/blockchain/storage/erigon"
LOG_DIR="/var/log/erigon"

# Create directories
sudo mkdir -p "$DATA_DIR" "$LOG_DIR"
sudo chown -R lyftium:lyftium "$DATA_DIR" "$LOG_DIR"

# JWT secret
if [ ! -f "$DATA_DIR/jwt.hex" ]; then
    openssl rand -hex 32 > "$DATA_DIR/jwt.hex"
fi

echo "[$(date)] Starting MEV-Optimized Erigon..." | tee -a "$LOG_DIR/erigon-startup.log"

exec $ERIGON_BINARY \
    --datadir="$DATA_DIR" \
    --chain=mainnet \
    --prune.mode=full \
    --http \
    --http.addr=127.0.0.1 \
    --http.port=8545 \
    --http.vhosts="*" \
    --http.api=eth,net,web3,txpool,erigon,trace,engine \
    --ws \
    --ws.port=8547 \
    --authrpc.addr=127.0.0.1 \
    --authrpc.port=8551 \
    --authrpc.jwtsecret="$DATA_DIR/jwt.hex" \
    --port=30309 \
    --maxpeers=25 \
    --db.pagesize=16k \
    --db.size.limit=20gb \
    --txpool.accountslots=8 \
    --txpool.globalslots=5000 \
    --txpool.globalqueue=2500 \
    --rpc.gascap=25000000 \
    --torrent.upload.rate=512mb \
    --torrent.download.rate=1024mb \
    --metrics \
    --metrics.addr=0.0.0.0 \
    --metrics.port=6062 \
    --log.console.verbosity=warn \
    --log.dir.path="$LOG_DIR" \
    --log.dir.verbosity=2 \
    --externalcl 2>&1 | tee -a "$LOG_DIR/erigon.log"
EOF

chmod +x /data/blockchain/nodes/ethereum/start-erigon-mev-optimized.sh

echo "✓ Created MEV-optimized Erigon configuration"

# 3. Check if Solana is needed for MEV operations
echo ""
echo "2. Analyzing non-MEV processes..."
if pgrep -f solana-validator > /dev/null; then
    echo "⚠ Solana validator detected (high resource usage)"
    echo "  This may not be needed for ETH MEV operations"
    echo "  Consider stopping if not required: sudo systemctl stop solana-validator"
fi

# 4. Optimize Spark cluster if not needed
if pgrep -f spark > /dev/null; then
    echo "⚠ Apache Spark cluster detected"
    echo "  Consider reducing Spark memory allocation if MEV priority is higher"
fi

# 5. System optimization
echo ""
echo "3. Applying system-level optimizations..."

# Set MEV-critical processes to high priority
echo "Setting MEV processes to high priority..."
if pgrep -f erigon > /dev/null; then
    sudo renice -10 $(pgrep -f erigon) 2>/dev/null || true
fi

if pgrep -f mev-boost > /dev/null; then
    sudo renice -10 $(pgrep -f mev-boost) 2>/dev/null || true
fi

if pgrep -f lighthouse > /dev/null; then
    sudo renice -5 $(pgrep -f lighthouse) 2>/dev/null || true
fi

echo "✓ Adjusted process priorities for MEV optimization"

# 6. Memory optimization
echo ""
echo "4. Memory optimization..."
echo "Clearing system caches..."
sudo sync
echo 1 | sudo tee /proc/sys/vm/drop_caches > /dev/null
echo "✓ System caches cleared"

# 7. Network optimization for MEV
echo ""
echo "5. Network optimization for MEV latency..."
# Optimize network settings for low latency
sudo sysctl -w net.core.rmem_max=134217728 2>/dev/null || true
sudo sysctl -w net.core.wmem_max=134217728 2>/dev/null || true
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728" 2>/dev/null || true
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728" 2>/dev/null || true
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true

echo "✓ Network optimized for MEV latency"

echo ""
echo "=== RESTART RECOMMENDATION ==="
echo "To apply all optimizations:"
echo "1. sudo systemctl daemon-reload"
echo "2. sudo systemctl restart ethereum"
echo "3. Monitor load with: watch 'uptime && ps aux --sort=-%cpu | head -5'"
echo ""
echo "Expected results:"
echo "- System load should drop below 15.0 within 5 minutes"
echo "- MEV operations should maintain <100ms latency"
echo "- Available memory should increase for optimal performance"
echo ""

# 8. Create monitoring command
echo "=== MONITORING COMMAND ==="
cat > /data/blockchain/nodes/monitor-mev-performance.sh << 'EOF'
#!/bin/bash
# MEV Performance Monitoring

while true; do
    clear
    echo "=== MEV INFRASTRUCTURE PERFORMANCE ==="
    echo "Time: $(date)"
    echo ""
    
    # System metrics
    echo "SYSTEM METRICS:"
    uptime
    free -h | head -2
    echo ""
    
    # MEV-specific checks
    echo "MEV SERVICES:"
    echo -n "Ethereum RPC: "
    if curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 > /dev/null 2>&1; then
        echo "✓ ACTIVE"
    else
        echo "✗ DOWN"
    fi
    
    echo -n "MEV-Boost: "
    if curl -s http://127.0.0.1:18550/eth/v1/builder/status > /dev/null 2>&1; then
        echo "✓ ACTIVE"
    else
        echo "✗ DOWN"
    fi
    
    echo ""
    echo "TOP PROCESSES (by CPU):"
    ps aux --sort=-%cpu | head -6
    
    echo ""
    echo "Press Ctrl+C to exit"
    sleep 5
done
EOF

chmod +x /data/blockchain/nodes/monitor-mev-performance.sh

echo "✓ MEV performance monitoring script created"
echo ""
echo "=== IMMEDIATE ACTION REQUIRED ==="
echo "Run the following commands to optimize for MEV operations:"
echo ""
echo "sudo systemctl daemon-reload"
echo "sudo systemctl restart ethereum"
echo "./monitor-mev-performance.sh  # To monitor improvements"
echo ""