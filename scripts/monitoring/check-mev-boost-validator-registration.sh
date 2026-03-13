#!/usr/bin/env bash
# Check MEV-Boost Validator Registration
# Verifies the validator is registered with Flashbots relay via data API.
# Exit 0 if OK, 1 if not found or error.
#
# Usage: ./check-mev-boost-validator-registration.sh [VALIDATOR_PUBKEY]
#   VALIDATOR_PUBKEY: BLS pubkey (0x + 96 hex chars). Optional if VALIDATOR_PUBKEY env set.
#
# Example: VALIDATOR_PUBKEY=0x1234... ./check-mev-boost-validator-registration.sh
# Or: ./check-mev-boost-validator-registration.sh 0x1234...
#
# Weekly cron: 0 9 * * 1 lyftium /data/blockchain/nodes/scripts/monitoring/check-mev-boost-validator-registration.sh

set -euo pipefail

FLASHBOTS_RELAY_URL="${FLASHBOTS_RELAY_URL:-https://boost-relay.flashbots.net}"
VALIDATOR_PUBKEY="${VALIDATOR_PUBKEY:-}"
TIMEOUT=15

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    echo "Usage: $0 [VALIDATOR_PUBKEY]"
    echo "  VALIDATOR_PUBKEY: BLS pubkey (0x + 96 hex chars)"
    echo "  Or set VALIDATOR_PUBKEY env var"
    echo ""
    echo "Checks Flashbots relay to verify validator registration."
    echo "Exit 0: registered, Exit 1: not found or error"
}

# Resolve pubkey from arg or env
if [[ -n "${1:-}" ]]; then
    VALIDATOR_PUBKEY="$1"
fi

if [[ -z "${VALIDATOR_PUBKEY}" ]]; then
    log_error "VALIDATOR_PUBKEY required. Set env or pass as argument."
    usage
    exit 1
fi

# Basic format check: 0x + 96 hex chars
if ! [[ "${VALIDATOR_PUBKEY}" =~ ^0x[a-fA-F0-9]{96}$ ]]; then
    log_error "Invalid pubkey format. Expected 0x + 96 hex chars."
    exit 1
fi

# Flashbots relay: GET /relay/v1/data/validator_registration?pubkey=0x...
# Returns 200 with registration JSON if found, 404 if not.
REG_URL="${FLASHBOTS_RELAY_URL}/relay/v1/data/validator_registration?pubkey=${VALIDATOR_PUBKEY}"

log_info "Checking validator registration at Flashbots relay..."
RESP=$(curl -sf --max-time "${TIMEOUT}" -w "\n%{http_code}" "${REG_URL}" 2>/dev/null) || true
HTTP_BODY=$(echo "$RESP" | head -n -1)
HTTP_CODE=$(echo "$RESP" | tail -1)

if [[ -z "${HTTP_CODE}" ]]; then
    log_error "No response from relay (timeout or connection error)"
    exit 1
fi

case "${HTTP_CODE}" in
    200)
        if echo "${HTTP_BODY}" | jq -e . >/dev/null 2>&1; then
            log_info "Validator is registered with Flashbots relay"
            echo "${HTTP_BODY}" | jq .
            exit 0
        else
            log_warn "Unexpected response body (not JSON)"
            exit 1
        fi
        ;;
    404)
        log_error "Validator not found in Flashbots relay registration"
        exit 1
        ;;
    400)
        log_error "Bad request (invalid pubkey format?)"
        exit 1
        ;;
    *)
        log_error "Relay returned HTTP ${HTTP_CODE}"
        echo "${HTTP_BODY}" | head -5
        exit 1
        ;;
esac
