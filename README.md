# LastStack Demo

LastStack is a staged, agent-first software architecture described in **WHITE_PAPER.md** (“The Last Stack: A Post-Human Software Development Architecture”, Mar 2026). It moves code from text toward **proof-carrying LLVM IR**: each function ships with pre/postconditions, invariants, and a proof witness. Near-term, text stays but gains structural metadata; long-term, LLVM IR plus proofs becomes the canonical form.

This repo is a runnable demo of that philosophy:
- **Server** (`demo/server.ll`) — HTTP/1.1 server in LLVM IR with PCF-style metadata; serves static assets only.
- **WASM workload** (`demo/fractal.ll` → `public/fractal.wasm`) — Mandelbrot generator compiled to wasm32.
- **Client** (`demo/public/index.html`) — minimal HTML/JS: fetches the WASM, calls `generate_fractal`, and blits the returned pixel buffer directly to a `<canvas>`.
- **Benchmarks** — exercised via conventional k6 scenarios in CI (artifact: `k6-summary/benchmark.md`).

![Fractal output](docs/fractal-demo.png)

## Build & Run
Requirements:
- LLVM toolchain: `llc`, `wasm-ld` (preferred) or `clang` with wasm32 target. Any recent 14–18 should work.
- `clang` (native) to link the server.
- POSIX shell utilities. No Node/npm required.

Steps:
1) **Build** (server + wasm):  
   ```bash
   cd demo
   ./build.sh
   ```
   - Step 0 in `build.sh` always produces `public/fractal.wasm` (uses `llc+wasm-ld`, falls back to `clang --target=wasm32-unknown-unknown`).
2) **Run server** on :9090:  
   ```bash
   cd demo
   ./run.sh
   ```
   Then open http://localhost:9090/ — the page fetches `fractal.wasm` and renders continuously via `requestAnimationFrame`.
3) **Verify invariants** (lightweight proof checks): `cd demo && ./verify.sh`

## Benchmarks
- CI runs k6 against the demo server; results are published as `benchmark.md` (artifact `k6-summary`) with single-VU and 1000-VU RPS/p95 latency. Treat these as the canonical numbers.
- To reproduce locally, use a stock k6 HTTP script pointing at `http://localhost:9090/` with your chosen VU profile. No custom benchmark binary is included.

## Files to Read First
- `WHITE_PAPER.md` — motivation, staged roadmap (text → text+structure → IR+proofs).
- `demo/SPEC.md` — demo-specific architecture and constraints.
- `CRITIQUE.md` — open issues and risks.

The browser UI stays intentionally bare to spotlight the WASM output and the IR/proof story behind it. JS does nothing but fetch, instantiate, and blit the buffer returned by `generate_fractal`.
