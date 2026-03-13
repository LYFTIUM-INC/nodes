#!/usr/bin/env bash
# JWT Setup Validation Script
# Verifies JWT secret file exists, has correct permissions, and valid hex format.
# Safe for cron, pre-start hooks, or manual verification.
# Exit 0 if OK, 1 with message if not.
# Run from any directory.

set -euo pipefail

JWT_PATH="${JWT_PATH:-/data/blockchain/storage/jwt-common/jwt-secret.hex}"
VALID_HEX_LEN=64  # 32 bytes = 64 hex chars

if [[ ! -f "${JWT_PATH}" ]]; then
    echo "JWT validation FAIL: file not found: ${JWT_PATH}"
    exit 1
fi

if [[ ! -s "${JWT_PATH}" ]]; then
    echo "JWT validation FAIL: file is empty: ${JWT_PATH}"
    exit 1
fi

# Check permissions (600 or 400)
PERMS=$(stat -c '%a' "${JWT_PATH}" 2>/dev/null || stat -f '%A' "${JWT_PATH}" 2>/dev/null)
if [[ "${PERMS}" != "600" && "${PERMS}" != "400" ]]; then
    echo "JWT validation FAIL: file permissions should be 600 or 400, got ${PERMS}: ${JWT_PATH}"
    exit 1
fi

# Read and validate hex content (strip whitespace/newlines)
CONTENT=$(tr -d '[:space:]' < "${JWT_PATH}")
LEN=${#CONTENT}

if [[ ${LEN} -ne ${VALID_HEX_LEN} ]]; then
    echo "JWT validation FAIL: hex length should be ${VALID_HEX_LEN} chars, got ${LEN}: ${JWT_PATH}"
    exit 1
fi

# Verify hex characters only
if [[ ! "${CONTENT}" =~ ^[0-9a-fA-F]+$ ]]; then
    echo "JWT validation FAIL: invalid hex characters in file: ${JWT_PATH}"
    exit 1
fi

echo "JWT validation OK: ${JWT_PATH} (perms ${PERMS}, ${LEN} hex chars)"
exit 0
