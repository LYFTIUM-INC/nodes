#!/bin/bash

echo "🚀 PRIVATE MEMPOOL INFRASTRUCTURE DEPLOYMENT STATUS"
echo "=================================================="
echo

# Check virtual environment
if [ -d "venv" ]; then
    echo "✅ Python virtual environment: Created"
    source venv/bin/activate
    echo "   Python version: $(python --version)"
    echo "   Key packages installed:"
    pip list | grep -E "web3|flashbots|websocket|aiohttp|requests" | awk '{printf "     - %s %s\n", $1, $2}'
else
    echo "❌ Python virtual environment: Not found"
fi

echo

# Check configuration
echo "📋 Configuration Status:"
if [ -d "config" ]; then
    echo "✅ Configuration directory exists"
    for file in config/*.json config/.env*; do
        if [ -f "$file" ]; then
            echo "   ✅ $(basename $file)"
        fi
    done
else
    echo "❌ Configuration directory not found"
fi

echo

# Check directories
echo "📁 Directory Structure:"
for dir in data backups logs; do
    if [ -d "$dir" ]; then
        echo "✅ $dir/"
    elif [ -d "/data/blockchain/nodes/logs" ] && [ "$dir" = "logs" ]; then
        echo "✅ logs/ (at /data/blockchain/nodes/logs)"
    else
        echo "❌ $dir/ - Missing"
    fi
done

echo

# Check Python modules
echo "🐍 Python Module Status:"
source venv/bin/activate 2>/dev/null
for module in config flashbots_client bloxroute_client buildernet_client validator_client mev_protection_client unified_manager; do
    if python -c "import $module" 2>/dev/null; then
        echo "✅ $module"
    else
        echo "❌ $module - Import failed"
    fi
done

echo
echo "=================================================="
echo "📊 DEPLOYMENT SUMMARY"
echo "=================================================="

if [ -f "venv/bin/python" ] && [ -d "config" ] && [ -f "config/mev_config.json" ]; then
    echo "✅ Infrastructure is DEPLOYED and READY"
    echo
    echo "🎯 Next Steps:"
    echo "1. Configure API keys in config/.env"
    echo "2. Run: source venv/bin/activate"
    echo "3. Run: python start_private_mempool.py"
    echo
    echo "📚 Available Services:"
    echo "   - Flashbots Private Relay Integration"
    echo "   - BloXroute MEV Integration" 
    echo "   - BuilderNet Early Access"
    echo "   - Validator Relationships"
    echo "   - MEV Protection Services"
else
    echo "⚠️  Infrastructure partially deployed"
    echo "   Run ./deploy.sh to complete setup"
fi

echo
echo "🌟 Private Mempool Infrastructure v1.0"
echo "=================================================="