# LastStack Demo

LastStack is a staged, agent-first software architecture described in `docs/white-paper.md`. The demo goal: a pure LLVM server and webpage (wasm) written by agents.

This repository now has two separate demos:
- `demo/webserver` - LLVM IR HTTP server + WASM fractal webpage.
- `demo/storage` - LLVM IR IPS durability and recovery runtime.

![Fractal output](docs/fractal-demo.png)

## Requirements

- LLVM toolchain (`llc`, `wasm-ld` preferred; `clang` fallback for wasm build)
- `clang` for native binaries
- `rg` (ripgrep) for gate scripts
- POSIX shell tools

## Webserver Demo

Build and run:

```bash
cd demo/webserver
./build.sh
./run.sh
```

Open `http://localhost:9090`.

Spec:
- `demo/webserver/spec.md`

Key generated outputs:
- `demo/webserver/public/fractal.wasm`
- `demo/webserver/laststack-server`
- `demo/webserver/verification-report.json`
- `demo/webserver/link-gate-report.json`
- `demo/webserver/artifacts/manifest.json`

## Storage Demo

Build and run:

```bash
cd demo/storage
./build.sh
./run.sh
```

Spec:
- `demo/storage/spec.md`

Key generated outputs:
- `demo/storage/laststack-ips`
- `demo/storage/ips-report.json`

## Benchmarks

Latest recorded k6 benchmark snapshot (from `k6-summary`, run `22686374237`, 2026-03-04T19:49:33Z):

| scenario | rps | p95_latency_s |
|---|---:|---:|
| single_vu | 3575.1656712592244 | 0.14615974999999995 |
| 1000_vus | 12929.951548136494 | 17.632081399999997 |

CI still runs the same k6 scenarios against `demo/webserver`, and raw summaries are kept in the `k6-summary` workflow artifact.

## Files to Read First

- `docs/white-paper.md`
- `demo/webserver/spec.md`
- `demo/storage/spec.md`
- `docs/critique.md`
