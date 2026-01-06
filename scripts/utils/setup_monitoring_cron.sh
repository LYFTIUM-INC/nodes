#!/bin/bash

# Setup automated monitoring cron jobs for MEV infrastructure

echo "Setting up MEV monitoring cron jobs..."

# Create monitoring directory
mkdir -p /data/blockchain/nodes/mev/monitoring
mkdir -p /data/blockchain/nodes/mev/logs

# Create systemd service for MEV monitoring
cat > /etc/systemd/system/mev-monitoring.service << EOF
[Unit]
Description=MEV Infrastructure Monitoring System
After=network.target docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/data/blockchain/nodes/mev/private_mempool
Environment="PYTHONPATH=/data/blockchain/nodes/mev/private_mempool"
ExecStart=/usr/bin/python3 /data/blockchain/nodes/mev/private_mempool/mev_monitoring.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for monitoring dashboard
cat > /etc/systemd/system/mev-dashboard.service << EOF
[Unit]
Description=MEV Monitoring Dashboard
After=network.target mev-monitoring.service

[Service]
Type=simple
User=root
WorkingDirectory=/data/blockchain/nodes/mev/private_mempool
Environment="PYTHONPATH=/data/blockchain/nodes/mev/private_mempool"
ExecStart=/usr/bin/python3 /data/blockchain/nodes/mev/private_mempool/monitoring_dashboard.py --mode web --port 8888
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create health check cron job
CRON_CMD="/data/blockchain/nodes/mev/private_mempool/health_check.sh >> /data/blockchain/nodes/mev/logs/health-check-cron.log 2>&1"
CRON_JOB="* * * * * $CRON_CMD"

# Add to crontab if not already present
(crontab -l 2>/dev/null | grep -v "$CRON_CMD"; echo "$CRON_JOB") | crontab -

# Create log rotation config
cat > /etc/logrotate.d/mev-monitoring << EOF
/data/blockchain/nodes/mev/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable mev-monitoring.service
systemctl enable mev-dashboard.service

echo "Starting MEV monitoring services..."
systemctl start mev-monitoring.service
systemctl start mev-dashboard.service

# Show status
echo ""
echo "=== MEV Monitoring Setup Complete ==="
echo ""
echo "Services created:"
echo "- mev-monitoring.service: Main monitoring system"
echo "- mev-dashboard.service: Web dashboard on port 8888"
echo ""
echo "Cron job added:"
echo "- Health checks run every minute"
echo ""
echo "Check service status:"
echo "  systemctl status mev-monitoring"
echo "  systemctl status mev-dashboard"
echo ""
echo "View logs:"
echo "  journalctl -u mev-monitoring -f"
echo "  journalctl -u mev-dashboard -f"
echo "  tail -f /data/blockchain/nodes/mev/logs/health-check.log"
echo ""
echo "Access web dashboard:"
echo "  http://localhost:8888"
echo ""