#!/usr/bin/env bash
# install-systemd-exporter.sh — Install prometheus-systemd-exporter binary and print unit setup instructions
#
# Downloads or builds systemd_exporter via go install, places binary in /usr/local/bin/,
# echoes instructions to copy and enable the systemd unit. Non-destructive: does not
# enable or start the service without user confirmation.
#
# Optional: enables ServiceRestartLoop alert in configs/monitoring/rules/mev-alerts.yml
#
# Usage: ./scripts/maintenance/install-systemd-exporter.sh
#
# Prerequisites: go (for go install) or curl (for binary download)

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BINARY_DEST="/usr/local/bin/systemd_exporter"
UNIT_SRC="${REPO_ROOT}/configs/systemd/systemd-exporter.service"
UNIT_DEST="/etc/systemd/system/systemd-exporter.service"

# --- Helper ---
log() { echo "[install-systemd-exporter] $*"; }

# --- Check if binary already present ---
if [[ -x "$BINARY_DEST" ]]; then
    log "Binary already present at $BINARY_DEST"
else
    # --- Install via go install ---
    if command -v go &>/dev/null; then
        log "Installing via: go install github.com/prometheus-community/systemd_exporter@latest"
        go install github.com/prometheus-community/systemd_exporter@latest
        BINARY_SRC="${GOPATH:-$HOME/go}/bin/systemd_exporter"
        if [[ ! -x "$BINARY_SRC" ]]; then
            BINARY_SRC="$HOME/go/bin/systemd_exporter"
        fi
        if [[ -x "$BINARY_SRC" ]]; then
            log "Copying $BINARY_SRC -> $BINARY_DEST (requires sudo)"
            sudo cp -f "$BINARY_SRC" "$BINARY_DEST"
            sudo chmod 755 "$BINARY_DEST"
        else
            echo "ERROR: go install succeeded but binary not found at $BINARY_SRC" >&2
            exit 1
        fi
    else
        # --- Fallback: download release binary ---
        log "go not found; attempting to download release binary"
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64) ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            *) echo "ERROR: Unsupported architecture: $ARCH" >&2; exit 1 ;;
        esac
        API_JSON=$(curl -sL "https://api.github.com/repos/prometheus-community/systemd_exporter/releases/latest")
        VER=$(echo "$API_JSON" | grep -oE '"tag_name":\s*"v[0-9.]+"' | head -1 | sed 's/.*"v\([0-9.]*\)".*/\1/')
        TARBALL="systemd_exporter-${VER}.linux-${ARCH}.tar.gz"
        RELEASE_URL="https://github.com/prometheus-community/systemd_exporter/releases/download/v${VER}/${TARBALL}"
        TMPDIR=$(mktemp -d)
        trap "rm -rf $TMPDIR" EXIT
        log "Downloading $RELEASE_URL"
        curl -sLf "$RELEASE_URL" -o "$TMPDIR/systemd_exporter.tar.gz"
        tar -xzf "$TMPDIR/systemd_exporter.tar.gz" -C "$TMPDIR"
        BINARY_SRC=$(find "$TMPDIR" -name "systemd_exporter" -type f | head -1)
        if [[ -x "${BINARY_SRC:-}" ]]; then
            log "Copying $BINARY_SRC -> $BINARY_DEST (requires sudo)"
            sudo cp -f "$BINARY_SRC" "$BINARY_DEST"
            sudo chmod 755 "$BINARY_DEST"
        else
            echo "ERROR: Downloaded archive did not contain systemd_exporter binary" >&2
            exit 1
        fi
    fi
fi

# --- Print instructions ---
echo ""
echo "=== systemd_exporter installed at $BINARY_DEST ==="
echo ""
echo "To enable the ServiceRestartLoop alert, copy and enable the systemd unit:"
echo ""
echo "  sudo cp ${UNIT_SRC} ${UNIT_DEST}"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable systemd-exporter   # enable at boot"
echo "  sudo systemctl start systemd-exporter   # start now"
echo ""
echo "Then reload Prometheus to pick up metrics:"
echo "  curl -X POST http://127.0.0.1:9090/-/reload"
echo ""
echo "Metrics will be available at http://127.0.0.1:9558/metrics"
echo ""
