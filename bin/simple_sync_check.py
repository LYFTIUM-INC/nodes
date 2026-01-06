#!/usr/bin/env python3
"""
Simple sync status checker
"""

import requests
import json

def check_node_status():
    """Check sync status of blockchain nodes"""

    # Check Erigon (port 8545)
    erigon_url = "http://127.0.0.1:8545"

    try:
        print("--- ERIGON ---")
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_syncing",
            "params": [],
            "id": 1
        }

        response = requests.post(erigon_url, json=payload, timeout=5)

        if response.status_code == 200:
            data = response.json()
            sync_result = data.get("result", False)

            if sync_result:
                current_block = int(data.get("currentBlock", "0x0"), 16)
                highest_block = int(data.get("highestBlock", "0x0"), 16)
                peer_count = data.get("peerCount", 0)

                sync_progress = min(100.0, (current_block / highest_block) * 100) if highest_block > 0 else 100

                print(f"  Status: {'Syncing' if sync_result else 'Fully Synced'}")
                print(f"  Progress: {sync_progress:.1f}%")
                print(f"  Current Block: #{current_block:,}")
                print(f"  Highest Block: #{highest_block:,}")
                print(f"  Peer Count: {peer_count}")
            else:
                print("  Status: Fully Synced")
        else:
            print("  Status: ❌ Node not responding")
    except Exception as e:
        print(f"  ❌ Error: {e}")

    print()

    # Check Geth (port 8545 as backup)
    geth_url = "http://127.0.0.1:8545"

    try:
        print("--- GETH ---")
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_syncing",
            "params": [],
            "id": 1
        }

        response = requests.post(geth_url, json=payload, timeout=5)

        if response.status_code == 200:
            data = response.json()
            sync_result = data.get("result", False)

            if sync_result:
                current_block = int(data.get("currentBlock", "0x0"), 16)
                highest_block = int(data.get("highestBlock", "0x0"), 16)
                peer_count = data.get("peerCount", 0)

                sync_progress = min(100.0, (current_block / highest_block) * 100) if highest_block > 0 else 100

                print(f"  Status: {'Syncing' if sync_result else 'Fully Synced'}")
                print(f"  Progress: {sync_progress:.1f}%")
                print(f"  Current Block: #{current_block:,}")
                print(f"  Highest Block: #{highest_block:,}")
                print(f"  Peer Count: {peer_count}")
            else:
                print("  Status: Fully Synced")
        else:
            print("  Status: ❌ Node not responding")
    except Exception as e:
        print(f"  ❌ Error: {e}")

if __name__ == "__main__":
    check_node_status()