#!/usr/bin/env bash
# sync-repo-configs-to-production.sh — Copy repo systemd configs to /etc/systemd/system/
#
# Copies critical systemd unit files from configs/systemd/ to /etc/systemd/system/.
# Does NOT blindly overwrite—requires explicit --execute flag or confirmation.
#
# Usage:
#   ./scripts/maintenance/sync-repo-configs-to-production.sh --dry-run   # Show what would be copied
#   ./scripts/maintenance/sync-repo-configs-to-production.sh --execute    # Copy without prompt
#   ./scripts/maintenance/sync-repo-configs-to-production.sh              # Prompt for confirmation
#
# Logs actions to /var/log/config-sync.log (requires sudo for write access).
#
# See: docs/operations/CONFIG_DRIFT_RESOLUTION.md

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
REPO_SYSTEMD="${REPO_ROOT}/configs/systemd"
DEPLOYED_SYSTEMD="/etc/systemd/system"
LOG_FILE="/var/log/config-sync.log"

# Critical units to sync (in order)
CRITICAL_UNITS=(
    mev-boost.service
    erigon.service
    reth.service
)

DRY_RUN=false
EXECUTE=false

log() {
    local msg="[$(date -Iseconds)] $*"
    echo "$msg"
    if [[ $(id -u) -eq 0 ]] && [[ -w /var/log ]] 2>/dev/null; then
        echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--execute]

  --dry-run    Only print what would be copied (no changes)
  --execute    Actually copy files (no confirmation prompt)

  Without --execute, prompts for confirmation before copying.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true ;;
        --execute)  EXECUTE=true ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

[[ -d "$REPO_SYSTEMD" ]] || { echo "ERROR: Repo systemd dir not found: $REPO_SYSTEMD" >&2; exit 1; }

# Collect units that exist in repo and would change /etc
# Use sudo diff for /etc files (often root-owned, mode 640)
TO_COPY=()
for unit in "${CRITICAL_UNITS[@]}"; do
    repo_file="${REPO_SYSTEMD}/${unit}"
    deployed_file="${DEPLOYED_SYSTEMD}/${unit}"
    [[ -f "$repo_file" ]] || continue
    if [[ ! -f "$deployed_file" ]]; then
        TO_COPY+=("$unit:NEW")
    elif ! (diff -q "$repo_file" "$deployed_file" &>/dev/null || sudo diff -q "$repo_file" "$deployed_file" &>/dev/null); then
        TO_COPY+=("$unit:CHANGED")
    fi
done

if [[ ${#TO_COPY[@]} -eq 0 ]]; then
    echo "No units to sync. All critical units match or are already deployed."
    exit 0
fi

echo "Units to sync (repo → /etc/systemd/system):"
for entry in "${TO_COPY[@]}"; do
    unit="${entry%%:*}"
    status="${entry##*:}"
    echo "  - $unit ($status)"
done

if $DRY_RUN; then
    echo ""
    echo "[DRY-RUN] Would run:"
    for entry in "${TO_COPY[@]}"; do
        unit="${entry%%:*}"
        echo "  sudo cp ${REPO_SYSTEMD}/${unit} ${DEPLOYED_SYSTEMD}/"
    done
    echo "  sudo chmod 644 ${DEPLOYED_SYSTEMD}/<units>"
    echo "  sudo systemctl daemon-reload"
    exit 0
fi

if ! $EXECUTE; then
    echo ""
    read -r -p "Proceed with copy? [y/N] " resp
    if [[ ! "$resp" =~ ^[yY] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Requires root for copy and daemon-reload
[[ $(id -u) -eq 0 ]] || { echo "ERROR: Must run as root (sudo) to copy to /etc" >&2; exit 1; }

COPIED=()
for unit in "${CRITICAL_UNITS[@]}"; do
    repo_file="${REPO_SYSTEMD}/${unit}"
    [[ -f "$repo_file" ]] || continue
    deployed_file="${DEPLOYED_SYSTEMD}/${unit}"
    if [[ ! -f "$deployed_file" ]] || ! diff -q "$repo_file" "$deployed_file" &>/dev/null; then
        cp "$repo_file" "$deployed_file"
        chmod 644 "$deployed_file"
        COPIED+=("$unit")
    fi
done

if [[ ${#COPIED[@]} -gt 0 ]]; then
    systemctl daemon-reload
    log "SYNC: Copied ${COPIED[*]} to ${DEPLOYED_SYSTEMD}"
    echo "Copied: ${COPIED[*]}"
    echo "Ran: systemctl daemon-reload"
    echo ""
    echo "Restart services as needed: sudo systemctl restart erigon.service mev-boost.service ..."
else
    echo "No files needed copying (already in sync)."
fi
