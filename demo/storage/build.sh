#!/bin/bash
# ============================================================================
# LastStack Storage Demo: Build Pipeline
# ============================================================================
# Compiles IPS LLVM IR to a native binary and runs the IPS evidence gate.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

find_tool() {
    local base="$1"
    shift || true
    local candidate

    for candidate in "$base" "$@"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

binary_size() {
    local path="$1"
    if stat -f%z "$path" >/dev/null 2>&1; then
        stat -f%z "$path"
    else
        stat -c%s "$path"
    fi
}

echo "[Storage Build] Starting build pipeline..."

CLANG="$(find_tool clang clang-18 clang-17 clang-16 clang-15 clang-14 || true)"
if [ -z "$CLANG" ]; then
    echo "[Storage Build] ✗ Missing clang"
    exit 1
fi

if [ ! -f ips.ll ]; then
    echo "[Storage Build] ✗ Missing ips.ll"
    exit 1
fi

echo "[Storage Build] Step 1: Building IPS runtime..."
"$CLANG" -O2 ips.ll -o laststack-ips 2>&1
echo "[Storage Build]   ✓ Built $SCRIPT_DIR/laststack-ips"

echo ""
echo "[Storage Build] Step 2: Running IPS evidence gate..."
bash ips-evidence.sh --bin ./laststack-ips --json ips-report.json
echo "[Storage Build]   ✓ IPS report: $SCRIPT_DIR/ips-report.json"

echo ""
echo "[Storage Build] Build complete!"
echo "[Storage Build] Binary: $SCRIPT_DIR/laststack-ips"
echo "[Storage Build] Size: $(binary_size laststack-ips) bytes"

echo ""
echo "[Storage Build] Demo: ./laststack-ips /tmp/ips-state.bin init && ./laststack-ips /tmp/ips-state.bin add 1 && ./laststack-ips /tmp/ips-state.bin recover"
