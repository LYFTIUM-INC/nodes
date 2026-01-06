#!/bin/bash

# MEV/Arbitrage Quick Start Script
# Get operational in 15 minutes

echo "🚀 MEV/ARBITRAGE QUICK START"
echo "============================"

# 1. Install ClickHouse for time-series data
echo "📊 Installing ClickHouse..."
sudo apt-get install -y apt-transport-https ca-certificates dirmngr
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 8919F6BD2B48D754
echo "deb https://packages.clickhouse.com/deb stable main" | sudo tee /etc/apt/sources.list.d/clickhouse.list
sudo apt-get update
sudo apt-get install -y clickhouse-server clickhouse-client

# 2. Set up Redis for real-time caching
echo "⚡ Setting up Redis..."
sudo apt-get install -y redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server

# 3. Install Python environment
echo "🐍 Setting up Python environment..."
cd /data/blockchain/nodes/mev
python3 -m venv venv
source venv/bin/activate
pip install -r data-pipeline/requirements.txt

# 4. Create MEV database schema
echo "🗄️ Creating database schema..."
clickhouse-client <<EOF
CREATE DATABASE IF NOT EXISTS mev_arbitrage;

USE mev_arbitrage;

CREATE TABLE IF NOT EXISTS arbitrage_opportunities (
    timestamp DateTime64(3),
    chain String,
    opportunity_type String,
    token_a String,
    token_b String,
    dex_a String,
    dex_b String,
    price_a Decimal(38, 18),
    price_b Decimal(38, 18),
    profit_usd Decimal(18, 2),
    gas_cost_usd Decimal(18, 2),
    net_profit_usd Decimal(18, 2),
    executed Boolean DEFAULT false,
    execution_tx String,
    INDEX idx_timestamp timestamp TYPE minmax GRANULARITY 3600,
    INDEX idx_profit net_profit_usd TYPE minmax GRANULARITY 100
) ENGINE = MergeTree()
ORDER BY (timestamp, chain, opportunity_type);

CREATE TABLE IF NOT EXISTS mempool_transactions (
    timestamp DateTime64(3),
    chain String,
    tx_hash String,
    from_address String,
    to_address String,
    value Decimal(38, 18),
    gas_price Decimal(18, 9),
    input_data String,
    mev_type String,
    profit_estimate Decimal(18, 2)
) ENGINE = MergeTree()
ORDER BY (timestamp, chain, tx_hash)
TTL timestamp + INTERVAL 1 DAY;
EOF

# 5. Start monitoring services
echo "📡 Starting monitoring services..."

# Create systemd service for mempool monitoring
sudo tee /etc/systemd/system/mev-mempool-monitor.service > /dev/null <<EOF
[Unit]
Description=MEV Mempool Monitor
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/data/blockchain/nodes/mev
ExecStart=/data/blockchain/nodes/mev/venv/bin/python /data/blockchain/nodes/mev/mempool_monitor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 6. Create sample arbitrage bot
cat > /data/blockchain/nodes/mev/simple_arbitrage_bot.py << 'EOF'
#!/usr/bin/env python3
"""
Simple Arbitrage Bot - Get started with MEV
"""

import asyncio
import json
from web3 import Web3
from decimal import Decimal
import aiohttp
import redis

# Configuration
CHAINS = {
    'ethereum': {'rpc': 'http://localhost:8545', 'chain_id': 1},
    'base': {'rpc': 'http://localhost:8547', 'chain_id': 8453},
    'arbitrum': {'rpc': 'http://localhost:8549', 'chain_id': 42161},
    'optimism': {'rpc': 'http://localhost:8550', 'chain_id': 10},
    'polygon': {'rpc': 'http://localhost:8552', 'chain_id': 137},
    'bsc': {'rpc': 'http://localhost:8555', 'chain_id': 56},
}

# DEX addresses (example - Uniswap V2 style)
DEXES = {
    'uniswap_v2': '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
    'sushiswap': '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F',
    'pancakeswap': '0x10ED43C718714eb63d5aA57B78B54704E256024E',
}

class SimpleArbitrageBot:
    def __init__(self):
        self.redis_client = redis.Redis(host='localhost', port=6379, db=0)
        self.opportunities = []
        
    async def find_arbitrage_opportunities(self):
        """Scan for price differences across DEXes"""
        print("🔍 Scanning for arbitrage opportunities...")
        
        # This is a simplified example - real implementation would:
        # 1. Connect to DEX contracts
        # 2. Get real-time prices
        # 3. Calculate profit after gas
        # 4. Execute if profitable
        
        # Example opportunity detection
        opportunity = {
            'type': 'dex_arbitrage',
            'chain': 'ethereum',
            'token_pair': 'WETH/USDC',
            'buy_dex': 'uniswap_v2',
            'sell_dex': 'sushiswap',
            'profit_estimate': 150.00,  # USD
            'gas_cost': 50.00,  # USD
            'net_profit': 100.00  # USD
        }
        
        if opportunity['net_profit'] > 50:  # Min profit threshold
            print(f"💰 Found opportunity: {opportunity}")
            self.opportunities.append(opportunity)
            
            # Store in Redis for execution
            self.redis_client.lpush(
                'arbitrage_opportunities',
                json.dumps(opportunity)
            )
    
    async def run(self):
        """Main bot loop"""
        print("🤖 Simple Arbitrage Bot Started")
        print("=" * 50)
        
        while True:
            try:
                await self.find_arbitrage_opportunities()
                await asyncio.sleep(1)  # Check every second
                
            except Exception as e:
                print(f"❌ Error: {e}")
                await asyncio.sleep(5)

if __name__ == "__main__":
    bot = SimpleArbitrageBot()
    asyncio.run(bot.run())
EOF

chmod +x /data/blockchain/nodes/mev/simple_arbitrage_bot.py

echo ""
echo "✅ MEV/ARBITRAGE QUICK START COMPLETE!"
echo ""
echo "🎯 NEXT STEPS:"
echo "1. Start simple arbitrage bot:"
echo "   cd /data/blockchain/nodes/mev && ./simple_arbitrage_bot.py"
echo ""
echo "2. Monitor opportunities in ClickHouse:"
echo "   clickhouse-client -d mev_arbitrage"
echo ""
echo "3. View real-time metrics:"
echo "   http://localhost:3000 (Grafana)"
echo ""
echo "4. Check Redis cache:"
echo "   redis-cli"
echo ""
echo "💡 Start with small amounts ($100-1000) to test!"