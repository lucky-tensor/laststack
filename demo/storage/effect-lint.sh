#!/bin/bash
# Thin wrapper retained for backwards compatibility.
# The effect lint is now shared across demos: see tools/effect-lint.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
exec bash ../../tools/effect-lint.sh "${1:-ips.ll}" "${2:-effect-lint-report.json}"