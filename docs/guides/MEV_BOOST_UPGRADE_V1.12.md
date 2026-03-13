# MEV-Boost Upgrade Runbook: v1.9 → v1.12+

**Purpose**: Step-by-step runbook for upgrading MEV-Boost from v1.9 to v1.12+.  
**Target**: Production LYFTIUM MEV infrastructure.  
**Reference**: [MEV-Boost Releases](https://github.com/flashbots/mev-boost/releases), [docs/research/WORLD_CLASS_MEV_INFRASTRUCTURE_2026.md](../research/WORLD_CLASS_MEV_INFRASTRUCTURE_2026.md)

---

## Prerequisites

- MEV-Boost currently at v1.9 (or earlier)
- Beacon node (Lighthouse) running and synced
- Consensus client connected to MEV-Boost
- Maintenance window (recommended: low-activity slot)

---

## Pre-Upgrade Checklist

- [ ] Backup current config and binary
- [ ] Verify beacon node health: `curl -s http://127.0.0.1:5052/eth/v1/node/syncing | jq`
- [ ] Note current MEV-Boost version: `mev-boost --version` or `docker exec mev-boost-foundation mev-boost --version`
- [ ] Ensure timing-games.yaml exists at `configs/mev-boost/timing-games.yaml`

---

## Step 1: Backup Configuration

```bash
# Systemd deployment
sudo cp /data/blockchain/nodes/configs/systemd/mev-boost.service /data/blockchain/nodes/configs/systemd/mev-boost.service.bak.$(date +%Y%m%d)
sudo cp /data/blockchain/mev-boost/mev-boost /data/blockchain/mev-boost/mev-boost.bak.v1.9 2>/dev/null || true

# Config backup
cp -r /data/blockchain/nodes/configs/mev-boost /data/blockchain/nodes/configs/mev-boost.bak.$(date +%Y%m%d)
```

---

## Step 2: Download MEV-Boost v1.12 Binary

```bash
cd /tmp
RELEASE="v1.12"
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && ARCH="amd64"
wget -O mev-boost-$RELEASE "https://github.com/flashbots/mev-boost/releases/download/${RELEASE}/mev-boost_${RELEASE}_linux_${ARCH}"
chmod +x mev-boost-$RELEASE
./mev-boost-$RELEASE --version  # Verify version
```

Or via Docker:
```bash
docker pull flashbots/mev-boost:1.12
```

---

## Step 3: Update Systemd Service (v1.12+ Flags)

Edit `configs/systemd/mev-boost.service` and apply:

1. **Add metrics** (v1.10+):
   ```
   --metrics --metrics-addr 127.0.0.1:18651
   ```

2. **Add config file** (v1.11+, optional for timing games):
   ```
   -config /data/blockchain/nodes/configs/mev-boost/timing-games.yaml -watch-config
   ```

3. **Replace binary path** if using local binary:
   ```
   ExecStart=/data/blockchain/mev-boost/mev-boost \
   ```

**Full ExecStart example (v1.12)**:
```bash
# Note: v1.12 rejects relay duplicates. When using -config, define relays ONLY in the YAML.
# Do NOT pass --relays when -config contains relays.
ExecStart=/data/blockchain/mev-boost/mev-boost \
    --mainnet \
    --addr 127.0.0.1:18551 \
    --metrics --metrics-addr 127.0.0.1:18651 \
    -config /data/blockchain/nodes/configs/mev-boost/timing-games.yaml -watch-config \
    --relay-check \
    --request-timeout-getheader 4950 \
    --request-timeout-getpayload 4500 \
    --request-timeout-regval 3000 \
    --request-max-retries 3 \
    --min-bid 0.01 \
    --loglevel info
```

---

## Step 4: Deploy New Binary

```bash
# Stop current MEV-Boost
sudo systemctl stop mev-boost

# Replace binary
sudo cp /tmp/mev-boost-v1.12 /data/blockchain/mev-boost/mev-boost
# Or keep existing path and overwrite

# Reload systemd
sudo systemctl daemon-reload

# Start with new version
sudo systemctl start mev-boost
```

---

## Step 5: Verify Upgrade

```bash
# Check service status
sudo systemctl status mev-boost

# Verify version
journalctl -u mev-boost -n 30 --no-pager | grep -i version

# Metrics endpoint (if --metrics enabled)
curl -s http://127.0.0.1:18651/metrics | head -20

# Relay check (should show relay registration)
journalctl -u mev-boost -n 100 --no-pager | grep -i relay
```

---

## Step 6: Prometheus Scrape (Optional)

Ensure Prometheus scrapes MEV-Boost metrics:

```yaml
# configs/monitoring/prometheus.yml
- job_name: 'mev-boost-metrics'
  static_configs:
    - targets: ['127.0.0.1:18651']
```

---

## Rollback Procedure

If issues occur after upgrade:

```bash
# 1. Stop MEV-Boost
sudo systemctl stop mev-boost

# 2. Restore previous binary
sudo cp /data/blockchain/mev-boost/mev-boost.bak.v1.9 /data/blockchain/mev-boost/mev-boost

# 3. Restore systemd service (remove --metrics, -config)
sudo cp /data/blockchain/nodes/configs/systemd/mev-boost.service.bak.YYYYMMDD /data/blockchain/nodes/configs/systemd/mev-boost.service

# 4. Reload and start
sudo systemctl daemon-reload
sudo systemctl start mev-boost

# 5. Verify
sudo systemctl status mev-boost
journalctl -u mev-boost -n 50 --no-pager
```

**Important**: v1.9 does NOT support `--metrics`, `-config`, or `-watch-config`. Remove these flags when rolling back.

---

## Docker Upgrade

For Docker-based deployment (`mev-foundation-complete.yml`):

```bash
# 1. Update image tag
# Edit: image: flashbots/mev-boost:1.12

# 2. Pull and recreate
docker-compose -f configs/mev-foundation-complete.yml pull mev-boost
docker-compose -f configs/mev-foundation-complete.yml up -d mev-boost

# 3. Verify
docker logs mev-boost-foundation -n 50
```

---

## v1.12 New Features

| Feature | Flag/Config | Notes |
|---------|-------------|-------|
| Relay multiplexing | `mux:` in YAML | Per-validator-group relay sets |
| Timing games | `enable_timing_games: true` | +2–5% revenue |
| Timeout getHeader | `timeout_get_header_ms: 950` | Flashbots default; internal timing budget (< CL get_header deadline) |
| Metrics | `--metrics --metrics-addr 127.0.0.1:18651` | Prometheus endpoints |
| Config file | `-config path -watch-config` | Hot-reload config changes |

---

## References

- [MEV-Boost v1.12 Release](https://github.com/flashbots/mev-boost/releases/tag/v1.12)
- [MEV-Boost v1.11 Timing Games](https://github.com/flashbots/mev-boost/releases/tag/v1.11)
- [Config Example](https://github.com/flashbots/mev-boost/blob/develop/config.example.yaml)
- [Timing Games Docs](https://github.com/flashbots/mev-boost/blob/develop/docs/timing-games.md)

---

**Owner**: Infrastructure / MEV Team  
**Last Updated**: 2026-03-09
