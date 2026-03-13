#!/usr/bin/env bash
# check-protocol-dependencies.sh — Verify MEV-Boost and client versions meet Fusaka/BPO minimums
#
# Requirements (Fusaka/BPO compatibility per BUILDERNET_PBS_EVOLUTION_2026.md):
#   - MEV-Boost >= 1.10.1
#   - Erigon >= 3.3.0 (if installed)
#   - Reth >= 1.9.3 (only when Reth service is active/enabled in production)
#   - Lighthouse >= 8.0.1 (if installed)
#
# Exit: 0 if compliant, 1 with error message if not
# Cron: Weekly — see configs/cron/protocol-dependencies
#
# Usage: ./scripts/maintenance/check-protocol-dependencies.sh
#        REPO_ROOT=/path/to/nodes ./scripts/maintenance/check-protocol-dependencies.sh

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "${REPO_ROOT}"

# Minimum versions (Fusaka / BPO requirement)
MIN_MEV_BOOST="1.10.1"
MIN_ERIGON="3.3.0"
MIN_RETH="1.9.3"
MIN_LIGHTHOUSE="8.0.1"

ERR_MSGS=()
FAILED=0
CHECKED=()
N_A=()

# Returns 0 if Reth service is active or enabled (in production use)
reth_in_use() {
  [[ $(systemctl is-active reth 2>/dev/null || true) == "active" ]] && return 0
  [[ $(systemctl is-enabled reth 2>/dev/null || true) == "enabled" ]] && return 0
  return 1
}

# Compare semantic versions: returns 0 if v1 >= v2, 1 otherwise
# Handles: 1.10.1, 1.12, v1.12.0
version_gte() {
  local v1="${1//v/}" v2="${2//v/}"
  local a b
  IFS=. read -ra a <<< "$v1"
  IFS=. read -ra b <<< "$v2"
  local n=$(( ${#a[@]} > ${#b[@]} ? ${#a[@]} : ${#b[@]} ))
  for (( i=0; i < n; i++ )); do
    local x="${a[i]:-0}" y="${b[i]:-0}"
    x="${x%%[-+]*}"
    y="${y%%[-+]*}"
    [[ "${x:-0}" =~ ^[0-9]+$ ]] || x=0
    [[ "${y:-0}" =~ ^[0-9]+$ ]] || y=0
    (( 10#$x > 10#$y )) && return 0
    (( 10#$x < 10#$y )) && return 1
  done
  return 0
}

# Extract version from common output formats: "v1.12", "1.12.0", "mev-boost 1.12.0", etc.
extract_version() {
  local out="$1"
  local ver
  ver=$(echo "$out" | grep -oE '[v]?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  echo "${ver#v}"
}

check_mev_boost() {
  local bin
  for path in /data/blockchain/mev-boost/mev-boost /usr/local/bin/mev-boost mev-boost; do
    if [[ -x "$path" ]] || ([[ "$path" == "mev-boost" ]] && command -v mev-boost &>/dev/null); then
      bin="$path"
      break
    fi
  done
  [[ -z "${bin:-}" ]] && { ERR_MSGS+=("MEV-Boost: binary not found"); FAILED=$((FAILED+1)); return; }

  local out
  out=$("$bin" --version 2>/dev/null || "$bin" -version 2>/dev/null || true)
  [[ -z "$out" ]] && { ERR_MSGS+=("MEV-Boost: could not get version"); FAILED=$((FAILED+1)); return; }

  local ver
  ver=$(extract_version "$out")
  if [[ -z "$ver" ]]; then
    ERR_MSGS+=("MEV-Boost: could not parse version from: $out")
    FAILED=$((FAILED+1))
    return
  fi

  if version_gte "$ver" "$MIN_MEV_BOOST"; then
    CHECKED+=("MEV-Boost: $ver OK")
  else
    ERR_MSGS+=("MEV-Boost: $ver < $MIN_MEV_BOOST (Fusaka/BPO requirement)")
    FAILED=$((FAILED+1))
  fi
}

check_erigon() {
  local bin=/usr/local/bin/erigon
  [[ ! -x "$bin" ]] && command -v erigon &>/dev/null && bin=erigon
  [[ ! -x "$bin" ]] && ! command -v erigon &>/dev/null && return 0  # Skip if not installed

  local out
  out=$("$bin" --version 2>/dev/null || true)
  [[ -z "$out" ]] && return 0  # Skip if cannot get version

  local ver
  ver=$(extract_version "$out")
  [[ -z "$ver" ]] && return 0

  if version_gte "$ver" "$MIN_ERIGON"; then
    CHECKED+=("Erigon: $ver OK")
  else
    ERR_MSGS+=("Erigon: $ver < $MIN_ERIGON (Fusaka requirement)")
    FAILED=$((FAILED+1))
  fi
}

check_reth() {
  # Only check Reth when service is active or enabled (in production use).
  # When Erigon is primary, Reth is N/A if not running.
  if ! reth_in_use; then
    N_A+=("Reth: N/A (service not active/enabled)")
    return 0
  fi

  local bin=/usr/local/bin/reth
  [[ ! -x "$bin" ]] && command -v reth &>/dev/null && bin=reth
  [[ ! -x "$bin" ]] && ! command -v reth &>/dev/null && { N_A+=("Reth: N/A (binary not found)"); return 0; }

  local out
  out=$("$bin" --version 2>/dev/null || "$bin" version 2>/dev/null || true)
  [[ -z "$out" ]] && return 0

  local ver
  ver=$(extract_version "$out")
  [[ -z "$ver" ]] && return 0

  if version_gte "$ver" "$MIN_RETH"; then
    CHECKED+=("Reth: $ver OK")
  else
    ERR_MSGS+=("Reth: $ver < $MIN_RETH (Fusaka requirement)")
    FAILED=$((FAILED+1))
  fi
}

check_lighthouse() {
  local bin=/usr/local/bin/lighthouse
  [[ ! -x "$bin" ]] && command -v lighthouse &>/dev/null && bin=lighthouse
  [[ ! -x "$bin" ]] && ! command -v lighthouse &>/dev/null && return 0

  local out
  out=$("$bin" --version 2>/dev/null || true)
  [[ -z "$out" ]] && return 0

  local ver
  ver=$(extract_version "$out")
  [[ -z "$ver" ]] && return 0

  if version_gte "$ver" "$MIN_LIGHTHOUSE"; then
    CHECKED+=("Lighthouse: $ver OK")
  else
    ERR_MSGS+=("Lighthouse: $ver < $MIN_LIGHTHOUSE (Fusaka requirement)")
    FAILED=$((FAILED+1))
  fi
}

# --- Main ---
check_mev_boost
check_erigon
check_reth
check_lighthouse

if [[ $FAILED -gt 0 ]]; then
  echo "Protocol dependency check FAILED:" >&2
  for msg in "${ERR_MSGS[@]}"; do
    echo "  - $msg" >&2
  done
  echo "" >&2
  echo "Checked: ${CHECKED[*]:-none}" >&2
  [[ ${#N_A[@]} -gt 0 ]] && echo "N/A: ${N_A[*]}" >&2
  echo "" >&2
  echo "See docs/operations/PROTOCOL_CALENDAR.md and docs/research/BUILDERNET_PBS_EVOLUTION_2026.md" >&2
  exit 1
fi

# Report which clients were checked and result
echo "Protocol dependency check: COMPLIANT"
echo "Checked: ${CHECKED[*]}"
[[ ${#N_A[@]} -gt 0 ]] && echo "N/A: ${N_A[*]}"
exit 0
