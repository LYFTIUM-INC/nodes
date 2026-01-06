#!/bin/bash
# /data/blockchain/nodes/monitoring/system-health-monitor.sh
# Monitoring système global - Lyftium Labs
# Surveillance continue pour prévenir les surcharges

set -euo pipefail

# Configuration
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEMORY=85
ALERT_THRESHOLD_LOAD=6.0  # Pour système 8 cores
LOG_DIR="/data/blockchain/nodes/logs"
ALERT_LOG="$LOG_DIR/system-alerts.log"
HEALTH_LOG="$LOG_DIR/system-health.log"
PID_FILE="/data/blockchain/nodes/logs/system-health-monitor.pid"

# Processus critiques à surveiller
CRITICAL_PROCESSES=("erigon" "docker" "postgres")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$HEALTH_LOG"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$ALERT_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$ALERT_LOG"
}

log_alert() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $1" >> "$ALERT_LOG"
}

# Setup function
setup_monitoring() {
    # Create log directory
    mkdir -p "$LOG_DIR"

    # Create PID file
    echo $$ > "$PID_FILE"

    # Trap signals for cleanup
    trap cleanup EXIT INT TERM

    log_info "Démarrage du monitoring système - Lyftium Labs"
    log_info "Seuils d'alerte: CPU: ${ALERT_THRESHOLD_CPU}%, Memory: ${ALERT_THRESHOLD_MEMORY}%, Load: ${ALERT_THRESHOLD_LOAD}"
}

# Cleanup function
cleanup() {
    log_info "Arrêt du monitoring système"
    rm -f "$PID_FILE"
    exit 0
}

# Get system metrics
get_cpu_usage() {
    # CPU usage over 5 seconds average
    grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4+$5)} END {print usage}'
}

get_memory_usage() {
    free | grep '^Mem:' | awk '{printf "%.1f", ($3/$2)*100}'
}

get_memory_details() {
    free -h | grep '^Mem:' | awk '{printf "Used: %s/%s (%.1f%%), Free: %s", $3, $2, ($3/$2)*100, $4}'
}

get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs
}

get_disk_usage() {
    df -h /data/blockchain | tail -1 | awk '{print $5}' | sed 's/%//'
}

# Check process health
check_process_health() {
    local process=$1
    local pid_count=$(pgrep -c "$process" 2>/dev/null || echo "0")

    if [[ $pid_count -eq 0 ]]; then
        log_error "Processus critique arrêté: $process"
        return 1
    else
        # Get resource usage for the process
        local cpu_mem=$(pgrep "$process" | head -1 | xargs -I {} ps -p {} -o pcpu,pmem,rss --no-headers 2>/dev/null || echo "0 0 0")
        local cpu=$(echo $cpu_mem | awk '{print $1}')
        local mem_pct=$(echo $cpu_mem | awk '{print $2}')
        local mem_mb=$(($(echo $cpu_mem | awk '{print $3}') / 1024))

        echo "$process: CPU=${cpu}%, Memory=${mem_mb}MB (${mem_pct}%)"

        # Alert on high usage
        if (( $(echo "$cpu > 50" | bc -l) )); then
            log_warn "Processus $process: Usage CPU élevé (${cpu}%)"
        fi

        if (( mem_mb > 8192 )); then
            log_warn "Processus $process: Usage mémoire élevé (${mem_mb}MB)"
        fi
    fi
}

# Check Docker containers
check_docker_health() {
    if ! command -v docker &> /dev/null; then
        return
    fi

    # Count running containers
    local running_containers=$(docker ps -q | wc -l)

    # Check for containers with high resource usage
    local high_cpu_containers=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}" | grep -v "NAME" | awk '$2 > 50 {print $1":"$2}' || true)

    if [[ -n "$high_cpu_containers" ]]; then
        log_warn "Conteneurs Docker avec CPU élevé: $high_cpu_containers"
    fi

    # Check for restarting containers
    local restarting_containers=$(docker ps --filter "status=restarting" --format "{{.Names}}" || true)

    if [[ -n "$restarting_containers" ]]; then
        log_error "Conteneurs en redémarrage constant: $restarting_containers"
    fi

    echo "Docker: $running_containers conteneurs actifs"
}

# Network monitoring
check_network_health() {
    # Check network connections
    local established_connections=$(netstat -tn 2>/dev/null | grep ESTABLISHED | wc -l)
    local time_wait_connections=$(netstat -tn 2>/dev/null | grep TIME_WAIT | wc -l)

    if [[ $established_connections -gt 1000 ]]; then
        log_warn "Nombre élevé de connexions établies: $established_connections"
    fi

    if [[ $time_wait_connections -gt 500 ]]; then
        log_warn "Nombre élevé de connexions TIME_WAIT: $time_wait_connections"
    fi

    echo "Network: $established_connections établies, $time_wait_connections TIME_WAIT"
}

# System performance check
check_system_performance() {
    local cpu_usage=$(get_cpu_usage)
    local memory_usage=$(get_memory_usage)
    local load_avg=$(get_load_average)
    local disk_usage=$(get_disk_usage)

    # CPU Check
    if (( $(echo "$cpu_usage > $ALERT_THRESHOLD_CPU" | bc -l) )); then
        log_alert "Usage CPU critique: ${cpu_usage}% (seuil: ${ALERT_THRESHOLD_CPU}%)"
    fi

    # Memory Check
    if (( $(echo "$memory_usage > $ALERT_THRESHOLD_MEMORY" | bc -l) )); then
        log_alert "Usage mémoire critique: ${memory_usage}% (seuil: ${ALERT_THRESHOLD_MEMORY}%)"
    fi

    # Load Average Check
    if (( $(echo "$load_avg > $ALERT_THRESHOLD_LOAD" | bc -l) )); then
        log_alert "Load average critique: ${load_avg} (seuil: ${ALERT_THRESHOLD_LOAD})"
    fi

    # Disk Space Check
    if [[ $disk_usage -gt 90 ]]; then
        log_alert "Espace disque critique: ${disk_usage}%"
    fi

    # Log current status
    local memory_details=$(get_memory_details)
    log_info "System: CPU=${cpu_usage}%, Memory=${memory_details}, Load=${load_avg}, Disk=${disk_usage}%"
}

# Automatic remediation
auto_remediate() {
    local cpu_usage=$(get_cpu_usage)
    local memory_usage=$(get_memory_usage)
    local load_avg=$(get_load_average)

    # If system is overloaded, try to reduce load
    if (( $(echo "$cpu_usage > 90" | bc -l) )) || (( $(echo "$memory_usage > 95" | bc -l) )) || (( $(echo "$load_avg > 10" | bc -l) )); then
        log_alert "Système en surcharge critique - Application de mesures d'urgence"

        # Reduce priority of non-critical processes
        local non_critical_pids=$(pgrep -f "spark|jupyter|notebook" || true)
        if [[ -n "$non_critical_pids" ]]; then
            echo "$non_critical_pids" | xargs -I {} renice +10 {} 2>/dev/null || true
            log_info "Priorité réduite pour processus non-critiques"
        fi

        # Stop non-essential Docker containers if any
        local optional_containers=$(docker ps --filter "label=priority=optional" -q || true)
        if [[ -n "$optional_containers" ]]; then
            docker stop $optional_containers || true
            log_info "Arrêt des conteneurs optionnels"
        fi

        # Clear system caches
        sync
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        log_info "Nettoyage des caches système"

        # Send alert
        log_alert "Mesures d'urgence appliquées - Surveillance renforcée activée"
    fi
}

# Main monitoring loop
monitoring_loop() {
    local iteration=0

    while true; do
        iteration=$((iteration + 1))

        log_info "=== Cycle de surveillance #$iteration ==="

        # System performance check
        check_system_performance

        # Process health check
        for process in "${CRITICAL_PROCESSES[@]}"; do
            check_process_health "$process"
        done

        # Docker health check
        check_docker_health

        # Network health check
        check_network_health

        # Auto-remediation if needed
        auto_remediate

        # Rotate logs every 100 iterations (≈ 1.6 hours at 1min intervals)
        if (( iteration % 100 == 0 )); then
            # Keep last 1000 lines of logs
            tail -n 1000 "$HEALTH_LOG" > "${HEALTH_LOG}.tmp" && mv "${HEALTH_LOG}.tmp" "$HEALTH_LOG"
            tail -n 1000 "$ALERT_LOG" > "${ALERT_LOG}.tmp" && mv "${ALERT_LOG}.tmp" "$ALERT_LOG"
            log_info "Rotation des logs effectuée"
        fi

        # Sleep for 60 seconds
        sleep 60
    done
}

# Status check function
check_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Monitoring actif (PID: $pid)"

            # Show recent status
            echo "--- État récent ---"
            tail -n 5 "$HEALTH_LOG" 2>/dev/null || echo "Aucun log disponible"

            # Show alerts
            local alert_count=$(wc -l < "$ALERT_LOG" 2>/dev/null || echo "0")
            echo "Alertes totales: $alert_count"

            if [[ $alert_count -gt 0 ]]; then
                echo "--- Dernières alertes ---"
                tail -n 3 "$ALERT_LOG" 2>/dev/null
            fi
        else
            echo "Monitoring arrêté (PID obsolète)"
            rm -f "$PID_FILE"
        fi
    else
        echo "Monitoring non actif"
    fi
}

# Stop monitoring
stop_monitoring() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid"
            log_info "Arrêt du monitoring demandé"
        else
            echo "Monitoring déjà arrêté"
            rm -f "$PID_FILE"
        fi
    else
        echo "Aucun monitoring actif"
    fi
}

# Usage function
usage() {
    echo "Usage: $0 {start|stop|status|check}"
    echo "  start  - Démarre le monitoring en arrière-plan"
    echo "  stop   - Arrête le monitoring"
    echo "  status - Affiche l'état du monitoring"
    echo "  check  - Effectue une vérification unique"
    exit 1
}

# Main function
main() {
    case "${1:-}" in
        start)
            if [[ -f "$PID_FILE" ]] && ps -p "$(cat "$PID_FILE")" > /dev/null 2>&1; then
                echo "Monitoring déjà actif"
                exit 1
            fi

            setup_monitoring
            echo "Démarrage du monitoring en arrière-plan..."
            nohup "$0" _monitor > /dev/null 2>&1 &
            sleep 2
            check_status
            ;;

        _monitor)
            setup_monitoring
            monitoring_loop
            ;;

        stop)
            stop_monitoring
            ;;

        status)
            check_status
            ;;

        check)
            mkdir -p "$LOG_DIR"
            log_info "Vérification unique du système"
            check_system_performance
            for process in "${CRITICAL_PROCESSES[@]}"; do
                check_process_health "$process"
            done
            check_docker_health
            check_network_health
            ;;

        *)
            usage
            ;;
    esac
}

# Execute main function
main "$@"
