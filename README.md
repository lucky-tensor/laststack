# LastStack Demo

LastStack is a staged, agent-first software architecture described in **docs/white-paper.md** (“The Last Stack: A Post-Human Software Development Architecture”, Mar 2026). It moves code from text toward **proof-carrying LLVM IR**: each function ships with pre/postconditions, invariants, and a proof witness. Near-term, text stays but gains structural metadata; long-term, LLVM IR plus proofs becomes the canonical form. The demo goal: a pure-LLVM HTTP server plus a WASM webpage, authored end-to-end by agents.

This repo is a runnable demo of that philosophy:
- **Server** (`demo/server.ll`) — HTTP/1.1 server in LLVM IR with PCF-style metadata; serves static assets only.
- **WASM workload** (`demo/fractal.ll` → `public/fractal.wasm`) — Mandelbrot generator compiled to wasm32.
- **Client** (`demo/public/index.html`) — minimal HTML/JS: fetches the WASM, calls `generate_fractal`, and blits the returned pixel buffer directly to a `<canvas>`.
- **IPS demo** (`demo/ips.ll`) — LLVM IR persistence runtime plus an evidence gate (`demo/ips-evidence.sh`) that checks init/add/recover behavior and corruption rejection.
- **Benchmarks** — exercised via conventional k6 scenarios in CI; results live in `docs/benchmark.md` (also published as artifact `k6-summary/benchmark.md`).

![Fractal output](docs/fractal-demo.png)

## Build & Run
Requirements:
- LLVM toolchain: `llc`, `wasm-ld` (preferred) or `clang` with wasm32 target. Any recent 14–18 should work.
- `clang` (native) to link the server.
- `rg` (ripgrep) for verification/evidence scripts.
- POSIX shell utilities. No Node/npm required.

Steps:
1) **Build** (server + wasm):  
   ```bash
   cd demo
   ./build.sh
   ```
   - Step 0 in `build.sh` produces `public/fractal.wasm`.
   - The build is fail-closed on `verify.sh`, `link-gate.sh`, and `ips-evidence.sh`; reports are written to `demo/verification-report.json`, `demo/link-gate-report.json`, and `demo/ips-report.json`.
2) **Run server** on :9090:  
   ```bash
   cd demo
   ./run.sh
   ```
   Then open http://localhost:9090/ — the page fetches `fractal.wasm` and renders continuously via `requestAnimationFrame`.
3) **Run IPS evidence standalone** (optional): `cd demo && ./ips-evidence.sh --bin ./laststack-ips --json ips-report.json`

## Benchmarks
- Latest results: see `docs/benchmark.md` (kept in-repo; CI also publishes the same file as artifact `k6-summary/benchmark.md`). Canonical scenarios: single VU and 1000 VU, reporting RPS and p95 latency.
- Run locally with any k6 script that hits `http://localhost:9090/`; for example:
  ```bash
  k6 run -e TARGET=http://localhost:9090 - <<'EOF'
  import http from 'k6/http';
  import { check } from 'k6';
  export const options = { vus: 1, iterations: 200 };
  export default () => {
    const res = http.get(`${__ENV.TARGET || 'http://localhost:9090/'}`);
    check(res, { 'status 200': r => r.status === 200 });
  };
  EOF
  ```

## Files to Read First
- `docs/white-paper.md` — motivation, staged roadmap (text → text+structure → IR+proofs).
- `docs/demo-spec.md` — demo-specific architecture and constraints.
- `docs/critique.md` — open issues and risks.

The browser UI stays intentionally bare to spotlight the WASM output and the IR/proof story behind it. JS does nothing but fetch, instantiate, and blit the buffer returned by `generate_fractal`.
