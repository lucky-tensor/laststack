#!/bin/bash
# =============================================================================
# Alien Stack Plaintext Demo: Build pipeline
# =============================================================================
# Compiles plaintext LLVM IR -> native binary and runs Alien Stack verification gates.
# =============================================================================

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

echo "[Plaintext Build] Starting build pipeline..."

CLANG="$(find_tool clang clang-18 clang-17 clang-16 clang-15 clang-14 || true)"
if [ -z "$CLANG" ]; then
    echo "[Plaintext Build] ✗ clang not found"
    exit 1
fi

if [ ! -f plaintext.ll ]; then
    echo "[Plaintext Build] ✗ Missing plaintext.ll"
    exit 1
fi

echo "[Plaintext Build] Step 1: Compiling plaintext server"
"$CLANG" -O2 plaintext.ll -o alienstack-plaintext
echo "[Plaintext Build]   ✓ Binary: $SCRIPT_DIR/alienstack-plaintext"

echo
bash verify.sh --json verification-report.json
bash link-gate.sh --verify-report verification-report.json --json link-gate-report.json

echo
echo "[Plaintext Build] Running structural effect lint..."
bash ../../tools/effect-lint.sh plaintext.ll effect-lint-report.json || {
    echo "[Plaintext Build] ✗ Effect lint failed — undeclared effects found"
    exit 1
}
echo "[Plaintext Build]   ✓ Effect lint report: $SCRIPT_DIR/effect-lint-report.json"

echo
echo "[Plaintext Build] Build complete!"
echo "[Plaintext Build] Binary size: $(binary_size alienstack-plaintext) bytes"
