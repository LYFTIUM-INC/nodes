#!/usr/bin/env bash
# run-all-verification.sh — Run all verification scripts in sequence.
# Continues on failure and reports summary at end. Exit 0 only if all pass.
#
# Scripts run in order:
#   1. validate-jwt-setup.sh
#   2. check-protocol-dependencies.sh
#   3. verify-monitoring-stack.sh
#   4. verify-research-implementation.sh
#
# Usage: ./scripts/monitoring/run-all-verification.sh

set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "${REPO_ROOT}"

SCRIPT_DIR="${REPO_ROOT}/scripts/monitoring"
MAINT_DIR="${REPO_ROOT}/scripts/maintenance"

declare -a SCRIPTS=(
    "${SCRIPT_DIR}/validate-jwt-setup.sh"
    "${MAINT_DIR}/check-protocol-dependencies.sh"
    "${SCRIPT_DIR}/verify-monitoring-stack.sh"
    "${SCRIPT_DIR}/verify-research-implementation.sh"
)

PASSED=0
FAILED=0
declare -a FAILED_NAMES=()

for script in "${SCRIPTS[@]}"; do
    name="$(basename "${script}")"
    echo "--- Running ${name} ---"
    if "${script}"; then
        ((PASSED++))
        echo "[PASS] ${name}"
    else
        ((FAILED++))
        FAILED_NAMES+=("${name}")
        echo "[FAIL] ${name} (exit $?)"
    fi
    echo
done

echo "========================================"
echo "Summary: ${PASSED} passed, ${FAILED} failed"
echo "========================================"

if [[ ${FAILED} -gt 0 ]]; then
    echo "Failed scripts: ${FAILED_NAMES[*]}"
    exit 1
fi

exit 0
