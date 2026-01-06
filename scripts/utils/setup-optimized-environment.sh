#!/bin/bash

# Solana Optimized Environment Setup Script
# This script prepares the system for optimal Solana performance

set -e

echo "🚀 Setting up optimized Solana environment..."

# Create necessary directories
mkdir -p /data/blockchain/storage/solana
mkdir -p /data/blockchain/nodes/solana/config
mkdir -p /data/blockchain/nodes/solana/logs

# Set proper permissions
chmod 755 /data/blockchain/storage/solana
chmod 755 /data/blockchain/nodes/solana/config

# Clean any existing ledger data for fresh start
if [ -d "/data/blockchain/storage/solana/test-ledger" ]; then
    echo "🧹 Cleaning existing ledger data..."
    rm -rf /data/blockchain/storage/solana/test-ledger
fi

# System optimizations for Solana
echo "⚙️  Applying system optimizations..."

# Increase file descriptor limits
if ! grep -q "solana" /etc/security/limits.conf; then
    echo "* soft nofile 1000000" >> /etc/security/limits.conf
    echo "* hard nofile 1000000" >> /etc/security/limits.conf
fi

# Network optimizations for better performance
sysctl -w net.core.rmem_max=134217728 2>/dev/null || echo "Note: Could not set rmem_max (may require root)"
sysctl -w net.core.wmem_max=134217728 2>/dev/null || echo "Note: Could not set wmem_max (may require root)"
sysctl -w vm.swappiness=10 2>/dev/null || echo "Note: Could not set swappiness (may require root)"

# Create network if it doesn't exist
docker network create blockchain_network 2>/dev/null || echo "Network already exists"

echo "✅ Environment setup complete!"
echo "📋 Configuration summary:"
echo "   - Memory allocation: 8GB (with 4GB reserved)"
echo "   - CPU allocation: 2.0 cores"
echo "   - Storage: /data/blockchain/storage/solana"
echo "   - Config: /data/blockchain/nodes/solana/config"
echo "   - Network optimizations applied"
echo ""
echo "🔧 Ready to start optimized Solana node!"