#!/usr/bin/env bash
# MEV Quick Wins Deployment Script
# Deploys MEV-Boost systemd service and Lighthouse backup cron.
# Run with: sudo ./scripts/maintenance/setup-mev-quick-wins.sh [options]
#
# See: docs/reports/LYFTIUM_MEV_NODE_BEST_PRACTICES_GAP_ANALYSIS_2026.md

set -euo pipefail

REPO_ROOT="/data/blockchain/nodes"
MEV_BOOST_SERVICE_SRC="${REPO_ROOT}/configs/systemd/mev-boost.service"
MEV_BOOST_SERVICE_DEST="/etc/systemd/system/mev-boost.service"
LIGHTHOUSE_CRON_SRC="${REPO_ROOT}/configs/cron/lighthouse-backup"
LIGHTHOUSE_CRON_DEST="/etc/cron.d/lighthouse-backup"
DR_TEST_SCRIPT="${REPO_ROOT}/scripts/maintenance/test-lighthouse-backup-restore.sh"
TIMING_GAMES_CONFIG="${REPO_ROOT}/configs/mev-boost/timing-games.yaml"
MEV_BOOST_CONFIG_DIR="/data/blockchain/mev-boost"

REQUIRED_RELAY_COUNT=10
RESTART_MEV=false
INSTALL_CRON=false
RUN_DR_TEST=false
METRICS_CHECK=false

# Colors for step output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

step_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
step_fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
step_info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

show_help() {
    echo "MEV Quick Wins Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --restart        Restart mev-boost after deploying service (default: no restart)"
    echo "  --cron           Install Lighthouse backup cron (weekly Sun 2am)"
    echo "  --dr-test        Run Lighthouse backup DR test script after setup"
    echo "  --metrics-check  Verify MEV-Boost metrics endpoint responds (18551 or 18651)"
    echo "  -h, --help       Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                    # Deploy MEV-Boost service only"
    echo "  $0 --cron            # Deploy + install Lighthouse backup cron"
    echo "  $0 --restart --cron  # Deploy, install cron, restart mev-boost"
    echo "  $0 --metrics-check   # Deploy + verify metrics endpoint"
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --restart) RESTART_MEV=true ;;
        --cron) INSTALL_CRON=true ;;
        --dr-test) RUN_DR_TEST=true ;;
        --metrics-check) METRICS_CHECK=true ;;
        -h|--help) show_help ;;
    esac
done

echo "=== MEV Quick Wins Deployment ==="

# --- Pre-deploy: Validate 10 relays in service file ---
step_info "Validating mev-boost.service has ${REQUIRED_RELAY_COUNT} relays..."
if [[ ! -f "$MEV_BOOST_SERVICE_SRC" ]]; then
    step_fail "MEV-Boost service not found at $MEV_BOOST_SERVICE_SRC"
fi
relay_count=$(grep -oE 'https://0x[a-fA-F0-9]{96}@[^,[:space:]]+' "$MEV_BOOST_SERVICE_SRC" 2>/dev/null | wc -l)
if [[ "${relay_count}" -ne "${REQUIRED_RELAY_COUNT}" ]]; then
    step_fail "Service has ${relay_count} relays, required ${REQUIRED_RELAY_COUNT}. Aborting deploy."
fi
step_ok "Service file has ${REQUIRED_RELAY_COUNT} relays"

# --- Step 1: Copy MEV-Boost systemd service ---
step_info "Copying mev-boost.service to /etc/systemd/system/..."
if ! cp -f "$MEV_BOOST_SERVICE_SRC" "$MEV_BOOST_SERVICE_DEST"; then
    step_fail "Failed to copy mev-boost.service"
fi
if [[ ! -f "$MEV_BOOST_SERVICE_DEST" ]]; then
    step_fail "Service file not found at destination after copy"
fi
step_ok "Copied mev-boost.service"

# --- Step 2: Daemon reload ---
step_info "Reloading systemd daemon..."
if ! systemctl daemon-reload; then
    step_fail "systemctl daemon-reload failed"
fi
step_ok "Daemon reloaded"

# --- Step 3: Deploy timing-games config if it exists ---
if [[ -f "$TIMING_GAMES_CONFIG" ]]; then
    step_info "Deploying timing-games.yaml..."
    mkdir -p "$MEV_BOOST_CONFIG_DIR"
    if ! cp -f "$TIMING_GAMES_CONFIG" "${MEV_BOOST_CONFIG_DIR}/timing-games.yaml"; then
        step_fail "Failed to copy timing-games.yaml"
    fi
    step_ok "Deployed timing-games.yaml to ${MEV_BOOST_CONFIG_DIR}/"
    step_info "To enable: add -config path -watch-config to mev-boost ExecStart (requires mev-boost v1.12+)."
fi

# --- Step 4: Optionally restart mev-boost ---
if [[ "$RESTART_MEV" == "true" ]]; then
    step_info "Restarting mev-boost..."
    if systemctl restart mev-boost.service 2>/dev/null || systemctl start mev-boost.service 2>/dev/null; then
        if systemctl is-active --quiet mev-boost.service; then
            step_ok "MEV-Boost restarted and active"
        else
            step_fail "MEV-Boost restart completed but service is not active"
        fi
    else
        step_fail "Failed to restart/start mev-boost.service"
    fi
else
    step_info "Skipping restart (use --restart to restart). Run: sudo systemctl restart mev-boost.service"
fi

# --- Step 5: Optional metrics check ---
if [[ "$METRICS_CHECK" == "true" ]]; then
    echo ""
    step_info "MEV-Boost Metrics Check"
    for port in 18551 18651; do
        if curl -s -m 5 "http://127.0.0.1:${port}/metrics" 2>/dev/null | head -5 | grep -qE '^(#|mev_boost|go_|process_)'; then
            step_ok "Port ${port}/metrics responds with Prometheus format"
        else
            step_info "Port ${port}/metrics not responding (mev-boost v1.9 has no --metrics; upgrade to v1.12+ for metrics)"
        fi
    done
fi

# --- Step 6: Lighthouse backup cron ---
echo ""
step_info "Lighthouse Backup Cron"
echo "  Weekly backup recommended: Sundays at 2:00 AM"
echo "  Script: ${REPO_ROOT}/scripts/backup-lighthouse-db.sh"
echo "  Cron entry: 0 2 * * 0 lyftium ${REPO_ROOT}/scripts/backup-lighthouse-db.sh"
echo ""

if [[ "$INSTALL_CRON" == "true" ]] && [[ -f "$LIGHTHOUSE_CRON_SRC" ]]; then
    step_info "Installing Lighthouse backup cron..."
    if ! cp -f "$LIGHTHOUSE_CRON_SRC" "$LIGHTHOUSE_CRON_DEST"; then
        step_fail "Failed to copy cron file"
    fi
    step_ok "Lighthouse backup cron installed at ${LIGHTHOUSE_CRON_DEST}"
fi

# --- Step 7: Optional DR test ---
if [[ "$RUN_DR_TEST" == "true" ]]; then
    echo ""
    step_info "Lighthouse Backup DR Test"
    if [[ -f "$DR_TEST_SCRIPT" ]] && [[ -x "$DR_TEST_SCRIPT" ]]; then
        if "$DR_TEST_SCRIPT"; then
            step_ok "DR test completed successfully"
        else
            step_fail "DR test failed - run backup first: ./scripts/backup-lighthouse-db.sh"
        fi
    else
        step_fail "DR test script not found or not executable: $DR_TEST_SCRIPT"
    fi
fi

echo ""
step_ok "=== Deployment Complete ==="
echo "Verify: systemctl status mev-boost.service"
echo "Health check: ./scripts/monitoring/mev-health-check.sh"
