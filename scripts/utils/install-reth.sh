#!/bin/bash

# Reth Installation Script for Production MEV Environment
# Professional setup for blockchain data lab

set -e

echo "🚀 Installing Reth for Production MEV Environment"

# Variables
RETH_VERSION="v1.0.0"
INSTALL_DIR="/usr/local/bin"
RETH_USER="lyftium"
RETH_GROUP="lyftium"
RETH_DATA_DIR="/data/blockchain/nodes/reth/data"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

echo "📦 Downloading Reth binary..."

# Download Reth binary
cd /tmp
wget -O reth.tar.gz "https://github.com/paradigmxyz/reth/releases/download/${RETH_VERSION}/reth-${RETH_VERSION}-x86_64-unknown-linux-gnu.tar.gz"

echo "📂 Extracting Reth..."
tar -xzf reth.tar.gz
chmod +x reth-${RETH_VERSION}-x86_64-unknown-linux-gnu/reth

echo "🔄 Installing Reth system-wide..."
mv reth-${RETH_VERSION}-x86_64-unknown-linux-gnu/reth ${INSTALL_DIR}/reth
ln -sf ${INSTALL_DIR}/reth ${INSTALL_DIR}/reth-node

echo "👥 Setting permissions..."
chown ${RETH_USER}:${RETH_GROUP} ${INSTALL_DIR}/reth

echo "📋 Creating Reth user group and system directories..."
groupadd -r reth 2>/dev/null || true
useradd -r -g reth -s /bin/false -d ${RETH_DATA_DIR} reth 2>/dev/null || true

# Create data directories
mkdir -p ${RETH_DATA_DIR}/{blocks,state,transactions,headers,canonical-chain}
chown -R reth:reth ${RETH_DATA_DIR}

echo "🧹 Cleaning up..."
rm -rf /tmp/reth*

echo "✅ Reth installation completed successfully!"

# Verify installation
if command -v reth &> /dev/null; then
    echo "🔍 Verifying Reth installation..."
    reth --version
    echo "✅ Reth is ready for production use!"
else
    echo "❌ Reth installation failed"
    exit 1
fi

echo ""
echo "📚 Next steps:"
echo "1. Configure reth.toml in /data/blockchain/nodes/reth/config/"
echo "2. Create systemd service: /etc/systemd/system/reth.service"
echo "3. Start Reth: systemctl enable --now reth"
echo ""
echo "🌐 RPC Endpoint: http://127.0.0.1:18554"
echo "🔌 WebSocket Endpoint: ws://127.0.0.1:18555"
echo "📊 Metrics: http://127.0.0.1:18560/metrics"