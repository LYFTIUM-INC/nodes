# Manual Setup Guide for MEV & Blockchain Data Engineering Infrastructure

## IMMEDIATE EXECUTION STEPS

Since the bash environment has issues, follow these exact commands in your terminal:

### 1. Make Scripts Executable
```bash
cd /data/blockchain/nodes
find . -name "*.sh" -exec chmod +x {} \;
```

### 2. Check Current System Status
```bash
# Check resources
free -h
nproc
df -h /data/blockchain

# Check Docker
systemctl status docker
docker --version
docker-compose --version
```

### 3. Install Dependencies (if needed)
```bash
# Install Docker if not present
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    sudo systemctl enable docker
    sudo systemctl start docker
fi

# Install Docker Compose if needed
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi
```

### 4. Create Storage Directories
```bash
sudo mkdir -p /data/blockchain/storage/{erigon,base,arbitrum,optimism,solana}
sudo chown -R $USER:$USER /data/blockchain
```

### 5. Clone All Repositories
```bash
cd /data/blockchain/nodes

# Erigon v3.0.5 (CRITICAL for MEV)
git clone https://github.com/erigontech/erigon.git ethereum/erigon/source
cd ethereum/erigon/source
git checkout v3.0.5
cd ../../..

# Base L2
git clone https://github.com/base-org/node.git base/source

# Arbitrum
git clone https://github.com/OffchainLabs/nitro.git arbitrum/source

# Optimism
git clone https://github.com/ethereum-optimism/optimism.git optimism/source
git clone https://github.com/smartcontracts/simple-optimism-node.git optimism/simple

# MEV-Boost
git clone https://github.com/flashbots/mev-boost.git mev-boost/source

# Solana
git clone https://github.com/solana-labs/solana.git solana/source
```

### 6. Install Go and Build Erigon
```bash
# Install Go 1.23.4
cd /tmp
wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
export PATH=$PATH:/usr/local/go/bin

# Build Erigon
cd /data/blockchain/nodes/ethereum/erigon/source
make -j2 BUILD_TAGS="nosqlite,noboltdb" erigon

# Create symlink
sudo ln -sf $(pwd)/build/bin/erigon /usr/local/bin/erigon

# Verify build
erigon --version
```

### 7. Pull Docker Images
```bash
cd /data/blockchain/nodes

# Pull all images in parallel
docker pull flashbots/mev-boost:1.8.0 &
docker pull ghcr.io/base-org/node:latest &
docker pull offchainlabs/nitro-node:v3.6.5-89cef87 &
docker pull ethereumoptimism/op-node:latest &
docker pull solanalabs/solana:v1.18.22 &
docker pull prom/prometheus:latest &
docker pull grafana/grafana:latest &

# Wait for all pulls to complete
wait
```

### 8. Start Services in Stages

#### Stage 1: Ethereum Erigon (CRITICAL FIRST)
```bash
# Build custom Erigon container
docker-compose build erigon

# Start Erigon
docker-compose up -d erigon

# Monitor startup
docker-compose logs -f erigon &

# Wait for RPC to be available (may take 5-10 minutes)
while ! curl -s http://localhost:8545 > /dev/null; do
    echo "Waiting for Erigon RPC..."
    sleep 30
done
echo "✅ Erigon RPC is responding!"
```

#### Stage 2: MEV-Boost
```bash
docker-compose up -d mev-boost
sleep 30

# Verify MEV-Boost
curl -s http://localhost:18550 && echo "✅ MEV-Boost running"
```

#### Stage 3: L2 Nodes (Start one at a time)
```bash
# Base L2
docker-compose up -d base-node
sleep 60

# Arbitrum L2
docker-compose up -d arbitrum-node
sleep 60

# Optimism L2  
docker-compose up -d optimism-node
sleep 60
```

#### Stage 4: Development Services
```bash
# Solana development cluster
docker-compose up -d solana-dev
sleep 30
```

#### Stage 5: Monitoring
```bash
docker-compose up -d prometheus grafana
```

### 9. Verification Commands

#### Check All Services
```bash
# Container status
docker-compose ps

# Test all RPC endpoints
curl -X POST -H "Content-Type: application/json" --data '{"method":"web3_clientVersion","params":[],"id":1,"jsonrpc":"2.0"}' http://localhost:8545
curl -X POST -H "Content-Type: application/json" --data '{"method":"web3_clientVersion","params":[],"id":1,"jsonrpc":"2.0"}' http://localhost:8547
curl -X POST -H "Content-Type: application/json" --data '{"method":"web3_clientVersion","params":[],"id":1,"jsonrpc":"2.0"}' http://localhost:8548
curl -X POST -H "Content-Type: application/json" --data '{"method":"web3_clientVersion","params":[],"id":1,"jsonrpc":"2.0"}' http://localhost:8550
curl http://localhost:8899
curl http://localhost:18550
curl http://localhost:3000
curl http://localhost:9090
```

#### Quick Status Check
```bash
./quick-status.sh
```

### 10. Expected Results

After successful setup, you should see:

✅ **8 Services Running:**
- ethereum-erigon (port 8545)
- mev-boost (port 18550) 
- base-node (port 8547)
- arbitrum-node (port 8548)
- optimism-node (port 8550)
- solana-dev (port 8899)
- prometheus (port 9090)
- grafana (port 3000)

✅ **Access Points:**
- Ethereum RPC: http://localhost:8545
- Base RPC: http://localhost:8547
- Arbitrum RPC: http://localhost:8548  
- Optimism RPC: http://localhost:8550
- Solana RPC: http://localhost:8899
- MEV-Boost: http://localhost:18550
- Grafana: http://localhost:3000 (admin/blockchain123)
- Prometheus: http://localhost:9090

✅ **MEV Infrastructure Ready:**
- Cross-chain arbitrage monitoring
- Real-time transaction analysis
- MEV opportunity detection
- Trading bot endpoints

### 11. Troubleshooting

#### If Services Don't Start:
```bash
# Check logs
docker-compose logs [service-name]

# Check resources
free -h
docker stats

# Restart specific service
docker-compose restart [service-name]
```

#### If Out of Memory:
```bash
# Create swap file
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Reduce container memory limits in docker-compose.yml
```

#### If Ports Conflict:
```bash
# Check what's using ports
netstat -tlnp | grep -E ":(8545|8546|8547|8548|8549|8550|8551|8899|8900|18550|3000|9090)"

# Kill conflicting processes
sudo systemctl stop [conflicting-service]
```

### 12. Management Commands

```bash
# Status check
./quick-status.sh

# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs -f [service]

# Restart service
docker-compose restart [service]

# Resource monitoring
watch docker stats
```

### 13. Critical Notes for MEV Operations

1. **Erigon MUST start first** - All L2s depend on it
2. **Wait for sync** - Initial sync takes 1-3 days
3. **Monitor resources** - 32GB RAM is minimum
4. **MEV-Boost** connects to Flashbots and Ultrasound relays
5. **Staged startup** prevents resource exhaustion

### EXECUTE THIS NOW:

1. Copy these commands to your terminal
2. Execute step by step
3. Monitor each stage completion
4. Verify all endpoints respond
5. Your MEV infrastructure will be operational!

**Estimated Setup Time: 1-2 hours** (excluding initial blockchain sync)