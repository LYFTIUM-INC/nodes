#!/bin/bash
# Automated Node Restart Script
# Safely restarts blockchain nodes with health verification

set -euo pipefail

# Configuration
LOG_FILE="/data/blockchain/nodes/logs/auto-restart.log"
MAX_RESTART_ATTEMPTS=3
RESTART_DELAY=30
HEALTH_CHECK_TIMEOUT=300
BACKUP_ENABLED=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Node configuration mapping
declare -A NODE_CONFIG=(
    ["ethereum-light"]="8545:eth_blockNumber"
    ["arbitrum-node"]="8560:eth_blockNumber" 
    ["base-mainnet"]="8547:eth_blockNumber"
    ["optimism-node"]="8550:eth_blockNumber"
    ["solana-dev"]="8899:getSlot"
)

# Function to check if container exists
container_exists() {
    local container=$1
    docker ps -a --format "{{.Names}}" | grep -q "^${container}$"
}

# Function to check if container is running
container_running() {
    local container=$1
    docker ps --format "{{.Names}}" | grep -q "^${container}$"
}

# Function to check RPC health
check_rpc_health() {
    local port=$1
    local method=$2
    local timeout=${3:-10}
    
    local response=$(curl -s --max-time "$timeout" -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
        "http://localhost:$port" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ] && echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to create data backup
create_backup() {
    local node_name=$1
    
    if [ "$BACKUP_ENABLED" = true ]; then
        log "INFO" "Creating backup for $node_name"
        
        local data_dir="/data/blockchain/storage/$node_name"
        local backup_dir="/data/blockchain/nodes/monitoring/backups"
        local backup_file="$backup_dir/${node_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        mkdir -p "$backup_dir"
        
        if [ -d "$data_dir" ]; then
            tar -czf "$backup_file" -C "$(dirname "$data_dir")" "$(basename "$data_dir")" 2>/dev/null || {
                log "WARN" "Failed to create backup for $node_name"
                return 1
            }
            log "INFO" "Backup created: $backup_file"
        else
            log "WARN" "Data directory not found for $node_name: $data_dir"
        fi
    fi
}

# Function to restart a single node
restart_node() {
    local container=$1
    local node_name=$(echo "$container" | sed 's/-.*$//')
    local attempt=1
    
    log "INFO" "Starting restart procedure for $container"
    
    # Check if container exists
    if ! container_exists "$container"; then
        log "ERROR" "Container $container does not exist"
        return 1
    fi
    
    # Get RPC configuration
    local rpc_config="${NODE_CONFIG[$container]:-}"
    if [ -z "$rpc_config" ]; then
        log "ERROR" "No RPC configuration found for $container"
        return 1
    fi
    
    local port=$(echo "$rpc_config" | cut -d: -f1)
    local method=$(echo "$rpc_config" | cut -d: -f2)
    
    while [ $attempt -le $MAX_RESTART_ATTEMPTS ]; do
        log "INFO" "Restart attempt $attempt for $container"
        
        # Create backup before restart
        create_backup "$node_name"
        
        # Stop container gracefully
        if container_running "$container"; then
            log "INFO" "Stopping container $container"
            docker stop "$container" --time=60 || {
                log "WARN" "Graceful stop failed, forcing stop"
                docker kill "$container" 2>/dev/null || true
            }
        fi
        
        # Wait for clean shutdown
        sleep "$RESTART_DELAY"
        
        # Start container
        log "INFO" "Starting container $container"
        docker start "$container" || {
            log "ERROR" "Failed to start container $container"
            ((attempt++))
            continue
        }
        
        # Wait for container to initialize
        log "INFO" "Waiting for container to initialize..."
        sleep 30
        
        # Health check with timeout
        local health_check_start=$(date +%s)
        local health_check_end=$((health_check_start + HEALTH_CHECK_TIMEOUT))
        local health_ok=false
        
        while [ $(date +%s) -lt $health_check_end ]; do
            if check_rpc_health "$port" "$method" 5; then
                health_ok=true
                break
            fi
            log "INFO" "Waiting for $container to become healthy..."
            sleep 10
        done
        
        if [ "$health_ok" = true ]; then
            log "INFO" "Container $container restarted successfully"
            
            # Additional health verification
            sleep 30
            if check_rpc_health "$port" "$method" 10; then
                log "INFO" "Final health check passed for $container"
                return 0
            else
                log "WARN" "Final health check failed for $container"
            fi
        else
            log "ERROR" "Health check failed for $container after restart attempt $attempt"
        fi
        
        ((attempt++))
        if [ $attempt -le $MAX_RESTART_ATTEMPTS ]; then
            log "INFO" "Waiting before next restart attempt..."
            sleep $((RESTART_DELAY * 2))
        fi
    done
    
    log "ERROR" "Failed to restart $container after $MAX_RESTART_ATTEMPTS attempts"
    return 1
}

# Function to restart all nodes
restart_all_nodes() {
    log "INFO" "Starting restart procedure for all nodes"
    
    local failed_nodes=()
    
    for container in "${!NODE_CONFIG[@]}"; do
        if container_exists "$container"; then
            if ! restart_node "$container"; then
                failed_nodes+=("$container")
            fi
        else
            log "WARN" "Container $container not found, skipping"
        fi
    done
    
    if [ ${#failed_nodes[@]} -eq 0 ]; then
        log "INFO" "All nodes restarted successfully"
        return 0
    else
        log "ERROR" "Failed to restart nodes: ${failed_nodes[*]}"
        return 1
    fi
}

# Function to perform emergency restart
emergency_restart() {
    local container=$1
    
    log "WARN" "Performing emergency restart for $container"
    
    # Force stop
    docker kill "$container" 2>/dev/null || true
    docker rm "$container" 2>/dev/null || true
    
    # Find and restart using docker-compose
    local compose_files=(
        "/data/blockchain/nodes/docker/services/docker-compose-optimized.yml"
        "/data/blockchain/nodes/environments/prod/docker-compose.yml"
        "/data/blockchain/nodes/deployment/docker-compose.yml"
    )
    
    for compose_file in "${compose_files[@]}"; do
        if [ -f "$compose_file" ]; then
            local service_name=$(docker-compose -f "$compose_file" config --services | grep -i "${container%-*}" | head -1)
            if [ -n "$service_name" ]; then
                log "INFO" "Restarting $service_name using docker-compose"
                docker-compose -f "$compose_file" up -d "$service_name" || {
                    log "ERROR" "Failed to restart $service_name with docker-compose"
                    continue
                }
                
                # Wait and check health
                sleep 60
                local rpc_config="${NODE_CONFIG[$container]:-}"
                if [ -n "$rpc_config" ]; then
                    local port=$(echo "$rpc_config" | cut -d: -f1)
                    local method=$(echo "$rpc_config" | cut -d: -f2)
                    
                    if check_rpc_health "$port" "$method" 10; then
                        log "INFO" "Emergency restart successful for $container"
                        return 0
                    fi
                fi
            fi
        fi
    done
    
    log "ERROR" "Emergency restart failed for $container"
    return 1
}

# Function to send notification
send_notification() {
    local status=$1
    local container=$2
    local message=$3
    
    # Send to monitoring system
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys
sys.path.append('/data/blockchain/nodes/monitoring')
from alert_system import AlertManager, Alert
from datetime import datetime

alert_manager = AlertManager()
alert = Alert(
    id='restart_${container}_$(date +%s)',
    severity='info' if '$status' == 'success' else 'warning',
    source='auto_restart',
    message='$message',
    timestamp=datetime.now()
)
alert_manager.process_alerts([alert])
" 2>/dev/null || log "WARN" "Could not send notification to monitoring system"
    fi
    
    # Log to alerts file
    echo "$(date '+%Y-%m-%d %H:%M:%S') [AUTO-RESTART] $message" >> "/data/blockchain/nodes/logs/alerts.log"
}

# Main execution
main() {
    local container="${1:-}"
    local action="${2:-restart}"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "INFO" "Auto-restart script started. Container: ${container:-all}, Action: $action"
    
    case "$action" in
        "restart")
            if [ -n "$container" ]; then
                if restart_node "$container"; then
                    send_notification "success" "$container" "Successfully restarted $container"
                else
                    send_notification "failure" "$container" "Failed to restart $container"
                    exit 1
                fi
            else
                if restart_all_nodes; then
                    send_notification "success" "all" "Successfully restarted all nodes"
                else
                    send_notification "failure" "all" "Failed to restart some nodes"
                    exit 1
                fi
            fi
            ;;
        "emergency")
            if [ -z "$container" ]; then
                log "ERROR" "Container name required for emergency restart"
                exit 1
            fi
            if emergency_restart "$container"; then
                send_notification "success" "$container" "Emergency restart successful for $container"
            else
                send_notification "failure" "$container" "Emergency restart failed for $container"
                exit 1
            fi
            ;;
        "health-check")
            if [ -z "$container" ]; then
                log "ERROR" "Container name required for health check"
                exit 1
            fi
            local rpc_config="${NODE_CONFIG[$container]:-}"
            if [ -n "$rpc_config" ]; then
                local port=$(echo "$rpc_config" | cut -d: -f1)
                local method=$(echo "$rpc_config" | cut -d: -f2)
                
                if check_rpc_health "$port" "$method" 10; then
                    log "INFO" "Health check passed for $container"
                    echo "healthy"
                else
                    log "WARN" "Health check failed for $container"
                    echo "unhealthy"
                    exit 1
                fi
            else
                log "ERROR" "No RPC configuration found for $container"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 [container] [restart|emergency|health-check]"
            echo "  container: Container name (optional for restart, required for others)"
            echo "  restart: Normal restart procedure (default)"
            echo "  emergency: Emergency restart with force kill"
            echo "  health-check: Check if container is healthy"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi