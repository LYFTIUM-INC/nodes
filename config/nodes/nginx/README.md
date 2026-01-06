# Lyftium Blockchain Infrastructure - Nginx Configuration

## 📁 Directory Structure

```
nginx/
├── production/           # Production-ready configurations
│   ├── main.conf        # Main nginx configuration
│   ├── rpc-proxy.conf   # RPC endpoint proxy configuration  
│   └── common.conf      # Shared configuration snippets
├── archive/             # Archived old configurations
└── README.md           # This documentation
```

## 🚀 Production Deployment

### 1. Main Configuration
- **File**: `production/main.conf`
- **Purpose**: Primary nginx configuration with optimized settings
- **Features**: Rate limiting, security headers, performance tuning

### 2. RPC Proxy
- **File**: `production/rpc-proxy.conf`
- **Purpose**: Blockchain RPC endpoint routing with SSL termination
- **Domains**: `*.rpc.lyftium.com` on port 8443
- **Security**: API key authentication, CORS policies

### 3. Common Configuration  
- **File**: `production/common.conf`
- **Purpose**: Reusable configuration snippets
- **Includes**: SSL settings, authentication, proxy settings

## 🔧 Usage

### Deploy to Nginx
```bash
# Symlink main configuration
sudo ln -sf /data/blockchain/nodes/config/nginx/production/main.conf /etc/nginx/nginx.conf

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

### SSL Certificate Setup
```bash
# Place SSL certificates in:
# /etc/ssl/certs/lyftium.com.crt
# /etc/ssl/private/lyftium.com.key
```

## 📊 Monitoring

### Log Files
- **Access**: `/var/log/nginx/blockchain-rpc-access.log`
- **Errors**: `/var/log/nginx/error.log`

### Metrics
- Request latency tracking
- Upstream response times
- API key usage statistics
- Rate limiting statistics

## 🔒 Security Features

- ✅ TLS 1.2/1.3 encryption
- ✅ API key authentication
- ✅ Rate limiting (100/min general, 1000/min authenticated)
- ✅ CORS policy enforcement
- ✅ Security headers
- ✅ DDoS protection

## 🎯 Performance Features  

- ⚡ Connection keepalive optimization
- ⚡ Upstream connection pooling
- ⚡ Gzip compression for JSON responses
- ⚡ Buffer size optimization for RPC calls
- ⚡ Load balancing with automatic failover

## 📋 Maintenance

### Archive Policy
Old configurations are moved to `archive/` with date stamps for historical reference.

### Configuration Updates
1. Edit files in `production/`
2. Test with `nginx -t`
3. Reload with `systemctl reload nginx`
4. Monitor logs for any issues

---
**Last Updated**: $(date)  
**Maintainer**: Lyftium Infrastructure Team