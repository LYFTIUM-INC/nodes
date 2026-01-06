#!/bin/bash

# CPU Usage Monitoring Script for Avalanche Node
# Monitors and logs CPU usage every 30 seconds

LOG_FILE="/data/blockchain/nodes/avalanche/cpu_usage.log"
echo "CPU Usage Monitoring Started - $(date)" | tee -a "$LOG_FILE"
echo "Time,CPU%,Memory%" | tee -a "$LOG_FILE"

while true; do
    STATS=$(docker stats avalanche-node --no-stream --format "table {{.CPUPerc}}\t{{.MemPerc}}" | tail -1)
    CPU_PERCENT=$(echo "$STATS" | awk '{print $1}' | sed 's/%//')
    MEM_PERCENT=$(echo "$STATS" | awk '{print $2}' | sed 's/%//')
    
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP,$CPU_PERCENT%,$MEM_PERCENT%" | tee -a "$LOG_FILE"
    
    sleep 30
done