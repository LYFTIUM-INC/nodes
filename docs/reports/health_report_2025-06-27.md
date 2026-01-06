# Blockchain Node & MEV Infrastructure Health Report
**Date:** 2025-06-27 18:45 PDT

## Executive Summary

### Critical Issues Found:
1. **Most blockchain nodes are DOWN or experiencing issues**
2. **MEV infrastructure services are failing due to configuration errors**
3. **Nginx SSL certificate permission issues preventing reverse proxy from working**
4. **High system load with multiple services in restart loops**

---

## System Resources

### CPU & Memory
- **Load Average:** 6.29, 8.80, 8.96 (elevated but manageable)
- **Memory Usage:** 38GB of 62GB (61%) - Adequate
- **Top Processes:**
  - node: 115.4% CPU, 12.0% MEM (PID: 817177)
  - avalanche: 76.9% CPU, 6.2% MEM (PID: 6298)
  - erigon: 53.8% CPU, 36.7% MEM (PID: 812124)

### Disk Usage
- **Main Disk (/):** 176GB of 248GB used (71%)
- **Data Disk (/data/blockchain):** 1.3TB of 1.8TB used (68%)

---

## Blockchain Node Status

### ✅ Operational Nodes

1. **Solana**
   - Container: solana-dev (UP 4 hours)
   - RPC Port: 8899 ONLINE
   - Current Slot: 199,568

2. **BSC Recovery**
   - Container: bsc-recovery (UP 4 hours)
   - RPC Port: 8585 ONLINE  
   - Block: 0 (appears to be syncing or in recovery mode)

3. **Avalanche**
   - Container: avalanche-node (UP 4 hours)
   - RPC Port: 9650 (timing out on RPC calls)
   - Process running with high CPU usage

4. **Optimism**
   - Containers: simple_op-node_1, simple_op-geth_1 (UP 4 hours)
   - RPC Port: 8550 (timing out)

5. **Lighthouse (Ethereum Beacon)**
   - Container: lighthouse-production (UP 4 hours)
   - Port: 5052 listening

### ❌ Failed/Down Nodes

1. **Ethereum (Erigon)**
   - Process running (PID: 812124) using 36.7% memory
   - RPC Port: 8545 NOT RESPONDING (timeout)
   - Ports 30303, 8546, 8547 are listening

2. **Polygon Heimdall**
   - Container: polygon-heimdall (Restarting loop)
   - Error: Services stopping immediately after start

3. **Arbitrum**
   - Container: arbitrum-mev-node (Restarting loop)
   - Critical Error: Missing beacon chain RPC URL configuration
   - Cannot connect to L1 Ethereum (port 8545 connection refused)

4. **Ethereum Geth**
   - Container: ethereum-geth (Exited 18 hours ago)

5. **BSC Node**
   - Container: bsc-node (Exited 20 hours ago)

---

## MEV Infrastructure Status

### Service Status Summary

| Service | Status | Issue |
|---------|--------|-------|
| mev-engine | Inactive (dead) | Stopped after 6min 47s runtime |
| mev-mempool-monitor | Failing (restart loop) | Working directory not found |
| mev-monitor | Inactive (dead) | Not running |
| mev-orchestrator | Inactive (dead) | Dependency failure |
| mev-scanner | Inactive (dead) | Service file syntax error |
| mev-wallet-service | Failing (restart loop) | Standard output setup failure |

### Common Issues:
1. **Service File Syntax Errors:** Multiple services have "Missing '='" errors
2. **Directory Issues:** Services failing to find working directories
3. **Output Configuration:** Services unable to set up standard output

---

## Network Services

### Nginx Reverse Proxy
- **Status:** DOWN
- **Critical Error:** SSL certificate permission denied
- **Path:** `/etc/letsencrypt/live/arbitrum.rpc.lyftium.com/fullchain.pem`
- **Impact:** No HTTPS access to RPC endpoints

### Docker
- **Status:** ACTIVE (running)
- **Uptime:** 4 hours 22 minutes
- **Container Count:** 11 containers (mix of running, restarting, and exited)

### Open Ports
- **RPC Ports:** 8545, 8546, 8547, 8550, 8585, 8899, 9650
- **P2P Ports:** 30303, 39393, 44321-44323
- **Web Ports:** 80, 443, 8080, 8081
- **Other:** 5052 (beacon), 9000-9003

---

## Recommendations for Immediate Action

### 1. Critical Fixes (Do First)
- [ ] Fix Nginx SSL certificate permissions: `sudo chmod 644 /etc/letsencrypt/live/*/fullchain.pem`
- [ ] Fix MEV service file syntax errors in `/etc/systemd/system/`
- [ ] Configure Arbitrum beacon URL: `--parent-chain.blob-client.beacon-url`
- [ ] Restart Ethereum/Erigon node (appears hung)

### 2. Service Repairs
- [ ] Create missing working directories for MEV services
- [ ] Fix StandardOutput configuration in systemd service files
- [ ] Resolve MEV orchestrator dependency issues
- [ ] Investigate Polygon Heimdall restart loop

### 3. Monitoring Setup
- [ ] Implement health check monitoring for all RPC endpoints
- [ ] Set up alerts for service failures
- [ ] Create automatic restart scripts with backoff
- [ ] Monitor disk space (68% usage on data volume)

### 4. Long-term Improvements
- [ ] Upgrade nodes that have been down for extended periods
- [ ] Implement proper logging rotation
- [ ] Set up centralized monitoring dashboard
- [ ] Create backup RPC endpoints for critical services

---

## Command Reference

### Check Service Status
```bash
systemctl status mev-*.service
docker ps -a
```

### Fix SSL Permissions
```bash
sudo chmod -R 755 /etc/letsencrypt/live/
sudo chmod 644 /etc/letsencrypt/live/*/fullchain.pem
```

### Restart Failed Services
```bash
sudo systemctl daemon-reload
sudo systemctl restart mev-engine mev-wallet-service
docker restart polygon-heimdall arbitrum-mev-node
```

### Monitor Logs
```bash
journalctl -f -u mev-*
docker logs -f [container-name]
```

---

**Report Generated:** 2025-06-27 18:45:23 PDT