#!/bin/bash
# Real-time sync progress tracker

echo "=== Blockchain Sync Progress Tracker ===" | tee -a /data/blockchain/nodes/logs/sync-tracker.log
echo "Started: $(date)" | tee -a /data/blockchain/nodes/logs/sync-tracker.log

while true; do
    echo -e "\n--- $(date) ---" | tee -a /data/blockchain/nodes/logs/sync-tracker.log
    
    # Check Ethereum execution stage
    eth_progress=$(journalctl -u ethereum -n 1 | grep "Execution" | tail -1 | grep -o "blk=[0-9]*" | cut -d'=' -f2 || echo "0")
    if [[ -n "$eth_progress" && "$eth_progress" != "0" ]]; then
        echo "Ethereum: Executing block $eth_progress (stage 4/6)" | tee -a /data/blockchain/nodes/logs/sync-tracker.log
    else
        echo "Ethereum: Still syncing (not yet executing)" | tee -a /data/blockchain/nodes/logs/sync-tracker.log
    fi
    
    # Check RPC responses
    for port in 8545 8546 8547 8548; do
        case $port in
            8545) chain="Ethereum" ;;
            8546) chain="Optimism" ;;
            8547) chain="Arbitrum" ;;
            8548) chain="Base" ;;
        esac
        
        result=$(curl -s -X POST http://127.0.0.1:$port -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        
        if [[ -n "$result" ]]; then
            block=$((16#${result#0x}))
            if [[ $block -gt 0 ]]; then
                echo "$chain: Block $block ✓" | tee -a /data/blockchain/nodes/logs/sync-tracker.log
            else
                echo "$chain: Still at block 0 (waiting for sync)" | tee -a /data/blockchain/nodes/logs/sync-tracker.log
            fi
        else
            echo "$chain: No RPC response" | tee -a /data/blockchain/nodes/logs/sync-tracker.log
        fi
    done
    
    # Check if any node has progressed past block 0
    any_synced=false
    for port in 8545 8546 8547 8548; do
        result=$(curl -s -X POST http://127.0.0.1:$port -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        if [[ -n "$result" ]]; then
            block=$((16#${result#0x}))
            if [[ $block -gt 0 ]]; then
                any_synced=true
                break
            fi
        fi
    done
    
    if [[ "$any_synced" == true ]]; then
        echo "✓ SUCCESS: At least one node has progressed past block 0!" | tee -a /data/blockchain/nodes/logs/sync-tracker.log
        break
    fi
    
    sleep 30
done

echo "Monitoring complete. Check full log at /data/blockchain/nodes/logs/sync-tracker.log"