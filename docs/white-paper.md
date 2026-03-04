# The Last Stack: Reconciled Architecture for Agent-Native Software

**Version 1.2 - March 2026**

## Abstract

LastStack targets one architecture: executable behavior authored in LLVM IR, machine-checkable contracts attached to exported behavior, and release artifacts gated by verification. This revision reconciles two active lines of work in this repository:
- Structural graph comments and extraction tooling now present on `master`.
- Formal verification semantics (effects, bindings, proof artifacts, link gate, artifact sealing) proposed in parallel.

The result is a single coherent specification grounded in measured repository state.

## 1. Empirical Baseline (Repository State)

Baseline commit for this assessment: `fbf810c` (`master`, March 4, 2026).

Observed facts:
- `demo/webserver/server.ll` and `demo/webserver/fractal.ll` include structured graph comments (`@module`, `@fn`, `@calls`, `@reads`, etc.).
- `tools/extract-graph` parses those comments into JSON and summary views.
- `demo/webserver/server.ll` contains PCF metadata on 5 of 7 functions.
- `demo/webserver/fractal.ll` exports are currently unannotated as PCFs.
- No `!pcf.effects` or `!pcf.bind` metadata exists in `master` demo IR.
- `demo/webserver/verify.sh` is report-oriented and not a fail-closed proof gate.
- Build/CI have no enforced link gate, artifact sealing manifest, or TCB capture.
- CI benchmark reporting is operational via `k6-summary` artifacts.

This baseline is the evidence foundation for the architecture below.

## 2. Reconciled Thesis

LastStack is defined by four non-negotiable constraints:

1. **Canonical behavior is LLVM IR.**
   Runtime semantics are defined by `.ll` modules and their compiled artifacts.

2. **Agent interface is text plus structure.**
   Agents operate over sequential text; therefore structural graph comments remain first-class, extractable, and diffable.

3. **Contracts are machine obligations, not prose.**
   Exported behavior must carry verifiable pre/post/effect/bind/proof metadata.

4. **Release is gate-driven.**
   Build success requires verification pass, link compatibility pass, and artifact seal generation.

## 3. Architecture

### 3.1 Structural Graph Layer (Implemented on `master`)

Source files embed graph comments directly in IR:
- Node tags: `@module`, `@fn`, `@global`, `@type`
- Edge tags: `@calls`, `@reads`, `@writes`, `@called-by`, `@uses-type`, `@exports`, `@emits`
- Contract-adjacent tags: `@pre`, `@post`, `@inv`, `@proof`, `@cfg`

`tools/extract-graph` is the canonical parser for this layer.

Structural invariants:
- Every declared edge must reference a declared node id.
- `@calls` and `@called-by` must be logically consistent where both are present.
- Extracted graph output is deterministic for a fixed file set and parser version.

### 3.2 Contract Layer (Required for Compliance)

Every exported PCF must include:
- `pcf.schema` (required: `laststack.pcf.v1`)
- `pcf.pre`
- `pcf.post`
- `pcf.effects`
- `pcf.bind`
- `pcf.proof`
- `pcf.toolchain`

#### 3.2.1 Effect Model

Canonical effect atoms:
- `sys.<name>`
- `libc.<name>`
- `global.read:<symbol>`
- `global.write:<symbol>`
- `io.net.<op>`, `io.fs.<op>`
- `nondet.clock`, `nondet.random`, `nondet.env`, `nondet.signal`
- `alloc.heap`, `alloc.mmap`, `thread.spawn`, `thread.sync`

Matching rule:
- `actual_effects <= declared_effects` (set inclusion)
- Any unresolved atom (`effect.unknown:*`) is a release failure.

#### 3.2.2 Binding Model (`pcf.bind`)

Binding kinds:
- `arg`, `ret`, `mem`, `state`, `exc`

Binding invariants:
- Every free symbol in `pcf.pre/post` resolves to exactly one binding.
- Memory bindings use region identity `<base-object, [start,end), lifetime>`.
- Alias groups are explicit.
- Missing or ambiguous bindings fail verification.

#### 3.2.3 Proof Artifact Envelope

Required envelope fields (`lspc.v1`):
- `format`, `goal_hash`, `method`, `checker`, `checker_hash`, `assumptions`, `result`
- optional `signature`

Hashing/compatibility:
- Canonical JSON encoding.
- Default hash: SHA-256.
- Proof validity requires matching `goal_hash`, schema, and checker digest.

### 3.3 Verification and Link Gate

Pipeline (fail-closed):
1. Parse and canonicalize IR modules.
2. Validate structural graph consistency.
3. Validate PCF completeness on required functions.
4. Materialize and check obligations (`pre/post/effects/bind/proof`).
5. Run link gate on resolved call edges.
6. Emit machine-readable verifier and link reports.

Link gate rules per edge `caller -> callee`:
- Schema compatibility.
- Caller proves callee precondition at callsite.
- Callee postcondition satisfies caller continuation assumptions.
- Callee effects are allowed in caller context.
- ABI and binding compatibility.

Reject on any failed condition.

### 3.4 Artifact Seal and TCB Capture

Every releasable build must emit a manifest containing:
- commit SHA
- IR file digests
- proof artifact digests
- verifier/link report digests
- benchmark snapshot digest
- toolchain and checker records (`path`, `version`, `sha256`)

TCB scope in manifest:
- LLVM toolchain components used
- verifier/checker binaries
- linker and sealing tool
- runtime/kernel assumptions profile id

### 3.5 IPS Persistence Layer

IPS is required for durable state claims:
- typed layout id
- epoch counter
- checksum-protected frames
- commit protocol with explicit flush points
- recovery replay/rollback rules
- invariant re-validation before exposure

Without IPS implementation, persistence claims are non-compliant.

## 4. Conformance Levels (Measurement, Not Roadmap)

- **L0 Structural**: Graph comments parse and pass consistency checks.
- **L1 Contract Complete**: Required functions have full PCF metadata (`pre/post/effects/bind/proof`).
- **L2 Verified**: Solver/checker-backed verification is fail-closed in build.
- **L3 Linked and Sealed**: Link gate enforced and artifact manifest emitted with TCB capture.
- **L4 Durable**: IPS recovery protocol implemented and validated under crash tests.

A system may claim only the highest level whose criteria are fully met.

## 5. Scientific Evaluation Plan

This architecture is tested with falsifiable hypotheses:

- **H1 Structural indexing reduces agent search cost.**
  Metric: median files opened, prompt tokens consumed, and wall-clock latency for impact-analysis tasks.

- **H2 Effect declarations catch real regressions.**
  Metric: number of undeclared side effects caught pre-merge by effect lint.

- **H3 Link gate prevents contract regressions.**
  Metric: rejected edges due to pre/post/effect incompatibility vs escaped regressions.

- **H4 Artifact sealing improves reproducibility.**
  Metric: successful deterministic rebuild rate from manifest-only replay.

- **H5 IPS recovery preserves invariants under fault injection.**
  Metric: invariant-preserving recovery success rate across crash points.

All hypothesis tests require machine-readable outputs committed or archived by CI.

## 6. Current Status Against This Spec

At baseline `fbf810c`:
- **Meets**: L0 (structural graph comments + extractor), benchmark policy operations.
- **Partially meets**: L1 (server partial PCF coverage only).
- **Does not meet**: L2, L3, L4.

This is an implementation maturity statement, not a philosophy change.

## 7. Definition of Done

A LastStack-compliant release must satisfy all of:
- Canonical LLVM IR behavior modules.
- Full PCF coverage on exported/critical interfaces.
- Fail-closed verifier and link gate in the build path.
- Artifact seal with explicit TCB records.
- IPS-backed durable state for persistence claims.
- CI benchmark evidence archived and reproducible.

This reconciled architecture keeps what is already working (structural graph for agents) and formalizes what must still be enforced (verification, linking, sealing, and durability).
