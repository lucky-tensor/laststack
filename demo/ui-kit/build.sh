#!/bin/bash
set -e
# Compile LLVM IR to Wasm
# Requires clang and wasm-ld

cd "$(dirname "$0")"

mkdir -p ir

# If no .ll files exist, we just exit (for testing script itself)
if ! ls ir/*.ll 1> /dev/null 2>&1; then
    echo "No .ll files found."
    exit 0
fi

if command -v brew >/dev/null 2>&1; then
    export PATH="$(brew --prefix llvm)/bin:$PATH"
fi

# Look for clang-18, clang etc since Apple clang doesn't support wasm
CLANG_CMD="clang"
if command -v clang-18 >/dev/null 2>&1; then
    CLANG_CMD="clang-18"
elif command -v clang-17 >/dev/null 2>&1; then
    CLANG_CMD="clang-17"
fi

# We compile all IR files
$CLANG_CMD --target=wasm32-unknown-unknown -nostdlib -O3 \
    -Wl,--no-entry \
    -Wl,--export=init \
    -Wl,--export=on_event \
    -Wl,--allow-undefined \
    ir/*.ll -o app.wasm

echo "Successfully built app.wasm"
