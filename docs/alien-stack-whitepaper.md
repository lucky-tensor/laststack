# The Alien Stack: Architecture for Agent-Native Software

**Version 2.0 — March 2026**

> **Research Paper.** This document is a scientific specification. It defines an architecture, the formal properties it requires, and falsifiable hypotheses for evaluation. The accompanying repository contains proof-of-concept demonstrations that validate the foundational claims. The demos are not production software — they exist to show that the core ideas are technically coherent and implementable. The full architecture (L2–L4 conformance, solver-backed verification, mechanically checked proof certificates) remains future work.

---

## Abstract

Software development has been shaped by human cognitive constraints for seven decades. Languages use English keywords. Source code is stored as text files. Build systems orchestrate tools designed for human workflows. These choices made sense when humans were the primary authors and readers of code. As agent coders take on an increasing share of implementation work, the assumptions behind these choices deserve reexamination.

But reexamination does not mean wholesale replacement. Current agent coders — large language models — are themselves text-native. They read text, reason in text, and emit text. Asking them to abandon text for raw IR is like asking a carpenter to work without hands. The transition must be incremental, and every stage must be independently useful.

**Alien Stack** defines an end-state architecture for software built primarily by coding agents: executable behavior authored in LLVM IR, machine-checkable contracts attached to every exported function, structural graph annotations navigable with grep, and release artifacts gated by formal verification. Text remains the agent-facing interface. Formal contracts create higher assurances for software that is built and run without human intervention — not by replacing tests, but by raising the floor of correctness that tests validate against. The build succeeds only when contracts are discharged, effects are declared, and artifacts are reproducible.

This paper specifies the architecture, the rationale behind it, and a concrete path from today's text-only codebases to the fully verified target.

---

## 1. Motivation

### 1.1 The Cost of Human-Centric Design

Modern software stacks impose five categories of overhead that exist solely to accommodate human cognition:

1. **Parsing overhead.** Source code is text. Text must be lexed, parsed into ASTs, type-checked, lowered to IR, optimized, and emitted as machine code. Each transformation is a potential source of bugs and a barrier to formal reasoning. An agent coder gains nothing from the text representation — it is a detour.

2. **Semantic ambiguity.** Human languages are ambiguous by design. Programming languages inherit this: operator overloading, implicit conversions, dynamic dispatch, macro expansion. Each feature adds expressiveness for humans at the cost of formal tractability. An agent reasons more effectively over a representation with explicit semantics.

3. **File-system coupling.** Code stored as text files inherits the file system's limitations: no type safety, no referential integrity, no transactional updates. Renaming a function requires a text search across files. An agent coder needs a representation where structural references are first-class.

4. **Testing as simulation.** Humans write tests because they cannot formally verify their code. Tests check a finite number of execution paths. Formal verification checks all of them. An agent coder that can generate and check proofs has no need for example-based testing as the primary correctness mechanism.

5. **Library indirection.** Human developers use libraries to avoid re-implementing solved problems. But libraries introduce dependency graphs, version conflicts, API surface area, and trust boundaries. In the human-centric model, libraries are essential because no individual can maintain everything — shared maintenance, security patching, and ecosystem coordination require social infrastructure.

   Agent coders change this calculus fundamentally. An agent that is both engineer and compiler can re-derive a patched implementation from a specification faster than it can track upstream changelogs. When the agent can verify the inlined result against a formal contract, the trust boundary that justified the library abstraction dissolves. Libraries remain useful for hardware-specific optimizations and externally mandated interfaces (e.g., TLS compliance), but the default posture shifts from "import a dependency" to "generate a verified implementation."

### 1.2 The Agent Text Problem

The critique above might suggest that text should be eliminated immediately. It should not. Current agent coders are LLMs — they think in text. Their training data is text. Their interface is text. Text is not merely a convenience for them; it is their native representation.

But agents pay a hidden tax every time they work with text-only codebases. Consider what an agent must do to answer "what breaks if I rename this function?":

1. Grep for the function name across all files.
2. Read each matching file to distinguish definitions from calls from string mentions.
3. Mentally reconstruct the call graph from these scattered text fragments.
4. Determine the blast radius.
5. Repeat if the function is called transitively.

A compiler answers this question instantly — it has already built the call graph, the type map, the reference index. But that information is discarded after compilation. The agent is left to re-derive it from text every time.

The cost is measured in context window tokens, latency, and errors. An agent that reads 20 files to trace a call chain burns thousands of tokens on content it doesn't need and risks missing references it never opened. This is not a text problem — it is a *structure-locked-inside-text* problem.

The solution is not to take text away from agents. It is to give them structure *alongside* text.

### 1.3 Agent Interface Constraints (Today)

The architecture is designed for current LLM-based agents, not hypothetical future models:

- Agents read and write text files through sequential token streams.
- Agents reason primarily over local spans and diffs, then stitch global behavior from repeated passes.
- Agents cannot reliably mount a full external knowledge graph as native working memory; they reconstruct task-specific graphs from code each session.
- Agents need explicit semantics (contracts, effects, invariants) attached to code to reduce ambiguity and search cost.

This is why Alien Stack uses LLVM IR as canonical behavior while keeping a text representation (`.ll`) as the agent-facing interface — not a proprietary binary format, not AST-as-source, but semantically rich text with machine-checkable metadata. It fits how agents actually work today.

---

## 2. Design Principles

Alien Stack is defined by six rules:

1. **One canonical representation.**
   LLVM IR is the only authoritative source representation for executable behavior.

2. **Proof-carrying linkage.**
   A function may be linked only when its contract and proof artifact pass machine verification.

3. **Declared effects, not inferred intent.**
   Every function declares external effects (syscalls, global writes, I/O classes, allocator use).

4. **Deterministic artifacts.**
   Build outputs, proof outputs, and benchmark reports are reproducible from commit + toolchain digest.

5. **Typed persistent state with invariants.**
   Persistent layouts are typed binary structures with invariants validated on mutation and recovery.

6. **Small explicit trust base.**
   The trusted computing base (TCB) is versioned and auditable.

---

## 3. Structural Graph Layer

Before agents can work with formal proofs, they need something immediately useful: the ability to navigate code structure without re-deriving it from syntax. The simplest solution is the one that requires no new tools, no sidecars, no databases: **structured doc comments inside the code files themselves**.

### 3.1 The Annotation Convention

Every function, global, and type gets a structured comment block using `@`-prefixed tags. The tags encode graph edges that agents traverse with grep:

```
; @fn           @build_response
; @called-by    @handle_client
; @calls        @strlen, @llvm.memcpy.p0i8.p0i8.i64
; @reads        @http_status, @http_content_type, @html_body
; @cfg          entry (single block, no branches)
; @pre          %buf is a valid pointer to >= 1024 bytes
; @post         return > 0, %buf contains valid HTTP/1.1 response
; @inv          all source strings are compile-time constants
; @proof        constant-propagation: total = sum(strlen(each constant)), QED
```

Globals get reverse edges:

```
; @global       html_body
; @read-by      @build_response
; @inv          length == 337, valid UTF-8 HTML
```

### 3.2 Tags as Graph Edges

Each tag is a directed edge in a property graph:

| Tag | Edge semantics | Direction |
|-----|----------------|-----------|
| `@calls` | function → functions it invokes | forward (caller → callee) |
| `@called-by` | function → functions that invoke it | backward (callee → caller) |
| `@reads` | function → globals it accesses | forward (consumer → data) |
| `@read-by` | global → functions that access it | backward (data → consumer) |
| `@uses-type` | function → struct types it uses | forward |
| `@used-by` | type → functions that use it | backward |
| `@cfg` | function → control flow summary | structural |
| `@pre` | function → entry precondition | contract |
| `@post` | function → exit postcondition | contract |
| `@inv` | any node → property that always holds | constraint |
| `@proof` | function → proof strategy | verification |

Forward and backward tags are **bidirectional by convention** — if `@build_response` has `@called-by @handle_client`, then `@handle_client` should have `@calls @build_response`. This redundancy is deliberate: an agent searching from either direction finds the edge.

### 3.3 Grep as Graph Traversal

An agent's existing tools — grep, read, search — become graph traversal operators:

**"What calls build_response?"**
```
grep "@calls.*build_response" *.ll
→ found in @handle_client's annotation block
```

**"What does main call?"**
```
grep -A20 "@fn.*@main" server.ll | grep "@calls"
→ @socket, @setsockopt, @htons, @bind, @listen, @accept, @handle_client, ...
```

**"What are all the invariants?"**
```
grep "@inv" *.ll
→ every correctness property in the system, with context
```

Five greps. Complete system understanding. No sidecar, no database, no tooling.

### 3.4 Why This Works

1. **No infrastructure.** No generator, no watcher, no build step. The annotations are in the source file. The agent reads the file it was going to read anyway.

2. **No drift.** When the agent modifies a function, it updates the annotations in the same edit. The graph and the code are the same file — they cannot go out of sync unless the agent makes them inconsistent.

3. **No new tools.** Grep is the query engine. Every agent already has it.

4. **Compiler-invisible.** LLVM IR comments are discarded by the assembler. The annotations have zero cost at build time and zero cost at runtime.

5. **Self-documenting.** A human reading the IR sees the same graph the agent sees.

### 3.5 Structural Invariants

- Every declared edge must reference a declared node id.
- `@calls` and `@called-by` must be logically consistent where both are present.
- Graph traversal is performed directly via grep against the source files. No parser or sidecar tool is required — the annotation convention is self-sufficient.

---

## 4. Core Units

### 4.1 Proof-Carrying Function (PCF)

The atomic unit of code in Alien Stack is the **Proof-Carrying Function**: an LLVM IR function bundled with its specification and a machine-checkable proof.

```llvm
; PCF: safe_add — adds two i32 values with overflow protection
;
; Specification (encoded as metadata):
;   pre:  %a in [INT32_MIN/2, INT32_MAX/2] AND %b in [INT32_MIN/2, INT32_MAX/2]
;   post: %result == %a + %b
;   proof: overflow impossible given precondition range
;
define i32 @safe_add(i32 %a, i32 %b) !pcf.pre !1 !pcf.post !2 !pcf.proof !3 {
entry:
  %result = add nsw i32 %a, %b
  ret i32 %result
}

!1 = !{"smt", "(and (>= a (- 1073741824)) (<= a 1073741823)
                     (>= b (- 1073741824)) (<= b 1073741823))"}
!2 = !{"smt", "(= result (+ a b))"}
!3 = !{"witness", "range-propagation", "qed"}
```

Every exported PCF must include:

| Metadata Key | Purpose |
|-------------|---------|
| `pcf.schema` | Schema identifier (`alienstack.pcf.v1`) |
| `pcf.pre` | Entry assumptions |
| `pcf.post` | Guarantees on normal and exceptional exits |
| `pcf.effects` | Exhaustive side-effect declaration |
| `pcf.bind` | Mapping from contract symbols to SSA values / memory regions |
| `pcf.proof` | Checkable witness or certificate reference |
| `pcf.toolchain` | Verifier/checker identity and digest |

A PCF without complete metadata is non-linkable.

#### 4.1.1 Binding Semantics (`pcf.bind`)

Bindings define how contract symbols map to program entities:

- `kind=arg`: direct function argument.
- `kind=ret`: normal return value.
- `kind=mem`: abstract memory region (`<base-object, [start,end), lifetime>`).
- `kind=state`: named persistent object/field.
- `kind=exc`: exceptional exit.

Rules: every free symbol in `pcf.pre/post` must resolve to exactly one binding. Memory bindings are region-based, not raw pointer identity. Aliasing must be explicit via alias group identifiers.

#### 4.1.2 Proof Artifact Format (`lspc.v1`)

Proof artifacts use a deterministic envelope:

- `format`: `lspc.v1`
- `goal_hash`: SHA-256 of canonicalized verification obligations
- `method`: `solver-discharge` or `proof-certificate`
- `checker` / `checker_hash`: checker identity and binary digest
- `assumptions`: explicit trusted assumptions
- `result`: `sat-proof` or `valid`
- `signature` (optional): detached signature over envelope

Proof validity requires matching `goal_hash`, schema version, and checker digest. Toolchain upgrades invalidate prior proofs unless compatibility is declared. Missing or stale proofs fail verification — no warning-only mode on release builds.

### 4.2 Invariant-Preserving Structure (IPS)

Data structures in Alien Stack are **Invariant-Preserving Structures**: typed binary layouts with embedded contracts. An IPS consists of:

| Component | Description |
|-----------|-------------|
| **Layout** | Binary layout schema (e.g. FlatBuffers). Zero-copy, zero-parse. |
| **Invariants** | SMT assertions over field values that must hold at all times. |
| **Accessors** | PCFs that read or mutate fields while preserving invariants. |
| **Recovery** | Validation rules: checksum/version/invariants checked before exposure. |

Mutation rule: every mutator must prove invariant preservation.

#### 4.2.1 IPS Durability Contract

Each IPS persistence domain defines: `layout_id`, `epoch` (monotonic counter), `root_ptr`, `journal_ptr`, `domain_checksum`. Committed mutation frames include prior/next epoch, affected regions, redo payload, and frame checksum.

Crash recovery replays only committed frames with valid checksums and contiguous epochs, stops at the first invalid frame, and re-checks all IPS invariants before exposing state.

### 4.3 Effect Surface

Effects are part of the contract surface, not comments. Canonical effect atoms:

- `sys.<name>` — direct syscalls
- `libc.<name>` — known libc wrappers
- `global.read:<symbol>` / `global.write:<symbol>`
- `io.net.<op>` / `io.fs.<op>` — capability atoms
- `nondet.clock`, `nondet.random`, `nondet.env`, `nondet.signal`
- `alloc.heap`, `alloc.mmap`, `thread.spawn`, `thread.sync`

Effect matching uses set inclusion: actual effects ≤ declared effects. Any `effect.unknown:*` atom is a release failure.

---

## 5. Architecture

### 5.1 Build and Verification Graph

The canonical pipeline is fail-closed:

1. **Normalize IR** — Parse modules, canonicalize symbols, freeze target triples and data layouts.
2. **Structural lint** — Verify graph comments against actual IR use-def and call graph.
3. **Contract extraction** — Materialize SMT obligations from `pcf.pre/post`, control-flow, and memory model.
4. **Proof check / discharge** — Validate proof witnesses or discharge obligations with configured solver profile.
5. **Link gate** — Link only modules whose exported PCFs pass verification and effect compatibility checks.
6. **Artifact seal** — Emit binaries plus manifest containing digests for IR, proofs, toolchain, and benchmark snapshot.

No step is advisory. Failure at any step blocks release artifacts.

### 5.2 Link-Gate Algorithm

For each resolved call edge `caller → callee`:

1. Check schema compatibility.
2. Check caller proof includes callee precondition obligations at callsite.
3. Check callee postconditions satisfy caller continuation assumptions.
4. Check actual callee effects are subset of effects allowed by caller context.
5. Check boundary ABI and binding compatibility.

Reject on any failed condition. Link output records all accepted edge proofs and rejected edge reasons.

### 5.3 Module Boundary Rules

At every boundary (native module, WASM module, RPC boundary):
- Caller must satisfy callee precondition.
- Callee guarantees postcondition and declared effects only.
- Boundary shims are generated from PCF metadata — they are not handwritten policy code.

### 5.4 Runtime Contract Modes

- **Verified mode**: proof-checked contracts trusted; only boundary assertions remain.
- **Audit mode**: selected contracts rechecked at runtime for sampling and drift detection.

### 5.5 Artifact Seal and TCB Capture

Every releasable build emits a manifest containing:
- Commit SHA, IR file digests, proof artifact digests
- Verifier/link report digests, benchmark snapshot digest
- Toolchain and checker records (`path`, `version`, `sha256`)

TCB scope: LLVM toolchain components, verifier/checker binaries, linker/sealing tool, runtime/kernel assumptions. Everything else is untrusted input.

### 5.6 Full Stack Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AGENT LAYER                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ IR Generator  │  │ IR Optimizer │  │ Re-optimization Engine    │ │
│  │ (spec → IR)   │  │ (pass mgr)   │  │ (improve + re-verify)     │ │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬──────────────┘ │
├─────────┼─────────────────┼────────────────────────┼────────────────┤
│         ▼                 ▼                        ▼                │
│              STRUCTURAL GRAPH LAYER (grep-navigable)                │
│  @calls / @called-by    @reads / @read-by    @cfg / @pre / @post   │
├─────────────────────────────────────────────────────────────────────┤
│                   VERIFICATION LAYER                                │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ SMT Solver   │  │ Proof Checker│  │ Effect Validator           │ │
│  │ (Z3 / CVC5)  │  │ (cert verify)│  │ (declared vs actual)       │ │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬──────────────┘ │
├─────────┼─────────────────┼────────────────────────┼────────────────┤
│         ▼                 ▼                        ▼                │
│                      IR LAYER                                       │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │              LLVM IR with PCF Metadata                          ││
│  │  • Function + spec + proof + effects + bindings                  ││
│  │  • IPS definitions (layout + invariants + accessors)             ││
│  │  • Link-time proof compatibility checks                          ││
│  └──────────────────────────┬──────────────────────────────────────┘│
├─────────────────────────────┼───────────────────────────────────────┤
│                             ▼                                       │
│                    EXECUTION LAYER                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ WASM Compiler│  │ WASM Runtime │  │ Contract Enforcer         │ │
│  │ (LLC → WASM) │  │ (wasmtime)   │  │ (pre/post/effect trap)    │ │
│  └──────────────┘  └──────────────┘  └───────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────┤
│                     DATA LAYER                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ IPS Store    │  │ Persistent   │  │ Memory-Mapped Backing     │ │
│  │ (typed blobs)│  │ MFO Heap     │  │ (mmap + msync)            │ │
│  └──────────────┘  └──────────────┘  └───────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.7 Tool Mapping

| Alien Stack Component | Existing Tool | Role |
|---------------------|---------------|------|
| Structural graph annotations | grep | Call graph, data flow, CFG traversal via @tags |
| IR representation | LLVM 14+ | Code storage, optimization, compilation |
| WASM compilation | LLVM wasm32 backend | IR → WASM bytecode |
| WASM execution | Wasmtime / Wasmer | Sandboxed runtime with WASI |
| SMT solving | Z3 / CVC5 | Proof discharge, invariant checking |
| Binary data formats | FlatBuffers | Zero-copy IPS layouts |
| Memory persistence | mmap + msync | MFO backing store |
| Proof format | Lean 4 / Coq export | Proof witness generation (future) |
| Fuzzing | libFuzzer / AFL | IR-level mutation testing |
| Module linking | lld (LLVM linker) | Proof-checked linking |

---

## 6. Conformance Levels

A system may claim only the highest level whose criteria are **fully met**:

| Level | Name | Criteria |
|-------|------|----------|
| **L0** | Structural | Graph comments parse and pass consistency checks. |
| **L1** | Contract Complete | Required functions have full PCF metadata (`pre/post/effects/bind/proof`). |
| **L2** | Verified | Solver/checker-backed verification is fail-closed in the build. |
| **L3** | Linked and Sealed | Link gate enforced, artifact manifest emitted with TCB capture. |
| **L4** | Durable | IPS recovery protocol implemented and validated under crash/fault injection. |

---

## 7. Demo: HTTP Server in LLVM IR

This repository demonstrates practical viability of the architecture:

- **`demo/webserver/server.ll`** — A native HTTP server authored entirely in LLVM IR with PCF metadata and structural graph annotations. Listens on TCP, accepts connections, responds with static HTML, enforces response invariants.
- **`demo/webserver/fractal.ll`** — A WASM fractal module authored in LLVM IR.
- **`demo/webserver/build.sh`** — Compilation pipeline: IR → native binary (+ WASM path).
- **`demo/webserver/verify.sh`** — Extracts and checks SMT invariants from metadata.

### 7.1 Invariants Demonstrated

| Invariant | Encoding | Enforcement |
|-----------|----------|-------------|
| Response body is never null | `!pcf.post` metadata | Static (provable from IR) |
| Status code ∈ {200} | `!pcf.post` metadata | Static (constant propagation) |
| Content-Length = len(body) | `!ips.inv` metadata | Runtime check in accessor |
| Socket fd ≥ 0 after bind | `!pcf.post` metadata | Runtime check (depends on OS) |

---

## 8. Scientific Evaluation Plan

This architecture is tested with falsifiable hypotheses:

- **H1: Structural indexing reduces agent search cost.**
  Metric: median files opened, prompt tokens consumed, and wall-clock latency for impact-analysis tasks.

- **H2: Effect declarations catch real regressions.**
  Metric: number of undeclared side effects caught pre-merge by effect lint.

- **H3: Link gate prevents contract regressions.**
  Metric: rejected edges due to pre/post/effect incompatibility vs. escaped regressions.

- **H4: Artifact sealing improves reproducibility.**
  Metric: successful deterministic rebuild rate from manifest-only replay.

- **H5: IPS recovery preserves invariants under fault injection.**
  Metric: invariant-preserving recovery success rate across crash points.

All hypothesis tests require machine-readable outputs committed or archived by CI.

---

## 9. Expected Outcomes

### 9.1 What This Stack Achieves

1. **Immediate structural navigation.** Agents grep `@calls`, `@reads`, `@inv` tags to traverse the code graph without reading every file. Zero tooling required — the graph is in the comments they were going to read anyway.

2. **Higher assurance through formal contracts.** Every exported function carries a machine-checkable specification. Linking is proof-checked. Formal verification raises the *floor* of correctness — it does not eliminate the need for testing. Unit tests and end-to-end tests should be authored in LLVM IR just as the production code is, and they validate that specifications match operational intent. The combination of proofs ("the code satisfies this contract") and tests ("this contract captures what we actually want") is strictly stronger than either alone.

3. **Zero-cost persistence.** Data structures in memory are identical to data structures on disk. No serialization, no ORM, no schema migration.

4. **Iterative re-optimization.** The agent acts as a non-deterministic JIT compiler: given the same specification, each run can produce improved IR — better instruction selection, tighter loop structures, more aggressive inlining. Re-optimization happens between deployments, not within a running process. Each candidate is re-verified against the original contracts before promotion, ensuring that optimization never regresses correctness.

5. **Sandboxed client execution.** WASM provides sandboxed, portable execution for client-side code. The fractal demo compiles LLVM IR to WASM and runs in the browser with no plugins or extensions. Server-side code compiles to native binaries for maximum throughput (as demonstrated by the plaintext benchmark). The architecture targets WASM for client isolation and native for server performance.

### 9.2 What Remains Human

This stack does not eliminate humans from software development. It eliminates humans from **implementation**. Humans retain:

- **Intent specification.** What should the system do?
- **Specification review.** Formal specifications are readable. Humans audit specifications, not code.
- **Acceptance criteria.** Humans define what "correct" means at the system level.

The role shifts from "programmer" to "specifier" — from writing instructions to defining outcomes.

---

## 10. Non-Goals

Alien Stack does not optimize for:
- Human-oriented syntax ergonomics as a primary concern.
- Framework-level abstraction layers with implicit side effects.
- Test-only correctness claims without contract/proof linkage.

---

## 11. Definition of Done

A system qualifies as Alien Stack-compliant when:
- Executable behavior is authored and versioned as LLVM IR modules.
- Exported behavior is expressed as complete PCFs.
- Verification is mandatory at link time.
- Effects are declared and mechanically validated.
- Persistent state uses IPS with validated recovery.
- Benchmark evidence is committed and reproducible.

---

## 12. Conclusion

The last stack humans build should be the one that makes human-built stacks unnecessary. But it won't be built in a single leap.

Agents today think in text — and that's fine. The mistake would be either ignoring that fact or treating it as permanent. Alien Stack starts where agents already are: reading text files, using grep, writing comments. Structural graph annotations require no tooling at all. Add `@calls`, `@called-by`, `@reads`, `@inv` comments to your code files. Agents grep them. That's it. The graph *is* the code.

From there, the architecture deepens: LLVM IR as canonical source, formal contracts on every export, proof-carrying linkage, effect validation, and ultimately self-modifying agents that optimize their own verified code at runtime.

Every stage is independently useful. You don't need to believe in the long-term vision to benefit from structured comments today.

The tools exist. Grep exists. LLVM IR is mature. SMT solvers are fast. WASM runtimes are production-grade. What remains is convention: agreeing on the tags, writing them consistently, and building the habit of treating comments as navigable structure rather than prose.

This is the last stack. It starts with a comment.

---

## References

1. Lattner, C., & Adve, V. (2004). LLVM: A Compilation Framework for Lifelong Program Analysis & Transformation. *CGO '04*.
2. De Moura, L., & Bjørner, N. (2008). Z3: An Efficient SMT Solver. *TACAS '08*.
3. Haas, A., et al. (2017). Bringing the Web up to Speed with WebAssembly. *PLDI '17*.
4. Necula, G. C. (1997). Proof-Carrying Code. *POPL '97*.
5. Google. (2014). FlatBuffers: Memory Efficient Serialization Library.
6. Bytecode Alliance. (2019). Wasmtime: A Fast and Secure Runtime for WebAssembly.
7. WASI. (2019). WebAssembly System Interface. *Bytecode Alliance*.
