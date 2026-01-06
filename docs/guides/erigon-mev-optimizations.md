# Erigon MEV Performance Optimizations

## Current Status
- **Sync Method**: OtterSync (Snapshot sync) - Already optimal
- **Database**: MDBX with 16KB page size
- **Estimated Sync Completion**: ~3 minutes behind chain tip as of last check

## Implemented Optimizations

### 1. System-level Optimizations
- **VM Swappiness**: Set to 1 (minimize swapping)
- **Dirty Ratio**: Reduced to 3% (faster write-backs)
- **Dirty Background Ratio**: Set to 2%
- **VFS Cache Pressure**: Set to 50 (balanced caching)
- **Transparent Huge Pages**: Set to 'madvise' mode
- **I/O Scheduler**: Set to 'none' for SSD
- **Read-ahead**: Increased to 4096KB

### 2. Erigon Configuration
- **Prune Mode**: Full (reduces disk usage)
- **Max Peers**: 150 (high connectivity)
- **DB Page Size**: 16KB (optimal for MDBX)
- **Torrent Download Rate**: 1GB/s
- **Torrent Upload Rate**: 512MB/s

## MEV-Specific Optimizations

### 1. RPC Configuration
```bash
--http.api=eth,net,web3,txpool,erigon,debug,engine
```
- Includes `debug` API for transaction tracing
- Includes `engine` API for MEV-boost integration
- `txpool` API for mempool monitoring

### 2. Transaction Pool Settings
```bash
--txpool.accountslots=16
--txpool.globalslots=15000
--txpool.globalqueue=15000
--txpool.pricelimit=1
--txpool.pricebump=10
```
- Large global slots for better mempool visibility
- Low price limit (1 wei) to see all transactions
- 10% price bump for replacement transactions

### 3. Performance Monitoring
Use the created monitoring script:
```bash
/data/blockchain/nodes/monitor-erigon-sync.sh
```

## Post-Sync Optimizations

Once sync is complete:

### 1. Enable Additional Caching
```bash
# Add to Erigon command:
--cache=8192  # 8GB cache for state
--cache.gc=0  # Disable GC during critical operations
```

### 2. Configure Rate Limiting
```bash
# For public RPC (if needed):
--rpc.gascap=50000000
--rpc.txfeecap=1
```

### 3. MEV Infrastructure Setup
1. **MEV-Boost Integration**:
   - Connect to Engine API at `http://localhost:8551`
   - JWT secret at `/data/blockchain/storage/erigon-fresh/jwt.hex`

2. **Flashbots Bundle Submission**:
   - Use debug_traceCall for bundle simulation
   - Monitor mempool via txpool_content

3. **Low-Latency Access**:
   - Use Unix socket for local connections (if configured)
   - Implement connection pooling for RPC clients
   - Consider running RPC proxy with caching

## Monitoring Commands

```bash
# Check sync status
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545

# Get latest block
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Check mempool size
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' \
  http://localhost:8545

# Monitor peers
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://localhost:8545
```

## Troubleshooting

If sync is slow:
1. Check disk I/O: `iostat -x 1`
2. Monitor memory: `free -h`
3. Check peer count in logs
4. Verify snapshot downloads completed
5. Consider restarting with `--snap.stop=false` if snapshots stalled

## Security Notes
- Engine API JWT is configured for secure MEV-boost communication
- Consider firewall rules for RPC ports
- Use SSL/TLS proxy for external RPC access