#!/bin/bash

# Disk Space Monitoring Script
# Monitors disk usage and triggers cleanup when needed

THRESHOLD_WARNING=85
THRESHOLD_CRITICAL=90
LOG_FILE="/data/blockchain/nodes/logs/disk-monitor.log"
CLEANUP_SCRIPT="/data/blockchain/nodes/scripts/emergency-disk-cleanup.sh"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get current disk usage
USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
AVAILABLE=$(df -h / | tail -1 | awk '{print $4}')

log "Disk usage check: ${USAGE}% used, ${AVAILABLE} available"

# Check thresholds
if [ "$USAGE" -ge "$THRESHOLD_CRITICAL" ]; then
    log "CRITICAL: Disk usage at ${USAGE}%. Running emergency cleanup..."
    if [ -x "$CLEANUP_SCRIPT" ]; then
        "$CLEANUP_SCRIPT" >> "$LOG_FILE" 2>&1
        NEW_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
        log "Emergency cleanup completed. New usage: ${NEW_USAGE}%"
    else
        log "ERROR: Emergency cleanup script not found or not executable"
    fi
elif [ "$USAGE" -ge "$THRESHOLD_WARNING" ]; then
    log "WARNING: Disk usage at ${USAGE}%. Consider running cleanup soon."
    
    # Light cleanup
    log "Running light cleanup..."
    pip cache purge 2>/dev/null || true
    docker system prune -f 2>/dev/null || true
    find /tmp -type f -atime +1 -delete 2>/dev/null || true
    
    NEW_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    log "Light cleanup completed. New usage: ${NEW_USAGE}%"
fi

# Rotate log file if it gets too large
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then  # 10MB
    mv "$LOG_FILE" "${LOG_FILE}.old"
    log "Log file rotated"
fi