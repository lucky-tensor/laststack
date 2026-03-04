# LastStack Whitepaper v1.0 Critique

*Evaluated against white-paper.md (Version 1.0, March 2026) and the current demo state.*

---

## Paper Strengths

- **Section 1.1 is the best part.** The rationale for using `.ll` text over a proprietary binary source or AST dumps is honest and well-grounded in current LLM behavior (sequential token streams, local-span reasoning, no native graph memory). This is a genuine architectural insight, not marketing.
- **Removing the staged migration model is the right call.** The previous spec hedged with Stage 1/2/3 scaffolding. Stating the target directly forces honest accounting of what the demo does and does not prove.
- **Section 8 (Demo Mapping) is creditably honest.** The four items listed under "What remains" are accurate and non-trivial. Naming them in the paper is good practice.
- **PCF as the atomic unit (Section 3.1) is well-defined.** The six required metadata fields (pre, post, effects, bind, proof, verifier) provide a concrete interface shape. The LLVM metadata syntax example is actionable.

---

## Paper Gaps

### Proof format is unspecified
Section 3.1 requires a `pcf.proof` field containing a "checkable witness or certificate reference." The paper never specifies what this witness looks like, what format it uses (e.g., Lean proof term, Coq certificate, Boogie VCC output, Z3 model), or what the independent checker is. Without a concrete format, the requirement cannot be mechanically enforced — it can only be satisfied by convention.

### SMT obligation materialization is glossed over
Section 4.1 step 3 states "Materialize SMT obligations from pcf.pre/post, control-flow, and memory model." For LLVM IR with pointer arithmetic, aliasing, and integer-wrapping semantics, this is a research-level problem. The paper treats it as a pipeline step without acknowledging the complexity or referencing a concrete tool (e.g., SeaHorn, KLEE, SMACK). This gap is load-bearing: if the obligation extraction is unsound, the proof discharge is meaningless.

### Effect surface enforcement is fully unspecified
Section 3.3 says "Effect mismatch between declaration and body is a hard verification failure." Section 4.1 step 2 calls this "structural lint." Neither section specifies how indirect calls, function pointers, or inline assembly are handled in the call graph — the hardest cases. The paper needs either a scoping statement (e.g., "no function pointers in PCF-annotated code") or a concrete analysis strategy.

### IPS recovery proofs have no format or toolchain
Section 3.2 and Section 5 require that crash recovery "validates checksum/version/invariants before exposure" and that durability guarantees are "machine-checked in recovery tests." No proof format, no checker tool, and no test harness shape is given. This is the least developed section of the paper.

### Verified/Audit runtime mode boundary is unclear
Section 4.3 defines two runtime modes but does not specify when a system transitions between them, who controls the mode flag, or what the audit sampling rate and drift threshold are. Without operational parameters, the distinction is nominal.

---

## Demo vs. Specification

The paper's Section 10 (Definition of Done) defines six criteria for LastStack compliance. The demo satisfies none of them completely.

### What the demo now gets right
- `fractal.wasm` is built from `fractal.ll` via the toolchain pipeline and is present in `public/` — the prior missing-artifact issue is resolved.
- PCF metadata is present on 5 of 7 functions in `server.ll` (`@build_response`, `@check_invariants`, `@load_assets`, `@handle_client`, `@main`).
- LLVM metadata survives through `llvm-as` and is partially preserved through optimization (noted honestly in `build.sh`).

### Remaining gaps

**fractal.ll has zero PCF metadata.** All six functions (`@mandelbrot_iter`, `@generate_fractal`, `@get_buffer`, etc.) have no pre/post/proof annotations. The paper requires every *exported* behavior to be a PCF. The WASM module is the most visible artifact of the demo, and it carries no proofs.

**Two server functions have no PCF.** `@read_file` and `@get_content_type` are called by annotated functions but carry no PCF metadata themselves. `@read_file` is the most dangerous omission: it takes an unchecked buffer size and callers assume 256 KB is always sufficient. There is no contract bounding this.

**No `!pcf.effects` declarations exist anywhere.** The paper's Effect Surface requirement (Section 3.3) is unimplemented in both `server.ll` and `fractal.ll`. No syscall declarations, no global-write declarations, no I/O class declarations. Effect lint cannot be run because there is nothing to lint against.

**`verify.sh` is a metadata reader, not a verifier.** It greps IR for annotation presence and unconditionally prints `PASS (static check — SMT discharge requires Z3)`. It performs no solver invocation, no SSA-value binding check, and no call-graph reconciliation. A build that "passes" verification currently means only that annotations exist syntactically.

**The build pipeline has no link gate.** Section 4.1 step 5 requires that only modules whose PCFs pass verification and effect compatibility checks are linked. `build.sh` links unconditionally. A function with a broken postcondition or missing proof is indistinguishable from a correct one at link time.

**No artifact seal.** The paper requires a manifest containing digests for IR, proofs, toolchain, and benchmark snapshot. No such manifest is generated or committed.

**TCB is not scoped.** The paper requires TCB versions and hashes in sealed manifests (Section 6). The toolchain versions used in CI are not recorded in any committed artifact.

**No IPS.** Persistent state uses the OS filesystem directly. No typed binary schema, no invariant validation on mutation, no crash recovery protocol.

---

## Verdict

The whitepaper v1.0 is a well-scoped, honest target-state specification. Its decision to drop the staged migration model, define PCF as the atomic unit with concrete metadata fields, and scope the TCB explicitly represents a meaningful tightening over the prior draft.

The demo is proof-of-concept at the annotation layer only. It shows that LLVM IR can serve as a practical source representation and that PCF-shaped metadata can be attached to functions. It does not demonstrate proof discharge, effect enforcement, link gating, or the IPS persistence model. The paper's own Section 8 acknowledges this accurately.

The most important near-term actions to close the gap:

1. Add `!pcf.pre`, `!pcf.post`, `!pcf.effects`, `!pcf.proof` metadata to all exported functions in `fractal.ll`.
2. Add `!pcf.effects` to all annotated functions in `server.ll`; implement an effect lint script that cross-checks declared effects against IR call graph and global accesses, and fail the build on mismatch.
3. Specify the proof witness format (even a stub format) so `verify.sh` can distinguish a valid proof from an empty metadata node.
4. Replace the hardcoded PASS in `verify.sh` with a real gate: fail if any PCF-annotated function is missing required metadata fields, and flag unannotated exported functions.
5. Commit a toolchain digest file alongside each build to make the TCB claim actionable.
