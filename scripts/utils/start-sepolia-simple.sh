#!/bin/bash
set -euo pipefail

SEPOLIA_DIR="/data/blockchain/nodes/sepolia"
CONFIG_FILE="$SEPOLIA_DIR/config/erigon-sepolia.toml"
JWT_SECRET="$SEPOLIA_DIR/jwt.hex"

# Ensure JWT secret exists
if [ ! -f "$JWT_SECRET" ]; then
    openssl rand -hex 32 > "$JWT_SECRET"
fi

# Start Erigon with config file
exec /data/blockchain/nodes/ethereum/erigon/bin/erigon --config="$CONFIG_FILE"