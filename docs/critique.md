# Fresh Critique of `docs/white-paper.md` (v1.2)

## Scope and Method

This critique evaluates the current whitepaper (`docs/white-paper.md`, v1.2) against the current repository implementation on branch `feat-close-spec-gaps`.

Evaluation criteria:
- Architectural coherence: are claims internally consistent?
- Scientific quality: are hypotheses and measurements falsifiable?
- Operational fit: can the stated gates map to real build/CI behavior?
- Evidence quality: are current-state claims traceable to code and scripts?

## What v1.2 Gets Right

### 1) It cleanly reconciles two real streams of work

The paper correctly combines:
- structural graph-comment infrastructure (`@fn/@calls/@reads` + extractor), and
- formal proof-carrying gate aspirations (effects, bind, link gate, sealing, TCB).

This avoids a false choice between “graph-first” and “formal-first.”

### 2) It shifts from ideology to measurable maturity

The conformance ladder (`L0`..`L4`) is the strongest part of the document. It prevents inflated claims by requiring explicit capability thresholds.

### 3) It uses evidence-first framing

Section 1 baseline statements align with repository reality and avoid pretending that verifier/link/sealing are complete on `master`.

### 4) It introduces a scientific evaluation frame

H1..H5 are falsifiable and force instrumentation discipline. This is materially better than narrative-only architecture docs.

## Core Critique

### A) v1.2 still mixes “spec” and “program plan” in the same level of authority

Problem:
- Some sections are normative requirements (“must emit manifest,” “reject edge”),
- others are roadmap-like measurements and hypotheses.

Impact:
- Hard to determine what is required for compliance now versus what is research instrumentation.

Recommendation:
- Split into two files or two explicit strata inside the paper:
  1. **Normative Spec** (must-pass release gates)
  2. **Research Program** (metrics/hypotheses, optional for compliance)

### B) The PCF schema is under-specified in this v1.2 revision

v1.2 names required keys (`pcf.schema`, `pcf.pre`, etc.) but does not fully pin wire format and canonical serialization in this revision text.

Impact:
- Independent implementations may interpret payload shape differently.
- Gate portability suffers.

Recommendation:
- Reintroduce one normative schema appendix with:
  - canonical encoding,
  - required/optional fields,
  - compatibility and versioning rules,
  - verifier failure behavior on unknown/missing fields.

### C) Link-gate semantics are conceptually correct but operationally incomplete

v1.2 defines edge checks, but does not define fallback policy under verifier uncertainty (timeouts, unknown SAT/SMT outcomes, solver divergence).

Impact:
- Different runners may produce different pass/fail outcomes for the same commit.

Recommendation:
- Add a strict policy table:
  - `valid` -> pass
  - `invalid` -> fail
  - `unknown/timeout` -> fail in release profile, warn in dev profile

### D) Artifact seal section needs a normative manifest schema id

The paper requires a manifest, but does not lock the schema id and required fields as a checksum-stable contract in this revision.

Impact:
- “sealed artifact” can become implementation-defined.

Recommendation:
- Define `laststack.artifact.v1` with required keys and hash algorithms.

### E) IPS section is principled but still detached from immediate adoption path

The paper correctly states IPS requirements, but no minimal first IPS scope is mandated (single object type, crash matrix, fsync model, etc.).

Impact:
- Teams can defer IPS indefinitely while still claiming architectural progress.

Recommendation:
- Add “minimum IPS compliance test” criteria (one durable object, deterministic crash-recovery harness, invariant proofs on replay).

## Evidence Check Against Current Branch

From current branch implementation:
- `demo/webserver/build.sh` now includes verification gate, link-gate, and artifact sealing steps.
- `demo/storage/build.sh` includes IPS runtime build and IPS evidence checks.
- `demo/webserver/verify.sh` is fail-closed and emits machine-readable JSON.
- `demo/webserver/fractal.ll` includes PCF metadata on exported functions in this branch state.
- `demo/webserver/server.ll` includes broader PCF coverage and effect/bind metadata in this branch state.

Interpretation:
- Branch implementation is ahead of baseline `master` and better aligned with v1.2 goals.
- Paper baseline remains historically correct for `master`, but a new section should explicitly track **branch-level** conformance when used for active R&D.

## Scientific Rigor Assessment

The scientific posture is substantially improved, but two additions are needed to make it robust:

1. Define exact data collection protocol per hypothesis (sampling window, environment controls, confidence interval method).
2. Require machine-readable experiment metadata (hardware profile, kernel/toolchain versions) for each reported metric.

Without these, hypothesis outcomes are easy to bias through test environment drift.

## Bottom Line

`docs/white-paper.md` v1.2 is directionally strong and substantially more rigorous than earlier versions. The central improvement is the conformance-level model tied to measurable outcomes.

The main remaining weakness is boundary clarity between normative release spec and research methodology. Fix that separation, pin schema-level contracts for PCF and artifact manifests, and add deterministic fallback policy for verifier uncertainty. Those steps would make the architecture both implementable and auditable across teams.

## Immediate Next Edits Recommended

1. Add a normative appendix for `laststack.pcf.v1` and `laststack.artifact.v1`.
2. Add verifier/link-gate uncertainty policy (`valid/invalid/unknown`) by profile.
3. Split compliance requirements from research hypotheses in document structure.
4. Add a concrete “minimum IPS compliance test” subsection.
