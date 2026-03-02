# Lighthouse Database Corruption Incident Report

**Date**: 2026-03-01
**Severity**: Critical
**Status**: Resolved (Recovery in Progress)
**Service**: Lighthouse Beacon Node (Consensus Layer)

## Summary

The Lighthouse beacon node experienced a critical LevelDB database corruption after 8 hours and 34 minutes of operation. The corruption resulted in 45,881+ failed restart attempts before intervention.

## Timeline

| Time (PST) | Event |
|------------|-------|
| ~02:00 | Lighthouse started successfully (last known good state) |
| 10:30 | Database corruption detected - missing files 000005.ldb through 000008.ldb |
| 10:30-19:43 | Automatic restart loop (45,881 attempts) |
| 19:43 | Service stopped and recovery initiated |

## Root Cause Analysis

### Primary Cause
**Memory pressure during database compaction** caused incomplete LevelDB compaction transactions.

### Evidence
1. High swap usage: 13GB/62GB (21%)
2. Zram at critical capacity: 11.3GB/15.7GB (72%)
3. Missing intermediate database files (000005-000008.ldb) typical of interrupted compaction
4. `--auto-compact-db true` setting may have triggered compaction under memory pressure

### Contributing Factors
- No effective memory limits on Lighthouse service
- Aggressive restart loop exacerbated system load
- No viable backups available for recovery
- Database was 18GB with aggressive compaction settings

## Impact

- **Consensus Layer**: Completely down - no beacon chain sync
- **Execution Layer**: Erigon operational but cannot communicate with consensus
- **MEV Operations**: Disabled - no block production capability
- **Data Loss**: Complete consensus database (18GB) - requires resync from checkpoint

## Resolution

### Immediate Actions Taken
1. Stopped restart loop: `systemctl stop lighthouse.service && systemctl disable lighthouse.service`
2. Backed up corrupted database: `/data/blockchain/storage/lighthouse/backups/corrupted-20260301-195837`
3. Cleaned database directories for fresh sync
4. Verified checkpoint sync URL availability

### Recovery Method
**Checkpoint Sync** from https://sync.invis.tools
- Expected checkpoint sync time: 5-15 minutes
- Expected backfill time: 2-4 hours
- Expected full sync to head: 6-7 days

## Preventive Measures

### 1. Memory Management (Implemented)
```bash
# /etc/systemd/system/lighthouse.service.d/memory.conf
[Service]
MemoryMax=12G
MemoryHigh=10G
MemorySwapMax=4G
```

### 2. Restart Loop Prevention (Implemented)
```bash
# /etc/systemd/system/lighthouse.service.d/restart.conf
[Service]
StartLimitIntervalSec=300
StartLimitBurst=5
RestartSec=30
```

### 3. Automated Backups (Recommended)
Weekly backups via cron job to preserve database state.

### 4. Monitoring & Alerting (Recommended)
- Alert on memory pressure > 85%
- Alert on restart loops > 3 in 5 minutes
- Alert on LevelDB corruption messages in logs

## Lessons Learned

1. **Memory Limits Critical**: Blockchain nodes need explicit memory limits to prevent system-wide pressure
2. **Restart Loops Dangerous**: Uncontrolled restart loops can mask the root cause and waste resources
3. **Backups Essential**: No viable backups meant complete resync was the only option
4. **Checkpoint Sync Valuable**: Having reliable checkpoint sync URLs reduces recovery time from weeks to hours

## Verification Steps

After recovery, verify with:
```bash
# Check sync status
curl -s http://127.0.0.1:5052/eth/v1/node/syncing | jq

# Check finality
curl -s http://127.0.0.1:5052/eth/v1/beacon/states/head/finality_checkpoints | jq

# Monitor memory
watch -n 5 'free -h && ps aux | grep lighthouse | grep -v grep'
```

## Related Files

- Startup script: `/data/blockchain/nodes/consensus/lighthouse/start-lighthouse-beacon.sh`
- Corrupted backup: `/data/blockchain/storage/lighthouse/backups/corrupted-20260301-195837/`
- Service file: `/etc/systemd/system/lighthouse.service`

## References

- [Lighthouse Database Management](https://lighthouse-book.sigmaprime.io/database.html)
- [LevelDB Corruption Recovery](https://github.com/google/leveldb/blob/main/doc/impl.md)
- [Ethereum Checkpoint Sync](https://eth-clients.github.io/checkpoint-sync-endpoints/)

---

**Report Generated**: 2026-03-01 20:00 PST
**Author**: Automated Infrastructure Analysis
**Review Status**: Pending
