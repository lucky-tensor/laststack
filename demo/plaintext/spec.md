# Plaintext Demo Specification

## Claim

An LLVM IR HTTP server authored by an agent — without hand-tuning, without frameworks, without a standard library — is performance-competitive with a naive Rust Hyper `current-thread` server at low-to-medium concurrency (c=256 to c=4096). At saturation (c=16384) the IR server loses; this is expected and disclosed — it uses a single-threaded accept loop, and Hyper's async runtime is built for that regime. Both implementations are agent first-pass; no hand-tuning was applied to either.

This demo reaches **L1 conformance**: PCF metadata is present and structurally checked. Proof discharge is not solver-backed — that is the role of the storage demo.

## Goal
Deliver a handwritten LLVM IR HTTP server that satisfies the TechEmpower FrameworkBenchmarks `plaintext` test. The server must respond to `GET /plaintext` (and any path) with `200 OK`, a `Content-Type: text/plain` header, and the constant body `Hello, World!` without heap allocations or standard library abstractions.

## Requirements
- Listen on port `18081` without needing env vars.
- Single-threaded accept loop; no connection pooling or `tokio`.
- Response is a single prebuilt buffer owned by the binary.
- PCF metadata attached to every gate-controlled function (`respond_plaintext`, `handle_client`, `main`).
- Verification (`verify.sh`) and link gate (`link-gate.sh`) must enforce metadata coverage.

## Build pipeline
- `clang` compiles `plaintext.ll` to `alienstack-plaintext` with `-O2`.
- `build.sh` runs the verification and link gates to fail closed if metadata is missing.
- `run.sh` builds and executes the server on the configured port.

## Benchmarks
CI runs the TFB plaintext profile (256, 1k, 4k, 16k concurrency wheels of `wrk`) against:
1. The LLVM IR plaintext server (this code).
2. Rust Hyper `current-thread` implementation (`demo/plaintext/hyper`).

The CI job captures `wrk` logs for each concurrency level to prove parity with the identical Hyper baseline.
