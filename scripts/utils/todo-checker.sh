#!/bin/bash
# TODO/FIXME checker for pre-commit hook
# Scans for TODO, FIXME, XXX, HACK, BUG markers

set -euo pipefail

echo "Checking for TODO/FIXME markers..."

# Find TODO/FIXME/XXX/HACK/BUG comments
patterns=(
    "TODO"
    "FIXME"
    "XXX"
    "HACK"
    "BUG"
    "TEMP"
    "TEMPORARY"
    "WORKAROUND"
)

found_any=0
for pattern in "${patterns[@]}"; do
    # Search in source files (exclude vendor, node_modules, .git)
    matches=$(grep -r "$pattern" \
        --include="*.py" \
        --include="*.go" \
        --include="*.sh" \
        --include="*.ts" \
        --include="*.js" \
        --include="*.yaml" \
        --include="*.yml" \
        --exclude-dir=.git \
        --exclude-dir=node_modules \
        --exclude-dir=vendor \
        --exclude-dir=venv \
        --exclude-dir=.venv \
        --exclude-dir=mev-geth \
        . 2>/dev/null || true)

    if [ -n "$matches" ]; then
        echo "  Found $pattern:"
        echo "$matches" | head -n 20
        found_any=1
    fi
done

if [ $found_any -eq 1 ]; then
    echo ""
    echo "⚠️  Warning: TODO/FIXME markers found. Consider linking to issues:"
    echo "  TODO(https://github.com/LYFTIUM-INC/nodes/issues/123): implement feature X"
    echo "  FIXME(#456): fix bug in Y"
fi

exit 0
