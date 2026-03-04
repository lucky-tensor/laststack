#!/bin/bash
# ============================================================================
# LastStack Demo: Build Pipeline
# ============================================================================
# Compiles LLVM IR → optimized IR → native binary
#
# Pipeline:
#   1. Verify IR is well-formed (llvm-as)
#   2. Optimize IR (opt -O2)
#   3. Compile to native object (llc)
#   4. Link to executable (clang)
#
# In a full LastStack system, steps 1-2 would include proof-checking passes
# and invariant metadata validation. The metadata survives optimization
# as LLVM preserves named metadata through standard passes.
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

echo "[LastStack Build] Starting build pipeline..."

LLVM_AS="$(find_tool llvm-as llvm-as-18 llvm-as-17 llvm-as-16 llvm-as-15 llvm-as-14 || true)"
OPT="$(find_tool opt opt-18 opt-17 opt-16 opt-15 opt-14 || true)"
LLC="$(find_tool llc llc-18 llc-17 llc-16 llc-15 llc-14 || true)"
WASM_LD="$(find_tool wasm-ld wasm-ld-18 wasm-ld-17 wasm-ld-16 wasm-ld-15 wasm-ld-14 || true)"
LLVM_DIS="$(find_tool llvm-dis llvm-dis-18 llvm-dis-17 llvm-dis-16 llvm-dis-15 llvm-dis-14 || true)"

# Step 0: Compile fractal.ll to WASM (if tooling/source available), else reuse prebuilt file.
echo "[LastStack Build] Step 0: Preparing fractal.wasm..."
if [ -f fractal.ll ] && [ -n "$LLC" ] && [ -n "$WASM_LD" ]; then
    "$LLC" --march=wasm32 --filetype=obj -O2 fractal.ll -o public/fractal.o 2>&1
    "$WASM_LD" --no-entry --export-all public/fractal.o -o public/fractal.wasm 2>&1
    echo "[LastStack Build]   ✓ fractal.wasm built from fractal.ll"
elif [ -f public/fractal.wasm ]; then
    echo "[LastStack Build]   ✓ Using existing public/fractal.wasm"
else
    echo "[LastStack Build]   ✗ Missing fractal.wasm and no WASM build toolchain/source"
    exit 1
fi

if [ -n "$LLVM_AS" ] && [ -n "$OPT" ] && [ -n "$LLC" ]; then
    # Full LLVM pipeline.
    echo "[LastStack Build] Step 1: Verifying IR well-formedness..."
    "$LLVM_AS" server.ll -o server.bc 2>&1
    echo "[LastStack Build]   ✓ IR parsed and verified"

    echo "[LastStack Build] Step 2: Optimizing IR (O2)..."
    "$OPT" -O2 server.bc -o server-opt.bc 2>&1
    echo "[LastStack Build]   ✓ IR optimized"

    echo "[LastStack Build] Step 3: Compiling to native object..."
    "$LLC" -O2 -relocation-model=pic -filetype=obj server-opt.bc -o server.o 2>&1
    echo "[LastStack Build]   ✓ Native object generated"

    echo "[LastStack Build] Step 4: Linking executable..."
    clang server.o -o laststack-server 2>&1
    echo "[LastStack Build]   ✓ Executable linked"
else
    # Portable fallback when standalone LLVM tools are not installed.
    echo "[LastStack Build] Step 1: LLVM toolchain not fully available; using clang fallback..."
    clang -c server.ll -o server.o 2>&1
    clang server.o -o laststack-server 2>&1
    echo "[LastStack Build]   ✓ Built via clang fallback"
fi

# Report
echo ""
echo "[LastStack Build] Build complete!"
echo "[LastStack Build] Binary: $SCRIPT_DIR/laststack-server"
echo "[LastStack Build] Size: $(binary_size laststack-server) bytes"
echo ""

# Step 5: Verify metadata survived optimization
echo "[LastStack Build] Step 5: Checking PCF metadata survival..."
if [ -n "$LLVM_DIS" ] && [ -f server-opt.bc ]; then
    METADATA_COUNT=$("$LLVM_DIS" server-opt.bc -o - 2>/dev/null | grep -c '!{!"pcf\.\|!{!"ips\.' || true)
    echo "[LastStack Build]   Found $METADATA_COUNT PCF/IPS metadata nodes in optimized IR"
    if [ "$METADATA_COUNT" -gt 0 ]; then
        echo "[LastStack Build]   ✓ Proof-carrying metadata survived optimization"
    else
        echo "[LastStack Build]   ⚠ Metadata was stripped (expected with standard passes)"
        echo "[LastStack Build]     In production, custom metadata-preserving passes would retain these"
    fi
else
    echo "[LastStack Build]   ⚠ Skipped (llvm-dis or optimized bitcode unavailable in fallback build)"
fi

echo ""
echo "[LastStack Build] To run: ./laststack-server"
echo "[LastStack Build] Then visit: http://localhost:9090"
