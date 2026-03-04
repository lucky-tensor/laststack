#!/bin/bash
# ============================================================================
# LastStack Webserver Demo: Build Pipeline
# ============================================================================
# Compiles LLVM IR -> optimized IR -> native binary and runs webserver gates.
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

echo "[Webserver Build] Starting build pipeline..."

LLVM_AS="$(find_tool llvm-as llvm-as-18 llvm-as-17 llvm-as-16 llvm-as-15 llvm-as-14 || true)"
OPT="$(find_tool opt opt-18 opt-17 opt-16 opt-15 opt-14 || true)"
LLC="$(find_tool llc llc-18 llc-17 llc-16 llc-15 llc-14 || true)"
WASM_LD="$(find_tool wasm-ld wasm-ld-18 wasm-ld-17 wasm-ld-16 wasm-ld-15 wasm-ld-14 || true)"
LLVM_DIS="$(find_tool llvm-dis llvm-dis-18 llvm-dis-17 llvm-dis-16 llvm-dis-15 llvm-dis-14 || true)"
CLANG="$(find_tool clang clang-18 clang-17 clang-16 clang-15 clang-14 || true)"

# Step 0: Compile fractal.ll to WASM (if tooling/source available), else reuse prebuilt file.
echo "[Webserver Build] Step 0: Preparing fractal.wasm..."
mkdir -p public
if [ -f fractal.ll ] && [ -n "$LLC" ] && [ -n "$WASM_LD" ]; then
    if "$LLC" --march=wasm32 --filetype=obj -O2 fractal.ll -o public/fractal.o 2>&1 \
       && "$WASM_LD" --no-entry --export-all public/fractal.o -o public/fractal.wasm 2>&1; then
        echo "[Webserver Build]   ✓ fractal.wasm built from fractal.ll"
    else
        echo "[Webserver Build]   ⚠ llc/wasm-ld path failed; trying fallback"
    fi
fi

if [ ! -f public/fractal.wasm ] && [ -f fractal.ll ] && [ -n "$CLANG" ]; then
    if "$CLANG" -O2 -nostdlib --target=wasm32-unknown-unknown -Wl,--no-entry -Wl,--export-all fractal.ll -o public/fractal.wasm 2>&1; then
        echo "[Webserver Build]   ✓ fractal.wasm built via clang wasm32 fallback"
    else
        echo "[Webserver Build]   ⚠ clang wasm32 fallback failed"
    fi
fi

if [ -f public/fractal.wasm ]; then
    echo "[Webserver Build]   ✓ Using public/fractal.wasm"
else
    echo "[Webserver Build]   ✗ Missing fractal.wasm and no WASM build toolchain/source"
    exit 1
fi

if [ -n "$LLVM_AS" ] && [ -n "$OPT" ] && [ -n "$LLC" ]; then
    # Full LLVM pipeline.
    echo "[Webserver Build] Step 1: Verifying IR well-formedness..."
    "$LLVM_AS" server.ll -o server.bc 2>&1
    echo "[Webserver Build]   ✓ IR parsed and verified"

    echo "[Webserver Build] Step 2: Optimizing IR (O2)..."
    "$OPT" -O2 server.bc -o server-opt.bc 2>&1
    echo "[Webserver Build]   ✓ IR optimized"

    echo "[Webserver Build] Step 3: Compiling to native object..."
    "$LLC" -O2 -relocation-model=pic -filetype=obj server-opt.bc -o server.o 2>&1
    echo "[Webserver Build]   ✓ Native object generated"

    echo "[Webserver Build] Step 4: Linking executable..."
    "$CLANG" server.o -o laststack-server 2>&1
    echo "[Webserver Build]   ✓ Executable linked"
else
    # Portable fallback when standalone LLVM tools are not installed.
    echo "[Webserver Build] Step 1: LLVM toolchain not fully available; using clang fallback..."
    "$CLANG" -c server.ll -o server.o 2>&1
    "$CLANG" server.o -o laststack-server 2>&1
    echo "[Webserver Build]   ✓ Built via clang fallback"
fi

# Step 5: Verify metadata survived optimization
echo "[Webserver Build] Step 5: Checking PCF metadata survival..."
if [ -n "$LLVM_DIS" ] && [ -f server-opt.bc ]; then
    METADATA_COUNT=$("$LLVM_DIS" server-opt.bc -o - 2>/dev/null | grep -c '!{!"pcf\.' || true)
    echo "[Webserver Build]   Found $METADATA_COUNT PCF metadata nodes in optimized IR"
    if [ "$METADATA_COUNT" -gt 0 ]; then
        echo "[Webserver Build]   ✓ Proof-carrying metadata survived optimization"
    else
        echo "[Webserver Build]   ⚠ Metadata was stripped (expected with standard passes)"
        echo "[Webserver Build]     In production, custom metadata-preserving passes would retain these"
    fi
else
    echo "[Webserver Build]   ⚠ Skipped (llvm-dis or optimized bitcode unavailable in fallback build)"
fi

# Step 6: Fail-closed verification gate
echo ""
echo "[Webserver Build] Step 6: Running verification gate..."
bash verify.sh --json verification-report.json
echo "[Webserver Build]   ✓ Verification report: $SCRIPT_DIR/verification-report.json"

# Step 7: Link gate
echo ""
echo "[Webserver Build] Step 7: Running link gate..."
bash link-gate.sh --verify-report verification-report.json --json link-gate-report.json
echo "[Webserver Build]   ✓ Link gate report: $SCRIPT_DIR/link-gate-report.json"

# Step 8: Artifact seal + TCB capture
echo ""
echo "[Webserver Build] Step 8: Sealing artifacts..."
bash seal-artifacts.sh --verify-report verification-report.json --link-report link-gate-report.json --out artifacts/manifest.json
echo "[Webserver Build]   ✓ Artifact manifest: $SCRIPT_DIR/artifacts/manifest.json"

# Report
echo ""
echo "[Webserver Build] Build complete!"
echo "[Webserver Build] Binary: $SCRIPT_DIR/laststack-server"
echo "[Webserver Build] Size: $(binary_size laststack-server) bytes"
echo ""

echo ""
echo "[Webserver Build] To run: ./laststack-server"
echo "[Webserver Build] Then visit: http://localhost:9090"
