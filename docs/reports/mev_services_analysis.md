# MEV Services Analysis Report
Generated: 2025-07-01

## Summary of Issues Found

### 1. Syntax Errors in Service Files

The following services have syntax errors (lines without '=' in [Service] section):
- **mev-automated.service** (line 35): `EOF < /dev/null`
- **mev-boost-fixed.service** (line 38): `EOF < /dev/null`
- **mev-data-ingestion.service** (line 38): `EOF < /dev/null`
- **mev-mempool-monitor.service** (line 22): `EOF < /dev/null`
- **mev-node.service** (line 26): `EOF < /dev/null`

### 2. Missing Binaries/Scripts

- **mev-node.service**: `/tmp/start_mev_node.sh` - File does not exist
- **erigon-bsc.service**: `/opt/blockchain-data/bin/erigon-bsc` - Binary not found
- **erigon-polygon.service**: `/opt/blockchain-data/bin/erigon-polygon` - Binary not found
- **erigon-secure.service**: `/usr/local/bin/erigon` - Symlink exists but points to restricted path
- **mev-execution-bot.service**: Referenced script `mev_execution_bot.py` may not exist in expected location

### 3. Missing Environment Files

- **wallet-manager.service**: `/tmp/wallet-service-env` - Environment file not found

### 4. Permission Issues

- **mev-wallet-service.service**: Service file cannot be read (permission denied)
- **erigon-mev.service**: Service file cannot be read (permission denied)
- **erigon-optimized.service**: Service file cannot be read (permission denied)

### 5. Missing Dependencies

- **mev-orchestrator.service**: Depends on `mev-wallet-service.service` which doesn't exist or has permission issues

### 6. Service Status Summary

#### Running Services:
- ✅ **mev-boost.service**: Active and running correctly
- ✅ **erigon.service**: Active and running

#### Failed Services:
- ❌ **wallet-latency-exporter.service**: Exit code 2 (invalid argument)
- ❌ **wallet-manager.service**: Failed to load environment file

#### Inactive Services (Disabled):
- ⚠️ mev-arbitrage-engine.service
- ⚠️ mev-automated.service
- ⚠️ mev-backend.service
- ⚠️ mev-boost-fixed.service
- ⚠️ mev-data-ingestion.service
- ⚠️ mev-execution-bot.service
- ⚠️ mev-mempool-monitor.service
- ⚠️ mev-node.service
- ⚠️ mev-orchestrator.service
- ⚠️ mev-scanner.service
- ⚠️ ethereum.service
- ⚠️ blockchain-monitoring-secure.service
- ⚠️ wallet-manager-api.service

#### Constantly Restarting:
- 🔄 **mev-engine.service**: Exits immediately, auto-restarting
- 🔄 **mev-monitor.service**: Exits after running, auto-restarting every 5 minutes

## Detailed Issues by Service

### mev-automated.service
- **Syntax Error**: Line 35 contains `EOF < /dev/null` which is invalid
- **Working Directory**: `/opt/blockchain-data/mempool/services`
- **Script**: `mev_data_ingestion.py` - Need to verify if this exists

### mev-boost-fixed.service
- **Syntax Error**: Line 38 contains `EOF < /dev/null`
- **Binary**: `/usr/local/bin/mev-boost` exists and is executable

### mev-data-ingestion.service
- **Syntax Error**: Line 38 contains `EOF < /dev/null`
- **Python**: Uses conda environment at `/home/lyftium/.conda/envs/mev/bin/python`
- **Script**: `services/mev_data_ingestion.py`

### mev-engine.service
- **Status**: Constantly restarting (exits with status 0)
- **Binary**: `/data/blockchain/mev-infra/_build/default/bin/main_service.exe` exists
- **Environment**: Uses `/etc/systemd/system/mev-engine.env` (exists)

### mev-execution-bot.service
- **Override**: Has override.conf that changes the ExecStart
- **Python**: Uses both miniconda and conda environments (conflicting)
- **Module**: `mempool.services.mev_execution_bot`

### mev-mempool-monitor.service
- **Syntax Error**: Line 22 contains `EOF < /dev/null`
- **Script**: `simple_mempool_monitor.py`

### mev-node.service
- **Syntax Error**: Line 26 contains `EOF < /dev/null`
- **Missing Binary**: `/tmp/start_mev_node.sh` does not exist

### mev-orchestrator.service
- **Missing Dependency**: Requires `mev-wallet-service.service` which is inaccessible

### wallet-latency-exporter.service
- **Status**: Failed with exit code 2 (invalid argument)
- **Working Directory**: `/opt/wallet-manager`

### wallet-manager.service
- **Missing Environment File**: `/tmp/wallet-service-env`
- **Override**: Complex bash command in override.conf
- **Status**: Failing to start due to missing environment file

## Recommendations for Fixes

1. **Fix Syntax Errors**: Remove `EOF < /dev/null` lines from service files
2. **Create Missing Scripts**: 
   - Create `/tmp/start_mev_node.sh` or update service to use correct path
   - Verify Python scripts exist in their expected locations
3. **Fix Environment Files**:
   - Create `/tmp/wallet-service-env` or update to permanent location
4. **Resolve Permission Issues**:
   - Check permissions on service files that can't be read
   - Fix ownership/permissions on directories
5. **Install Missing Binaries**:
   - Install erigon-bsc and erigon-polygon binaries
6. **Fix Dependencies**:
   - Ensure mev-wallet-service.service exists and is readable
7. **Debug Failing Services**:
   - Investigate why mev-engine.service exits immediately
   - Fix wallet-latency-exporter arguments