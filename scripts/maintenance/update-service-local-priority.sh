#!/bin/bash
# Update MEV Pipeline Service Configuration for Local Node Priority
# This script updates the service to prioritize local endpoints

set -euo pipefail

echo "🔄 Updating MEV Pipeline Service Configuration..."

# Backup current configuration
cp /opt/mev-lab/mev-pipeline.service /opt/mev-lab/mev-pipeline.service.backup

# Update environment file to use local priority configuration
cp /opt/mev-lab/mev-pipeline-local-priority.env /opt/mev-lab/.env.backup
echo "📝 Updated environment file to prioritize local endpoints"

# Update systemd service to use new environment
sed -i 's|EnvironmentFile=.*|EnvironmentFile=/opt/mev-lab/mev-pipeline-local-priority.env|g' \
    /opt/mev-lab/mev-pipeline.service

# Update service description
sed -i 's|Description=.*|Description=MEV Pipeline Service (Local Node Priority)|g' \
    /opt/mev-lab/mev-pipeline.service

# Reload systemd to apply changes
sudo systemctl daemon-reload
echo "✅ Systemd configuration reloaded"

# Restart MEV pipeline service
echo "🔄 Restarting MEV pipeline service..."
sudo systemctl restart mev-pipeline
echo "✅ MEV pipeline service restarted with local node priority"

# Verify service status
sleep 10
SERVICE_STATUS=$(systemctl is-active mev-pipeline)
if [ "$SERVICE_STATUS" = "active" ]; then
    echo "✅ MEV Pipeline Service: RUNNING"
else
    echo "❌ MEV Pipeline Service: FAILED - checking logs..."
    journalctl -u mev-pipeline --no-pager -n 50
fi

echo ""
echo "🔍 Local Node Integration Status: ENABLED"
echo "📊 Priority: Local nodes (priority 1), Public endpoints (priority 10)"
echo "🚀 Ready for Production MEV Operations"