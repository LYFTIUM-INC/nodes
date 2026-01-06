# Memory Allocation Plan for Blockchain Nodes

## Current Memory Usage Analysis

### System Overview
- Total RAM: 64GB (65.8GB)
- Currently Used: 45GB (68%)
- Available: 17GB
- Swap Usage: 3.3GB (heavily used)

### Major Memory Consumers
1. **Erigon (Ethereum)**: 24.3% (16GB) - Running natively
2. **Cursor/IDE processes**: ~15% (10GB)
3. **Docker containers**: ~5GB
4. **System/Cache**: ~16GB

### Current Docker Nodes Status
- **Ethereum Light**: 65MB (allocated 6GB)
- **Arbitrum**: 13MB (allocated 6GB)
- **Base**: 61MB (allocated 6GB)
- **Avalanche**: 435MB (allocated 2GB)
- **Solana Dev**: 0B (allocated but not running)
- **MEV Boost**: 15MB

## Memory Optimization Strategy

### Phase 1: Immediate Actions
1. **Kill Cursor/IDE processes** to free ~10GB
2. **Clear system cache** to free ~5GB
3. **Stop unused containers** (Solana Dev)

### Phase 2: Deploy Missing Nodes with Constraints

#### Optimism Deployment (Total: 5GB)
- **op-geth**: 3GB (execution layer)
  - Cache: 1024MB
  - Max peers: 30
  - Snap sync mode
- **op-node**: 2GB (consensus layer)
  - Minimal P2P connections
  - Reduced cache

#### Polygon Deployment (Total: 6GB)
- **Heimdall**: 2GB (consensus layer)
  - Reduced cache
  - Limited peers
- **Bor**: 4GB (execution layer)
  - Cache: 2048MB
  - Snap sync
  - Limited peers: 30

### Phase 3: System-wide Optimizations

#### Memory Limits Per Node (Revised)
| Node | Current | Optimized | Notes |
|------|---------|-----------|-------|
| Ethereum (Erigon) | 16GB | 12GB | Reduce cache, peers |
| Solana | 6GB | 0GB | Stop dev instance |
| BSC | 4GB | 4GB | Keep as is |
| Avalanche | 2GB | 2GB | Keep as is |
| Arbitrum | 6GB | 4GB | Reduce allocation |
| Base | 6GB | 4GB | Reduce allocation |
| Optimism | - | 5GB | New deployment |
| Polygon | - | 6GB | New deployment |
| **Total** | 40GB | 37GB | Under 80% limit |

#### Cgroup Configuration
- Enable memory accounting
- Set hard limits per container
- Configure OOM killer priorities
- Enable memory pressure notifications

## Implementation Steps

1. **Prepare System**
   ```bash
   # Clear page cache
   sync && echo 3 > /proc/sys/vm/drop_caches
   
   # Kill unnecessary processes
   pkill -f cursor
   pkill -f node
   
   # Stop unused containers
   docker stop solana-dev
   ```

2. **Deploy Optimism**
   ```bash
   # Create optimized config
   # Deploy with memory limits
   ```

3. **Deploy Polygon**
   ```bash
   # Fix existing setup
   # Deploy with constraints
   ```

4. **Monitor & Alert**
   ```bash
   # Set up monitoring
   # Configure alerts at 80% usage
   ```

## Success Criteria
- Total memory usage < 51GB (80% of 64GB)
- All nodes syncing properly
- No OOM kills
- Stable performance