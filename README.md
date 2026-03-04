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

Latest recorded k6 benchmark snapshot (2026-03-04T18:37:58Z):

| scenario | rps | p95_latency_s |
|---|---:|---:|
| single_vu | 3421.084244877707 | 0.15918009999999996 |
| 1000_vus | 3815.592037200089 | 18.719029599999995 |

CI still runs the same k6 scenarios against `demo/webserver`, and raw summaries are kept in the `k6-summary` workflow artifact.

## Files to Read First

- `docs/white-paper.md`
- `demo/webserver/spec.md`
- `demo/storage/spec.md`
- `docs/critique.md`
