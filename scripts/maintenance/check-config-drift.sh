#!/usr/bin/env bash
# check-config-drift.sh — Compare repo configs with deployed versions; detect drift
#
# Compares:
#   - configs/systemd/*.service  vs  /etc/systemd/system/
#   - configs/mev-boost/*.yaml  vs  /data/blockchain/nodes/configs/mev-boost/
#
# Run weekly or before upgrades to ensure deployed configs match Git source of truth.
# Exit: 0 if no drift, 1 if drift found (DRIFT: <file> printed to stderr)
#
# Usage: ./scripts/maintenance/check-config-drift.sh
#        REPO_ROOT=/path/to/nodes ./scripts/maintenance/check-config-drift.sh
#
# Deploy cron: configs/cron/config-drift.cron (Mondays 4 AM)

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPLOYED_SYSTEMD="/etc/systemd/system"
DEPLOYED_MEVBOOST="${DEPLOYED_MEVBOOST:-/data/blockchain/nodes/configs/mev-boost}"

DRIFT_FOUND=0

check_systemd() {
    local repo_systemd="${REPO_ROOT}/configs/systemd"
    [[ ! -d "$repo_systemd" ]] && return 0

    local f
    for f in "$repo_systemd"/*.service; do
        [[ -e "$f" ]] || continue
        local name
        name=$(basename "$f")
        local deployed="${DEPLOYED_SYSTEMD}/${name}"
        if [[ ! -f "$deployed" ]]; then
            echo "NOT_DEPLOYED: $name (first-time deploy: cp configs/systemd/$name /etc/systemd/system/)" >&2
            continue
        fi
        if diff "$f" "$deployed" &>/dev/null; then
            :  # no drift
        else
            echo "DRIFT: $name (repo vs $deployed)" >&2
            DRIFT_FOUND=1
        fi
    done
}

check_mev_boost() {
    local repo_mev="${REPO_ROOT}/configs/mev-boost"
    [[ ! -d "$repo_mev" ]] && return 0

    local f
    for f in "$repo_mev"/*.yaml; do
        [[ -e "$f" ]] || continue
        local name
        name=$(basename "$f")
        local deployed="${DEPLOYED_MEVBOOST}/${name}"
        [[ -f "$deployed" ]] || { echo "DRIFT: $name (deployed missing at $deployed)" >&2; DRIFT_FOUND=1; continue; }
        if diff "$f" "$deployed" &>/dev/null; then
            :  # no drift
        else
            echo "DRIFT: $name (repo vs $deployed)" >&2
            DRIFT_FOUND=1
        fi
    done
}

# --- Main ---
check_systemd
check_mev_boost

if [[ $DRIFT_FOUND -gt 0 ]]; then
    exit 1
fi
exit 0
