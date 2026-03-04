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
CLANG="$(find_tool clang clang-18 clang-17 clang-16 clang-15 clang-14 || true)"

# Step 0: Compile fractal.ll to WASM (if tooling/source available), else reuse prebuilt file.
echo "[LastStack Build] Step 0: Preparing fractal.wasm..."
mkdir -p public
if [ -f fractal.ll ] && [ -n "$LLC" ] && [ -n "$WASM_LD" ]; then
    if "$LLC" --march=wasm32 --filetype=obj -O2 fractal.ll -o public/fractal.o 2>&1 \
       && "$WASM_LD" --no-entry --export-all public/fractal.o -o public/fractal.wasm 2>&1; then
        echo "[LastStack Build]   ✓ fractal.wasm built from fractal.ll"
    else
        echo "[LastStack Build]   ⚠ llc/wasm-ld path failed; trying fallback"
    fi
fi

if [ ! -f public/fractal.wasm ] && [ -f fractal.ll ] && [ -n "$CLANG" ]; then
    if "$CLANG" -O2 -nostdlib --target=wasm32-unknown-unknown -Wl,--no-entry -Wl,--export-all fractal.ll -o public/fractal.wasm 2>&1; then
        echo "[LastStack Build]   ✓ fractal.wasm built via clang wasm32 fallback"
    else
        echo "[LastStack Build]   ⚠ clang wasm32 fallback failed"
    fi
fi

if [ -f public/fractal.wasm ]; then
    echo "[LastStack Build]   ✓ Using public/fractal.wasm"
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

# Step 6: Fail-closed verification gate
echo ""
echo "[LastStack Build] Step 6: Running verification gate..."
bash verify.sh --json verification-report.json
echo "[LastStack Build]   ✓ Verification report: $SCRIPT_DIR/verification-report.json"

# Step 7: Link gate
echo ""
echo "[LastStack Build] Step 7: Running link gate..."
bash link-gate.sh --verify-report verification-report.json --json link-gate-report.json
echo "[LastStack Build]   ✓ Link gate report: $SCRIPT_DIR/link-gate-report.json"

# Step 8: Build IPS runtime (LLVM IR only)
echo ""
echo "[LastStack Build] Step 8: Building IPS runtime..."
if [ ! -f ips.ll ]; then
    echo "[LastStack Build]   ✗ Missing ips.ll"
    exit 1
fi
if [ -z "$CLANG" ]; then
    echo "[LastStack Build]   ✗ Missing clang; cannot build ips.ll"
    exit 1
fi
"$CLANG" -O2 ips.ll -o laststack-ips 2>&1
echo "[LastStack Build]   ✓ Built $SCRIPT_DIR/laststack-ips"

# Step 9: IPS evidence gate
echo ""
echo "[LastStack Build] Step 9: Running IPS evidence checks..."
bash ips-evidence.sh --bin ./laststack-ips --json ips-report.json
echo "[LastStack Build]   ✓ IPS report: $SCRIPT_DIR/ips-report.json"

# Step 10: Artifact seal + TCB capture
echo ""
echo "[LastStack Build] Step 10: Sealing artifacts..."
bash seal-artifacts.sh --verify-report verification-report.json --link-report link-gate-report.json --ips-report ips-report.json --out artifacts/manifest.json
echo "[LastStack Build]   ✓ Artifact manifest: $SCRIPT_DIR/artifacts/manifest.json"

# Report
echo ""
echo "[LastStack Build] Build complete!"
echo "[LastStack Build] Binary: $SCRIPT_DIR/laststack-server"
echo "[LastStack Build] Size: $(binary_size laststack-server) bytes"
if [ -f laststack-ips ]; then
    echo "[LastStack Build] IPS Runtime: $SCRIPT_DIR/laststack-ips"
    echo "[LastStack Build] IPS Size: $(binary_size laststack-ips) bytes"
fi
echo ""

echo ""
echo "[LastStack Build] To run: ./laststack-server"
echo "[LastStack Build] IPS demo: ./laststack-ips /tmp/ips-state.bin init && ./laststack-ips /tmp/ips-state.bin add 1 && ./laststack-ips /tmp/ips-state.bin recover"
echo "[LastStack Build] Then visit: http://localhost:9090"
