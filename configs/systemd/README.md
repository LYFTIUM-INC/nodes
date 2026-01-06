# Blockchain Node Service Templates

This directory contains production-ready systemd service templates for blockchain infrastructure.

## Services

| Service | Description | Port | Status |
|----------|-------------|------|--------|
| `geth.service` | Geth Execution Client | HTTP: 8549, WS: 8550, Engine: 8554 | ✅ Production |
| `reth.service` | Reth Execution Client | HTTP: 8557, WS: 8558, Engine: 8553 | ✅ Template |
| `erigon.service` | Erigon Execution Client | HTTP: 8545, WS: 8546, Engine: 8552 | ⚠️ Backup |
| `lighthouse.service` | Lighthouse Consensus | HTTP: 5052, P2P: 9003 | ✅ Production |
| `mev-boost.service` | MEV-Boost Relay | HTTP: 18551 | ✅ Production |

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
ss -tlnp | grep -E "8549|8554|5052"
```

### Restart all services
```bash
sudo systemctl restart lighthouse.service geth.service mev-boost.service
```

## Service Dependencies

```
Lighthouse (Consensus)
    │
    ├─> Geth (Execution Layer) - Primary
    │     └─> Engine API: 127.0.0.1:8554
    │
    └─> JWT Secret: /data/blockchain/storage/jwt-common/jwt-secret.hex

MEV-Boost
    └─> Geth (for block submission)
```
