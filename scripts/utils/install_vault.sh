#!/bin/bash
# Critical Security Implementation: HashiCorp Vault Installation
# This script implements enterprise-grade secret management

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[SECURITY] Installing HashiCorp Vault for Secret Management${NC}"

# Create vault user and directories
sudo useradd --system --home /opt/vault --shell /bin/false vault 2>/dev/null || true
sudo mkdir -p /opt/vault/{bin,data,config,logs}
sudo mkdir -p /etc/vault.d

# Download and install Vault
VAULT_VERSION="1.15.4"
cd /tmp
wget -q "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
unzip -q "vault_${VAULT_VERSION}_linux_amd64.zip"
sudo mv vault /opt/vault/bin/
sudo chmod +x /opt/vault/bin/vault
sudo ln -sf /opt/vault/bin/vault /usr/local/bin/vault

# Set ownership
sudo chown -R vault:vault /opt/vault
sudo chown -R vault:vault /etc/vault.d

echo -e "${GREEN}[SECURITY] Vault installed successfully${NC}"

# Create Vault configuration
sudo tee /etc/vault.d/vault.hcl > /dev/null << 'EOF'
# HashiCorp Vault Configuration for Blockchain Infrastructure
# Implements enterprise security standards

# Storage backend (local file for development, use cloud storage for production)
storage "file" {
  path    = "/opt/vault/data"
}

# API listener
listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
  # In production, enable TLS:
  # tls_cert_file = "/path/to/cert.pem"
  # tls_key_file = "/path/to/key.pem"
}

# UI
ui = true

# Logging
log_level = "INFO"
log_file  = "/opt/vault/logs/vault.log"

# Telemetry
telemetry {
  disable_hostname = true
  prometheus_retention_time = "30s"
}

# API settings
api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"

# Disable mlock for development (enable in production)
disable_mlock = true

# Performance settings
default_lease_ttl = "168h"
max_lease_ttl = "720h"
EOF

# Set proper permissions
sudo chmod 640 /etc/vault.d/vault.hcl
sudo chown vault:vault /etc/vault.d/vault.hcl

echo -e "${GREEN}[SECURITY] Vault configuration created${NC}"