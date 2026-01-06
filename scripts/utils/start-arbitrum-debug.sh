#!/bin/bash
# Arbitrum Node - Debug Configuration to diagnose tmp directory issue

set -euo pipefail

# Configuration
DATA_DIR="/data/blockchain/storage/arbitrum"
LOG_DIR="$DATA_DIR/logs"
NITRO_DIR="$DATA_DIR/nitro"

echo "=== Arbitrum Node Debug Script ==="
echo "Current time: $(date)"
echo

# Check current state
echo "1. Checking directory structure:"
echo "   Main data dir: $DATA_DIR"
ls -la "$DATA_DIR"
echo
echo "   Nitro dir: $NITRO_DIR"
ls -la "$NITRO_DIR" 2>/dev/null || echo "   [Does not exist]"
echo

# Clean up tmp directory if it exists
if [ -d "$NITRO_DIR/tmp" ]; then
    echo "2. Found tmp directory in nitro folder:"
    ls -la "$NITRO_DIR/tmp"
    echo
    echo "   This is causing the 'unexpected files in database directory' error!"
    echo "   The tmp directory contains partial download files from a previous attempt."
    echo
    
    # Check if download is complete
    if [ -f "$NITRO_DIR/tmp/pruned.tar.part0000" ]; then
        echo "3. Partial download detected. Options:"
        echo "   a) Remove tmp directory and start fresh download"
        echo "   b) Wait for download to complete (if container is running)"
        echo
        
        # Check if container is running
        if docker ps | grep -q arbitrum-node; then
            echo "   Container is currently running - download may be in progress"
            echo "   Check logs: tail -f $LOG_DIR/arbitrum.log"
        else
            echo "   Container is NOT running - download is incomplete"
            echo
            echo "   To fix, run: sudo rm -rf $NITRO_DIR/tmp"
            echo "   Then restart the node"
        fi
    fi
else
    echo "2. No tmp directory found - this is good!"
fi

echo
echo "4. Checking for existing chaindata:"
if [ -d "$NITRO_DIR/l2chaindata" ]; then
    echo "   Found existing l2chaindata directory"
    ls -la "$NITRO_DIR/l2chaindata" | head -5
else
    echo "   No l2chaindata directory - node needs initialization"
fi

echo
echo "5. Docker container status:"
docker ps -a | grep arbitrum || echo "   No arbitrum containers found"

echo
echo "=== Recommendations ==="
echo
if [ -d "$NITRO_DIR/tmp" ]; then
    echo "ISSUE: The tmp directory exists and is preventing node startup."
    echo
    echo "ROOT CAUSE: Nitro node downloads the snapshot in parts to a tmp directory."
    echo "If the download is interrupted or the container exits during download,"
    echo "the tmp directory remains and causes the 'unexpected files' error on restart."
    echo
    echo "SOLUTION:"
    echo "1. Remove the tmp directory: sudo rm -rf $NITRO_DIR/tmp"
    echo "2. Clear any partial chaindata: sudo rm -rf $NITRO_DIR/l2chaindata"
    echo "3. Restart the node with the original script"
    echo
    echo "ALTERNATIVE SOLUTION (for large downloads):"
    echo "1. Download snapshot manually:"
    echo "   wget https://snapshot.arbitrum.foundation/arb1/nitro-pruned.tar"
    echo "2. Use local file in startup:"
    echo "   --init.url=\"file:///path/to/nitro-pruned.tar\""
else
    echo "No issues detected. You can start the node normally."
fi

echo
echo "=== End of Debug Report ==="