#!/usr/bin/env python3
import sys
sys.path.append('/data/blockchain/nodes/failover')
from circuit_breaker import FailoverManager

try:
    failover = FailoverManager()
    
    # Test each blockchain
    blockchains = ['ethereum', 'arbitrum', 'optimism', 'base', 'bsc']
    
    for blockchain in blockchains:
        try:
            result = failover.rpc_call(blockchain, "eth_blockNumber")
            if result and 'result' in result:
                print(f"✓ {blockchain}: Block {int(result['result'], 16)}")
            else:
                print(f"✗ {blockchain}: Failed to get block number")
        except Exception as e:
            print(f"✗ {blockchain}: Error - {e}")
    
    # Test Solana
    try:
        solana_cb = failover.get_endpoint("solana")
        if solana_cb:
            health = solana_cb.call("health", "GET")
            if health:
                print(f"✓ solana: Health check passed")
            else:
                print(f"✗ solana: Health check failed")
    except Exception as e:
        print(f"✗ solana: Error - {e}")
    
    # Print status
    status = failover.get_all_status()
    print("\nCircuit Breaker Status:")
    for name, cb_status in status.items():
        state = cb_status['state']
        color = '✓' if state == 'closed' else '!' if state == 'half_open' else '✗'
        print(f"  {color} {name}: {state}")
        
except Exception as e:
    print(f"Error testing failover: {e}")
    sys.exit(1)
