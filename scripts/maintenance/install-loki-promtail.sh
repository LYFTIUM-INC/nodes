#!/usr/bin/env bash
# Skeleton script: prints install instructions for Loki and Promtail.
# Does NOT perform download or install - manual steps only.
# See docs/guides/LOKI_PROMPTAIL_SETUP.md for full guide.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/data/blockchain/nodes}"
CONFIGS="${REPO_ROOT}/configs"
UNITS="${CONFIGS}/systemd"
MONITORING="${CONFIGS}/monitoring"

echo "=== Loki + Promtail Install Instructions (skeleton) ==="
echo ""
echo "1. Download Loki and Promtail:"
echo "   https://github.com/grafana/loki/releases"
echo "   - loki-linux-amd64.zip"
echo "   - promtail-linux-amd64.zip"
echo "   Unzip and copy to /usr/local/bin/"
echo ""
echo "2. Verify configs exist:"
echo "   ls ${MONITORING}/loki-config.yml ${MONITORING}/promtail-config.yml"
echo ""
echo "3. Install systemd units:"
echo "   sudo cp ${UNITS}/loki.service /etc/systemd/system/"
echo "   sudo cp ${UNITS}/promtail.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload"
echo ""
echo "4. Enable and start:"
echo "   sudo systemctl enable loki.service promtail.service"
echo "   sudo systemctl start loki.service promtail.service"
echo ""
echo "5. Verify:"
echo "   curl -s http://localhost:3100/ready"
echo "   curl -s http://localhost:9080/targets"
echo ""
echo "See docs/guides/LOKI_PROMPTAIL_SETUP.md for full guide."
