# Demos

- [`demo/webserver`](webserver/spec.md) - LLVM IR HTTP server + WASM fractal client demo.
- [`demo/storage`](storage/spec.md) - LLVM IR IPS durability and recovery demo.
- [`demo/ui-kit`](ui-kit/spec.md) - Isomorphic UI Kit (LLVM IR to Wasm styling and logic).
- [`demo/plaintext`](plaintext/spec.md) - LLVM IR plaintext HTTP server tailored for the TFB plaintext benchmark.

Each demo has its own `spec.md` (linked above) and build pipeline (`build.sh`). The native demos (webserver, storage, plaintext) target x86_64 Linux; ui-kit targets wasm32.
