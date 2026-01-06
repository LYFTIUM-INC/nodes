# Arbitrum Node Fix Summary

## Issue
The Arbitrum node deployment was failing with the error: "Fatal configuration error: unknown flag: --l1.url"

## Root Cause
The docker-compose.yml file was using incorrect command-line flags for the Arbitrum Nitro node. Specifically:
- `--l1.url` is not a valid flag in Arbitrum Nitro
- `--l2.chain-id` should be `--chain.id`

## Solution Applied

### Changed Flags:
1. **L1 Connection**: `--l1.url` → `--parent-chain.connection.url`
2. **Chain ID**: `--l2.chain-id` → `--chain.id`
3. **Added persistent storage**: `--persistent.chain=/data`
4. **Added initialization snapshot**: 
   - `--init.url=https://snapshot.arbitrum.foundation/arb1/nitro-pruned.tar`
   - `--init.latest=pruned`

### Final Configuration:
```yaml
command: >
  nitro
  --parent-chain.connection.url=http://erigon:8545
  --chain.id=42161
  --http.addr=0.0.0.0
  --http.port=8547
  --http.api=net,web3,eth,arb
  --ws.addr=0.0.0.0
  --ws.port=8548
  --persistent.chain=/data
  --node.data-availability.enable
  --node.data-availability.rest-aggregator.enable
  --node.data-availability.rest-aggregator.urls=https://arb1.arbitrum.io/das-servers
  --init.url=https://snapshot.arbitrum.foundation/arb1/nitro-pruned.tar
  --init.latest=pruned
```

## Key Points:
1. The node will connect to the Ethereum mainnet via the Erigon node running in the same docker network
2. Chain ID 42161 is for Arbitrum One mainnet
3. The node will download a pruned snapshot on first run to speed up sync
4. Data Availability is enabled with the official Arbitrum DAS servers
5. All data will be persisted to `/data` which is mapped to the host volume

## To Apply the Fix:
```bash
cd /data/blockchain/nodes/deployment
docker-compose up -d arbitrum-node
```

## Verification:
After starting, you can check if the node is running correctly:
```bash
# Check logs
docker logs arbitrum-node -f

# Test RPC connection
curl -X POST http://localhost:8548 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

The node should now start successfully and begin syncing with the Arbitrum network.