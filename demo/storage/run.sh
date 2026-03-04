#!/bin/bash
# ============================================================================
# LastStack Storage Demo: Run
# ============================================================================
# Builds the storage demo and runs a quick recovery scenario.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[Storage] Building..."
bash build.sh
echo ""

STATE_FILE="/tmp/laststack-ips-demo.bin"

echo "[Storage] Running scenario against $STATE_FILE"
./laststack-ips "$STATE_FILE" init
./laststack-ips "$STATE_FILE" add 1
./laststack-ips "$STATE_FILE" recover
