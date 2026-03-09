# Blockchain Node Service Templates

This directory contains production-ready systemd service templates for blockchain infrastructure.

## Services

| Service | Description | Port | Role |
|----------|-------------|------|--------|
| `erigon.service` | Erigon Execution Client | HTTP: 8545, WS: 8546, Engine: 8552 | **PRIMARY** for MEV |
| `lighthouse-beacon.service` | Lighthouse Consensus | HTTP: 5052, P2P: 9003 | Consensus layer |
| `mev-boost.service` | MEV-Boost Relay | HTTP: 18551 | Proposer-critical |
| `geth.service` | Geth Execution Client | HTTP: 8549, WS: 8550, Engine: 8554 | Alternative/backup |
| `reth.service` | Reth Execution Client | HTTP: 8557, WS: 8558, Engine: 8553 | Alternative/template |

## Installation

To install/update a service:

```bash
# Copy service file to systemd
sudo cp configs/systemd/[service].service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service (start on boot)
sudo systemctl enable [service].service

# Start service
sudo systemctl start [service].service

# Check status
sudo systemctl status [service].service
```

### Lighthouse Beacon Drop-in (DB Integrity Check)

If using lighthouse-beacon.service, install the pre-restart DB integrity check drop-in:

```bash
sudo mkdir -p /etc/systemd/system/lighthouse-beacon.service.d
sudo cp configs/systemd/lighthouse-beacon.service.d/db-check.conf /etc/systemd/system/lighthouse-beacon.service.d/
sudo systemctl daemon-reload
```

This runs `lighthouse-db-integrity-check.sh` before each start to prevent restart loops from corrupted LevelDB.

## JWT Secret Management

All services use the canonical JWT secret location:

```
/data/blockchain/storage/jwt-common/jwt-secret.hex
```

Symlinks for backward compatibility:
- `/data/blockchain/storage/jwt-secret-common.hex` → `jwt-common/jwt-secret.hex`
- `/data/blockchain/storage/erigon/jwt.hex` → `jwt-common/jwt-secret.hex`

## Port Allocation

| Purpose | Geth | Erigon | Reth | Lighthouse |
|---------|------|--------|------|------------|
| HTTP RPC | 8549 | 8545 | 8557 | - |
| WebSocket | 8550 | 8546 | 8558 | - |
| Engine API | 8554 | 8552 | 8553 | - |
| Metrics | 6061 | 6062 | 6063 | 5054 |
| P2P Discovery | 30309 | 30303 | 30313 | 9003 |
| P2P Listen | - | - | - | 9004 |

## Health Check

Run the health check script:

```bash
./scripts/monitoring/blockchain-health-check.sh
```

## Troubleshooting

### Service won't start
```bash
sudo journalctl -u [service].service -n 50
```

### JWT authentication errors
```bash
# Verify JWT secret is accessible
ls -la /data/blockchain/storage/jwt-common/jwt-secret.hex
ls -la /data/blockchain/storage/jwt-secret-common.hex
```

### Check port bindings
```bash
ss -tlnp | grep -E "8545|8552|5052|18551"
```

### Restart all services
```bash
sudo systemctl restart lighthouse-beacon.service erigon.service mev-boost.service
```

## Service Dependencies

```
Lighthouse (Consensus) - port 5052
    │
    ├─> Erigon (Execution Layer) - PRIMARY
    │     └─> Engine API: 127.0.0.1:8552
    │
    └─> JWT Secret: /data/blockchain/storage/jwt-common/jwt-secret.hex

MEV-Boost - port 18551
    └─> Erigon (for block submission)
```
