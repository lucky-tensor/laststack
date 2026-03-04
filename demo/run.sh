#!/bin/bash
# ============================================================================
# LastStack Demo: Run Server
# ============================================================================
# Builds (if needed) and runs the LastStack webserver.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Always build first to avoid stale/incompatible binaries.
echo "[LastStack] Building..."
bash build.sh
echo ""

# Run verification
echo "[LastStack] Running invariant verification..."
bash verify.sh
echo ""

# Start server
echo "[LastStack] Starting server..."
echo "[LastStack] Press Ctrl+C to stop."
echo ""
exec ./laststack-server
