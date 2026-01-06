#!/usr/bin/env python3
"""
Quick blockchain sync status check
"""

import asyncio
import aiohttp
import json
import sys
from datetime import datetime
from pathlib import Path
import yaml

async def main():
    """Quick blockchain sync status check"""
    config_file = "/data/blockchain/nodes/etc/sync_verifier.conf"
    
    # Load configuration
    config = {}
    if Path(config_file).exists():
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f) or {}
    
    networks = config.get('networks', ['mainnet'])
    node_types = config.get('node_types', ['geth', 'erigon'])
    rpc_endpoints = config.get('rpc_endpoints', {})
    
    print(f"🔍 QUICK SYNC STATUS CHECK - {datetime.now()}")
    print(f"Network: {networks}")
    print(f"Node types: {node_types}")
    print(f"{'='*60}")

    # Quick sync status for each node type
    for node_type in node_types:
        rpc_url = rpc_endpoints.get(node_type)
        if rpc_url:
            print(f"\n--- {node_type.upper()} ---")
            try:
                async with aiohttp.ClientSession() as session:
                    payload = {
                        "jsonrpc": "2.0",
                        "method": "eth_syncing",
                        "params": [],
                        "id": 1
                    }
                    async with session.post(rpc_url, json=payload) as response:
                        if response.status == 200:
                            data = await response.json()
                            sync_result = data.get("result", False)

                            if sync_result:
                                current_block = int(data.get("currentBlock", "0x0"), 16)
                                highest_block = int(data.get("highestBlock", "0x0"), 16)
                                peer_count = int(data.get("result", "0x0"), 16)

                                sync_progress = min(100.0, (current_block / highest_block) * 100) if highest_block > 0 else 100

                                print(f"  Status: {'Syncing' if sync_result else 'Fully Synced'}")
                                print(f"  Progress: {sync_progress:.1f}%")
                                print(f"  Current Block: #{current_block}")
                                print(f"  Highest Block: #{highest_block}")
                                print(f"  Peer Count: {peer_count}")
                            else:
                                print(f"  Status: ❌ Node not responding")
                except Exception as e:
                    print(f"  ❌ {node_type} error: {e}")
                    continue
            else:
                        print(f"  ⚠️ {node_type} not configured")
        else:
            print(f"  ⚠️ {node_type} not configured")

if __name__ == "__main__":
    asyncio.run(main())