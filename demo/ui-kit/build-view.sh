#!/bin/bash
set -e
cd "$(dirname "$0")"

CLANG_CMD="clang"
if command -v clang-18 >/dev/null 2>&1; then
    CLANG_CMD="clang-18"
elif command -v clang-17 >/dev/null 2>&1; then
    CLANG_CMD="clang-17"
fi

$CLANG_CMD --target=wasm32-unknown-unknown -nostdlib -O3 \
    -Wl,--no-entry \
    -Wl,--export=init \
    -Wl,--export=on_event \
    -Wl,--allow-undefined \
    ir/button.ll -o view.wasm

echo "Built view.wasm"
