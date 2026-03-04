# LastStack Whitepaper vs Demo Critique

## Paper (WHITE_PAPER.md)
- Strength: Presents an incremental path (Stage 1 annotations → Stage 2 IR-as-source → Stage 3 proofs) that is practical and aligned with LLVM/WASM ecosystems.
- Strength: Inline `@tag` navigation is well-motivated as zero-infra graph exposure for agent coders.
- Gaps: Annotation soundness is unspecified (e.g., how `@calls` accounts for indirect calls/varargs/inline asm); proof artifacts have no concrete, checkable format or cost model; persistence story (MFO) omits crash-consistency and recovery guarantees; trust base for the immutable verification layer is not scoped.

## Demo Implementation Review
- Scope mismatch: Paper highlights WASM server with contract enforcement; the shipped server is native Mach-O built from [demo/server.ll](/Users/lucas/code/laststack/demo/server.ll) and does not enforce pre/post at runtime.
- Missing artifact: `public/fractal.wasm` is absent; build relies on `llc/wasm-ld` to generate it, but the repo ships neither a binary nor the wasm-linked object, violating SPEC acceptance criteria.
- Annotation coverage: `server.ll` uses Stage 1 tags and PCF metadata on four functions; `fractal.ll` has no tags or PCF metadata, so the WASM module is unannotated despite the paper’s requirements.
- Proof story gap: `verify.sh` only prints metadata; there is no SMT solver invocation, and metadata symbols (e.g., `bytes_written`) are not bound to SSA values, making proofs non-checkable. No lint exists to reconcile `@calls/@reads` with actual IR.
- Invariant fidelity: `@handle_client` postcondition claims `bytes_written > 0` and fd closed; code closes fds but does not connect the SMT variable to the write result on all paths. `@build_response` claims Content-Length equals body length, but the file-serving path computes Content-Length at runtime and never cross-checks body size. `read_file` lacks buffer bound guarantees while callers assume 256 KB fits any file.
- WASM path: The fractal generator runs in the browser, but there is no runtime contract enforcement or proof metadata attached to it, contrary to the “WASM with proofs” claim in SPEC.

## Verdict
The demo illustrates the *idea* of inline annotations on a small native server, but it does not implement the paper’s verification stack. Key deliverables (proof discharge, wasm artifact, annotated WASM, runtime contract enforcement) are missing. Claims of “proof-carrying” are presently aspirational rather than realized.

## Concrete Fixes
- Check in a deterministic `public/fractal.wasm` or ensure the toolchain path produces it during CI; gate build on its presence.
- Add Stage 1 tags and PCF metadata to [demo/fractal.ll](/Users/lucas/code/laststack/demo/fractal.ll); enforce `@calls` symmetry across files.
- Implement the promised lint pass/script to compare IR calls and global accesses against `@calls/@reads`; fail the build on divergence.
- Bind SMT variables to SSA values (named metadata operands) and wire `verify.sh` to Z3/CVC5 so PCF specs are actually discharged.
- Either align the narrative to “native server, no runtime contracts (yet)” or add a minimal WASI host that checks pre/post at module boundaries to match the paper’s WASM contract story.
