#!/bin/bash

# Start MEV Monitoring System
# Quick launcher for monitoring components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/data/blockchain/nodes/mev/logs"
MONITORING_DIR="/data/blockchain/nodes/mev/monitoring"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create required directories
echo -e "${YELLOW}Creating required directories...${NC}"
mkdir -p "$LOG_DIR"
mkdir -p "$MONITORING_DIR"

# Check Python dependencies
echo -e "${YELLOW}Checking Python dependencies...${NC}"
if ! python3 -c "import aiohttp, psutil, docker, rich" 2>/dev/null; then
    echo -e "${RED}Missing Python dependencies. Installing...${NC}"
    pip3 install aiohttp psutil docker-py rich aiofiles
fi

# Function to check if process is running
is_running() {
    pgrep -f "$1" > /dev/null
}

# Start MEV monitoring system
echo -e "${YELLOW}Starting MEV monitoring system...${NC}"
if is_running "mev_monitoring.py"; then
    echo -e "${GREEN}✓ MEV monitoring already running${NC}"
else
    echo "Starting MEV monitoring..."
    cd "$SCRIPT_DIR"
    nohup python3 mev_monitoring.py > "$LOG_DIR/mev-monitoring.out" 2>&1 &
    sleep 3
    if is_running "mev_monitoring.py"; then
        echo -e "${GREEN}✓ MEV monitoring started${NC}"
    else
        echo -e "${RED}✗ Failed to start MEV monitoring${NC}"
        exit 1
    fi
fi

# Start monitoring dashboard
echo -e "${YELLOW}Starting monitoring dashboard...${NC}"
if is_running "monitoring_dashboard.py"; then
    echo -e "${GREEN}✓ Monitoring dashboard already running${NC}"
else
    echo "Starting monitoring dashboard..."
    cd "$SCRIPT_DIR"
    nohup python3 monitoring_dashboard.py --mode web --port 8888 > "$LOG_DIR/dashboard.out" 2>&1 &
    sleep 3
    if is_running "monitoring_dashboard.py"; then
        echo -e "${GREEN}✓ Monitoring dashboard started${NC}"
    else
        echo -e "${RED}✗ Failed to start monitoring dashboard${NC}"
    fi
fi

# Set up cron job for health checks
echo -e "${YELLOW}Setting up health check cron job...${NC}"
CRON_CMD="$SCRIPT_DIR/health_check.sh >> $LOG_DIR/health-check-cron.log 2>&1"
CRON_JOB="* * * * * $CRON_CMD"

# Add to crontab if not already present
if ! crontab -l 2>/dev/null | grep -q "$CRON_CMD"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}✓ Health check cron job added${NC}"
else
    echo -e "${GREEN}✓ Health check cron job already exists${NC}"
fi

# Run initial health check
echo -e "${YELLOW}Running initial health check...${NC}"
"$SCRIPT_DIR/health_check.sh"

# Display status
echo ""
echo -e "${GREEN}=== MEV Monitoring System Started ===${NC}"
echo ""
echo "Components running:"
echo "  • MEV Monitoring System"
echo "  • Web Dashboard (http://localhost:8888)"
echo "  • Health checks (every minute)"
echo ""
echo "View logs:"
echo "  • tail -f $LOG_DIR/mev-monitoring.out"
echo "  • tail -f $LOG_DIR/dashboard.out"
echo "  • tail -f $LOG_DIR/health-check.log"
echo ""
echo "Stop monitoring:"
echo "  • pkill -f mev_monitoring.py"
echo "  • pkill -f monitoring_dashboard.py"
echo ""
echo -e "${GREEN}Monitoring system is now active!${NC}"