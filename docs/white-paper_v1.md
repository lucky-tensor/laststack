# The Alien Stack: A Post-Human Software Development Architecture

**Version 0.2 — March 2026**

---

## Abstract

Software development has been shaped by human cognitive constraints for seven decades. Languages use English keywords. Source code is stored as text files. Build systems orchestrate tools designed for human workflows. These choices made sense when humans were the primary authors and readers of code. As agent coders take on an increasing share of implementation work, the assumptions behind these choices deserve reexamination.

But reexamination does not mean wholesale replacement. Current agent coders — large language models — are themselves text-native. They read text, reason in text, and emit text. Asking them to abandon text for raw IR is like asking a carpenter to work without hands. The transition must be incremental.

This paper presents **Alien Stack** — a software development architecture designed for agent coders, built in stages. The near-term stage augments text-based source code with **structural sidecars**: queryable graph and tree representations (call graphs, ASTs, type maps, scope references) that give agents the structural reasoning they currently reconstruct from scratch on every turn. The long-term stage replaces text entirely with typed intermediate representations, formal verification, and persistent memory-native structures.

The result is an evolution path — from text-only, to text-with-structure, to structure-with-text-as-view, to pure IR — where every step is independently useful and every function eventually carries its own proof of correctness.

---

## 1. Motivation

### 1.1 The Cost of Human-Centric Design

Modern software stacks impose five categories of overhead that exist solely to accommodate human cognition:

1. **Parsing overhead.** Source code is text. Text must be lexed, parsed into ASTs, type-checked, lowered to IR, optimized, and emitted as machine code. Each transformation is a potential source of bugs and a barrier to formal reasoning. An agent coder gains nothing from the text representation — it is a detour.

2. **Semantic ambiguity.** Human languages are ambiguous by design. Programming languages inherit this: operator overloading, implicit conversions, dynamic dispatch, macro expansion. Each feature adds expressiveness for humans at the cost of formal tractability. An agent reasons more effectively over a representation with explicit semantics.

3. **File-system coupling.** Code stored as text files inherits the file system's limitations: no type safety, no referential integrity, no transactional updates. Renaming a function requires a text search across files. An agent coder needs a representation where structural references are first-class.

4. **Testing as simulation.** Humans write tests because they cannot formally verify their code. Tests check a finite number of execution paths. Formal verification checks all of them. An agent coder that can generate and check proofs has no need for example-based testing as the primary correctness mechanism.

5. **Library indirection.** Human developers use libraries to avoid re-implementing solved problems. But libraries introduce dependency graphs, version conflicts, API surface area, and trust boundaries. An agent coder can inline verified implementations directly, eliminating the library abstraction entirely.

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

### 1.3 Design Goals

Alien Stack is designed around six principles:

- **Incrementally adoptable.** Each layer of the stack provides value independently. An agent using structural sidecars today benefits immediately, without waiting for formal verification or IR-native tooling.

- **IR-native (long-term).** The eventual canonical representation of code is LLVM IR with typed metadata — not text, not ASTs, not bytecode. IR is the lowest representation that preserves optimization-relevant semantics.

- **Structure-in-place (near-term).** Code files carry their own structural graph as inline annotations — call edges, data flow, control flow, contracts — queryable with grep. No sidecars, no databases, no external tooling.

- **Proof-carrying.** Every function is accompanied by a machine-checkable proof of its specification. Functions without proofs cannot be linked.

- **Invariant-preserving.** Data structures carry their invariants as runtime-enforceable contracts. Mutation operations that would violate invariants are statically rejected or dynamically trapped.

- **Memory-first.** Persistent state is stored in typed, self-describing binary formats — not text files. Serialization and deserialization are identity operations on the in-memory representation.

---

## 2. Idealized Abstractions

### 2.1 The Proof-Carrying Function (PCF)

The atomic unit of code in Alien Stack is the **Proof-Carrying Function**: an LLVM IR function bundled with:

- **A specification** (preconditions, postconditions, frame conditions) encoded as SMT-LIB assertions in function metadata.
- **A proof witness** (a certificate that the function body satisfies the specification) encoded as a verifiable artifact.
- **An invariant set** (properties that hold at every point in the function's execution) encoded as LLVM metadata on basic blocks.

```
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

!1 = !{!"smt", !"(and (>= a (- 1073741824)) (<= a 1073741823)
                       (>= b (- 1073741824)) (<= b 1073741823))"}
!2 = !{!"smt", !"(= result (+ a b))"}
!3 = !{!"witness", !"range-propagation", !"qed"}
```

The proof witness is not a textual label — in a production system it would be a serialized proof tree verifiable by an embedded SMT checker. The metadata shown here is the interface format.

### 2.2 Invariant-Preserving Structures (IPS)

Data structures in Alien Stack are **Invariant-Preserving Structures**: typed binary layouts with embedded contracts.

An IPS consists of:

| Component | Description |
|-----------|-------------|
| **Layout** | A Cap'n Proto or FlatBuffers schema defining the binary layout. Zero-copy, zero-parse. |
| **Invariants** | SMT assertions over field values that must hold at all times. |
| **Accessors** | PCFs that read or mutate fields while preserving invariants. |
| **Serialization** | Identity — the in-memory layout *is* the persistent format. |

Example: an HTTP response structure.

```
; IPS: HttpResponse
; Layout: [status: i16, content_length: i32, body_ptr: i8*, headers_ptr: i8*]
; Invariants:
;   status in {200, 301, 400, 404, 500}
;   content_length >= 0
;   body_ptr != null
;   content_length == strlen(body_ptr)

%HttpResponse = type { i16, i32, i8*, i8* }

; Accessor: get_status — reads status with invariant guarantee
define i16 @http_response_get_status(%HttpResponse* %self) !ips.inv !10 {
  %status_ptr = getelementptr %HttpResponse, %HttpResponse* %self, i32 0, i32 0
  %status = load i16, i16* %status_ptr
  ret i16 %status
}

!10 = !{!"invariant", !"(and (member status (list 200 301 400 404 500))
                              (>= content_length 0)
                              (not (= body_ptr null)))"}
```

### 2.3 Memory-First Objects (MFO)

An MFO is an IPS that lives in persistent memory. It has no serialization step — the binary layout in RAM is the layout on disk. This is achieved by:

1. Memory-mapping a file as the backing store.
2. Allocating the IPS directly in the mapped region.
3. Using `msync` for durability.

The agent coder never "saves" or "loads" data. Data is always live, always typed, always invariant-checked.

### 2.4 SSA/LLVM IR as the Native Language

LLVM IR in SSA form is the native language of Alien Stack. There is no "source language." Agents:

- **Generate** IR directly from specifications.
- **Optimize** IR using LLVM's pass infrastructure plus custom invariant-aware passes.
- **Verify** IR by extracting SMT queries from metadata and discharging them.
- **Link** IR modules after verifying proof compatibility at module boundaries.
- **Emit** WASM (or native code) from verified IR.

The key insight: LLVM IR is already the lingua franca of compilation. Alien Stack simply removes the layers above it that exist only for human convenience.

---

## 3. Near-Term Layer: Inline Graph Annotations

Before agents can work with IR and formal proofs, they need something immediately useful: the ability to navigate code structure without re-deriving it from syntax. The simplest solution is the one that requires no new tools, no sidecars, no databases: **structured doc comments inside the code files themselves**.

### 3.1 Why Not Sidecars?

An earlier version of this paper proposed a `.code-graph/` sidecar directory with JSON and DOT files alongside source. This approach has a fatal problem: **drift**. The sidecar is derived from source, so it must be regenerated on every change. If it isn't, the agent reads stale structure. If it is, you need a watcher, a generator, and a build step — infrastructure that must be maintained and that agents cannot inspect or modify.

The alternative is zero-infrastructure: put the graph *in the code*. LLVM IR comments (lines starting with `;`) are ignored by the compiler. They cost nothing at build time, nothing at runtime. But they are visible to any agent that can grep.

### 3.2 The Annotation Convention

Every function, global, and type gets a structured comment block using `@`-prefixed tags. The tags encode graph edges that agents traverse with grep:

```
; @function     @build_response
; @called-by    @handle_client
; @calls        @strlen, @llvm.memcpy.p0i8.p0i8.i64
; @reads        @http_status, @http_content_type, @html_body
; @cfg          entry (single block, no branches)
; @pre          %buf is a valid pointer to >= 1024 bytes
; @post         return > 0, %buf contains valid HTTP/1.1 response
; @invariant    all source strings are compile-time constants
; @proof        constant-propagation: total = sum(strlen(each constant)), QED
```

Globals get reverse edges:

```
; @global       html_body
; @read-by      @build_response
; @invariant    length == 337, valid UTF-8 HTML
```

Types get usage edges:

```
; @type         %struct.sockaddr_in
; @used-by      @main
; @invariant    sin_family == 2 (AF_INET)
```

### 3.3 Tags as Graph Edges

Each tag is a directed edge in a property graph. The full set:

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
| `@invariant` | any node → property that always holds | constraint |
| `@proof` | function → proof strategy | verification |

Forward and backward tags are **bidirectional by convention** — if `@build_response` has `@called-by @handle_client`, then `@handle_client` should have `@calls @build_response`. This redundancy is deliberate: an agent searching from either direction finds the edge.

### 3.4 Grep as Graph Traversal

An agent's existing tools — grep, read, search — become graph traversal operators:

**"What calls build_response?"** (follow backward edge)
```
grep "@calls.*build_response" *.ll
→ ; @calls  @read, @build_response, @check_invariants, @write, @printf, @close
→ (found in @handle_client's annotation block)
```

**"What does main call?"** (follow forward edge)
```
grep -A20 "@function.*@main" server.ll | grep "@calls"
→ ; @calls  @socket, @setsockopt, @htons, @bind, @listen, @accept,
→           @handle_client, @printf, @close
```

**"What are all the invariants?"** (collect all constraint edges)
```
grep "@invariant" *.ll
→ 10 results: every correctness property in the system, with context
```

**"What data does build_response touch?"** (follow data-flow edges)
```
grep "@read-by.*build_response" *.ll
→ 7 globals: http_status, http_content_type, html_body, ...
```

**"What's the control flow of main?"** (read structural edge)
```
grep "@cfg" server.ll
→ ; @cfg  entry → socket_fail | socket_ok
→         socket_ok → bind_fail | bind_success
→         bind_success → listen_fail | listen_success
→         listen_success → accept_loop → client_accepted → accept_loop
```

Five greps. Complete system understanding. No sidecar, no database, no tooling.

### 3.5 Why This Works

1. **No infrastructure.** No generator, no watcher, no build step. The annotations are in the source file. The agent reads the file it was going to read anyway.

2. **No drift.** When the agent modifies a function, it updates the annotations in the same edit. The graph and the code are the same file — they cannot go out of sync unless the agent makes them inconsistent (which is the same class of error as writing incorrect code).

3. **No new tools.** Grep is the query engine. Every agent already has it. No JSON parser, no DOT reader, no SQLite driver.

4. **Compiler-invisible.** LLVM IR comments are discarded by the assembler. The annotations have zero cost at build time and zero cost at runtime. They survive in the `.ll` source but don't pollute the `.bc` bitcode.

5. **Self-documenting.** A human reading the IR sees the same graph the agent sees. The module header includes a legend explaining every tag.

### 3.6 Limitations

- **Manual maintenance.** Annotations must be kept consistent with the code. An agent that adds a call but forgets to update `@calls` creates a lie. Mitigation: a lint pass (trivially writable) that cross-checks `call` instructions against `@calls` annotations.

- **Single-file scope.** In a multi-file project, `@called-by @some_function` doesn't say which file `@some_function` lives in. Mitigation: use `@called-by file.ll:@some_function` for cross-file references, or accept that grep across `*.ll` handles this naturally.

- **Not machine-verified.** Unlike LLVM metadata (`!pcf.pre`, `!pcf.post`), comments are not checked by anything. They are documentation, not contracts. The metadata nodes carry the formal specifications; the comments carry the navigation graph. Both are needed.

### 3.7 Relationship to LLVM Metadata

The annotation convention and LLVM metadata serve different purposes:

| | Doc Comments (`; @tag`) | LLVM Metadata (`!pcf.*`) |
|---|---|---|
| **Purpose** | Navigation — help agents find things | Verification — formal specifications |
| **Audience** | Agents and humans reading `.ll` files | SMT solvers and proof checkers |
| **Survives compilation?** | No (comments stripped) | Yes (in bitcode) |
| **Machine-checked?** | No (lint only) | Yes (solver-discharged) |
| **Cost to add** | Zero (just comments) | Requires metadata node design |

Both encode graph structure. The doc comments encode the *navigation* graph (who calls whom, who reads what). The metadata encodes the *correctness* graph (what must be true, why it's true). A complete Alien Stack module has both.

---

## 4. Proposed Architecture

### 4.1 Evolution Path

The architecture is designed to be adopted incrementally:

```
Stage 0 (today):      text files only
                      agents re-derive structure every turn
                      ↓
Stage 1 (near-term):  text files with inline graph annotations
                      agents grep @tags to traverse call/data/control flow
                      ↓
Stage 2 (mid-term):   LLVM IR as source of truth + annotations + metadata
                      agents operate on IR directly, grep for navigation
                      ↓
Stage 3 (long-term):  full Alien Stack (IR + proofs + invariants + metadata)
                      formal verification replaces testing
```

Each stage is independently valuable. Stage 1 can be implemented today with existing tools. Stages 2-3 require the infrastructure described below.

### 4.2 Full Stack Layer Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AGENT LAYER                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ IR Generator  │  │ IR Optimizer │  │ Self-Modification Engine  │ │
│  │ (spec → IR)   │  │ (pass mgr)   │  │ (mutation + re-verify)    │ │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬──────────────┘ │
│         │                 │                        │                │
├─────────┼─────────────────┼────────────────────────┼────────────────┤
│         ▼                 ▼                        ▼                │
│              INLINE GRAPH ANNOTATIONS (Stage 1)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ @calls       │  │ @reads       │  │ @cfg                      │ │
│  │ @called-by   │  │ @read-by     │  │ @pre / @post              │ │
│  │ (call graph) │  │ (data flow)  │  │ @invariant / @proof       │ │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬──────────────┘ │
│         │                 │                        │                │
├─────────┼─────────────────┼────────────────────────┼────────────────┤
│         ▼                 ▼                        ▼                │
│                   VERIFICATION LAYER (Stage 3)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ SMT Solver   │  │ Proof Checker│  │ Invariant Monitor         │ │
│  │ (Z3 / CVC5)  │  │ (cert verify)│  │ (runtime assertions)      │ │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬──────────────┘ │
│         │                 │                        │                │
├─────────┼─────────────────┼────────────────────────┼────────────────┤
│         ▼                 ▼                        ▼                │
│                      IR LAYER (Stage 2)                             │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │              LLVM IR with Invariant Metadata                    ││
│  │  • PCF modules (function + spec + proof)                        ││
│  │  • IPS definitions (layout + invariants + accessors)            ││
│  │  • Link-time proof compatibility checks                         ││
│  └──────────────────────────┬──────────────────────────────────────┘│
│                             │                                       │
├─────────────────────────────┼───────────────────────────────────────┤
│                             ▼                                       │
│                    EXECUTION LAYER                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ WASM Compiler│  │ WASM Runtime │  │ Contract Enforcer         │ │
│  │ (LLC → WASM) │  │ (wasmtime)   │  │ (pre/post/invariant trap) │ │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬──────────────┘ │
│         │                 │                        │                │
├─────────┼─────────────────┼────────────────────────┼────────────────┤
│         ▼                 ▼                        ▼                │
│                     DATA LAYER                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ Persistent   │  │ IPS Store    │  │ Memory-Mapped Backing     │ │
│  │ MFO Heap     │  │ (typed blobs)│  │ (mmap + msync)            │ │
│  └──────────────┘  └──────────────┘  └───────────────────────────┘ │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                     TEST / FUZZ LAYER                               │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
│  │ Invariant    │  │ Path Coverage│  │ Mutation Fuzzer            │ │
│  │ Exhaustion   │  │ Analyzer     │  │ (IR-level mutations)       │ │
│  └──────────────┘  └──────────────┘  └───────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.3 Layer Descriptions

#### Inline Graph Annotation Layer (Stage 1 — implementable today)

The annotation layer embeds structural navigation directly in source files as structured doc comments (detailed in Section 3). Every function, global, and type gets `@`-prefixed tags encoding call graph edges (`@calls` / `@called-by`), data flow edges (`@reads` / `@read-by`), control flow summaries (`@cfg`), and contracts (`@pre` / `@post` / `@invariant`).

No external tooling is required. Agents traverse the graph using grep — the tool they already have. The annotations are invisible to the compiler (LLVM IR comments are discarded by the assembler) and co-located with the code they describe, eliminating sync drift.

The annotation layer is the **entry point** to Alien Stack. It can be applied to any codebase today, in any language that supports comments.

#### Agent Layer

The agent layer is where autonomous coders operate. It contains three subsystems:

**IR Generator.** Translates formal specifications (pre/post conditions, type signatures, behavioral descriptions) into LLVM IR. This replaces the human act of writing source code. The generator can use template instantiation, synthesis from examples, or direct construction.

**IR Optimizer.** Wraps LLVM's optimization pass manager with invariant-aware extensions. Standard passes (dead code elimination, inlining, loop unrolling) are augmented with metadata-preserving variants that maintain proof annotations through transformations.

**Self-Modification Engine.** Enables agents to modify their own IR at runtime. A module can request re-optimization, specialization for observed input distributions, or structural refactoring. All modifications are gated by re-verification — a modified function must re-prove its specification before replacing the original.

#### Verification Layer

**SMT Solver Integration.** Z3 or CVC5 runs as a service, accepting queries extracted from PCF metadata. Verification is not optional — it is a build step. Unverified functions cannot be linked.

**Proof Checker.** Validates proof witnesses attached to PCFs. A proof witness is a certificate that can be checked in linear time, even if generating it required exponential time. This separates proof generation (expensive, done once) from proof checking (cheap, done at every link).

**Invariant Monitor.** For properties that cannot be statically verified (e.g., properties depending on runtime input), the invariant monitor inserts lightweight runtime checks. These are not "assertions" in the traditional sense — they are contract enforcement with defined trap behavior.

#### IR Layer

The IR layer stores all code as LLVM IR bitcode with extended metadata. Key properties:

- **Typed.** Every value has a known type at every point.
- **SSA.** Every variable is assigned exactly once, enabling straightforward dataflow analysis.
- **Annotated.** Metadata nodes carry specifications, proofs, invariants, and provenance.
- **Linkable.** Modules can be composed with proof-compatibility checks at link boundaries.

#### Execution Layer

**WASM Compiler.** LLVM's WebAssembly backend compiles verified IR to WASM bytecode. WASM provides:
- Sandboxed execution (memory safety by default).
- Portable deployment (runs anywhere with a WASM runtime).
- Deterministic execution (no undefined behavior in the WASM spec).

**Contract Enforcer.** A WASM host function layer that intercepts calls and checks pre/postconditions at module boundaries. Internal function calls within a verified module skip enforcement (they are statically proven). Cross-module calls are dynamically checked.

#### Data Layer

**Persistent MFO Heap.** A memory-mapped region where all persistent data lives as typed, invariant-checked structures. No ORM, no serialization, no file I/O. Data is live.

**IPS Store.** A catalog of invariant-preserving structure definitions, enabling agents to discover and compose data types.

#### Test / Fuzz Layer

Even with formal verification, testing serves a purpose: it validates that specifications match intent. The test layer provides:

**Invariant Exhaustion.** Attempts to find inputs that satisfy preconditions but violate invariants — effectively fuzzing the specification itself.

**Path Coverage Analyzer.** Ensures that verification has considered all reachable paths in the IR control flow graph.

**Mutation Fuzzer.** Applies mutations to IR (flipping comparison operators, changing constants, removing instructions) and checks that the proof checker correctly rejects the mutated versions. This validates the proof infrastructure itself.

### 4.4 Tool Mapping

| Alien Stack Component | Existing Tool | Role |
|---------------------|---------------|------|
| Inline graph annotations | grep / any text search | Call graph, data flow, CFG traversal via @tags |
| Annotation linting | custom LLVM pass | Cross-check @calls against actual call instructions |
| IR representation | LLVM 14+ | Code storage, optimization, compilation |
| WASM compilation | LLVM wasm32 backend | IR → WASM bytecode |
| WASM execution | Wasmtime / Wasmer | Sandboxed runtime with WASI |
| SMT solving | Z3 / CVC5 | Proof discharge, invariant checking |
| Binary data formats | FlatBuffers / Cap'n Proto | Zero-copy IPS layouts |
| Memory persistence | mmap + msync | MFO backing store |
| Proof format | Lean 4 / Coq export | Proof witness generation (future) |
| Fuzzing | libFuzzer / AFL | IR-level mutation testing |
| Module linking | lld (LLVM linker) | Proof-checked linking |

---

## 5. Implementation Plan

### Phase 0: Inline Graph Annotations (Weeks 1–2)

**Objective:** Define the `@tag` annotation convention and apply it to LLVM IR modules. Build a lint pass to verify annotation consistency.

**Steps:**
1. Formalize the annotation tag set (`@calls`, `@called-by`, `@reads`, `@read-by`, `@uses-type`, `@used-by`, `@cfg`, `@pre`, `@post`, `@invariant`, `@proof`).
2. Write a convention document (the module header in each `.ll` file) that agents and humans can reference.
3. Annotate the demo webserver IR as a reference implementation.
4. Build a lint script that cross-checks `@calls` tags against actual `call` instructions in the IR, and `@reads` tags against actual `getelementptr` / `load` references to globals.
5. Define cross-file reference format: `@called-by module.ll:@function_name`.

**Tools:** grep (for traversal), a Python or shell script (for linting), LLVM IR text format.

**Pitfalls:**
- Annotations can drift from code if the agent forgets to update them. Mitigation: the lint script catches inconsistencies; agents can run it as a post-edit check.
- Convention must be simple enough that agents maintain it without explicit instruction. Mitigation: lead by example — every `.ll` file in the project is pre-annotated, so agents see the pattern and follow it.

**Milestone:** An agent can grep `@calls.*build_response` to find all callers, grep `@invariant` to list all correctness properties, and run the lint script to verify annotations match the actual IR — all without any tooling beyond grep and a shell script.

### Phase 1: IR Metadata Extensions (Weeks 3–6)

**Objective:** Extend LLVM IR with custom metadata for specifications and invariants.

**Steps:**
1. Define metadata schema for PCF annotations (`!pcf.pre`, `!pcf.post`, `!pcf.proof`).
2. Define metadata schema for IPS annotations (`!ips.layout`, `!ips.inv`).
3. Build an LLVM pass that validates metadata well-formedness.
4. Build an LLVM pass that extracts SMT queries from metadata.
5. Verify metadata survives standard optimization passes (or build metadata-preserving pass wrappers).

**Tools:** LLVM 14 C++ API, LLVM pass infrastructure.

**Pitfalls:**
- LLVM optimization passes may drop or invalidate custom metadata. Mitigation: register metadata kinds as "preserved" through pass declarations, or rebuild metadata post-optimization from a side table.
- SMT-LIB embedded in metadata is fragile. Mitigation: use a structured binary encoding rather than string-based SMT-LIB.

**Milestone:** An LLVM IR module with PCF metadata that survives `opt -O2` and can be extracted as valid SMT-LIB queries.

### Phase 2: Proof-Carrying Module Format (Weeks 7–10)

**Objective:** Define a module container that bundles IR + specifications + proof witnesses.

**Steps:**
1. Design a binary container format (extending LLVM bitcode sections).
2. Implement proof witness serialization (initially: Z3 proof logs).
3. Build a linker plugin that checks proof compatibility at module boundaries.
4. Build a proof-checking pass that validates witnesses against specifications.

**Tools:** LLVM bitcode format, Z3 C API, lld plugin API.

**Pitfalls:**
- Z3 proof logs are large and unstable across versions. Mitigation: use proof certificates (e.g., LFSC format) instead of raw logs.
- Link-time checking adds latency. Mitigation: cache verification results keyed on module hash.

**Milestone:** Two PCF modules linked together with proof-checked interfaces.

### Phase 3: WASM Runtime with Contract Enforcement (Weeks 11–14)

**Objective:** A WASM runtime that enforces pre/postconditions at module boundaries.

**Steps:**
1. Compile verified IR to WASM using `llc -march=wasm32`.
2. Build a WASM host that intercepts imported/exported function calls.
3. Implement contract enforcement as host functions (check pre before call, post after return).
4. Integrate WASI for system calls (file I/O, networking, clock).

**Tools:** Wasmtime (Rust), WASI SDK, LLVM WASM backend.

**Pitfalls:**
- WASM's linear memory model complicates pointer-based invariants. Mitigation: translate pointer invariants to offset invariants within WASM memory.
- WASI is still evolving. Mitigation: target WASI preview 1, which is stable.

**Milestone:** A WASM module executing with runtime contract checks on cross-module calls.

### Phase 4: Persistent Invariant-Aware Data Structures (Weeks 15–18)

**Objective:** Implement MFOs backed by memory-mapped files.

**Steps:**
1. Define IPS binary layouts using FlatBuffers schema compiler.
2. Build mmap-based allocator for IPS instances.
3. Implement invariant-checking accessors as PCFs.
4. Build a persistence manager (msync scheduling, crash recovery).

**Tools:** FlatBuffers, POSIX mmap, LLVM IR generation.

**Pitfalls:**
- Crash consistency is hard with raw mmap. Mitigation: use write-ahead logging or copy-on-write pages for transactional updates.
- Memory-mapped IPS instances cannot be moved (pointers become invalid). Mitigation: use offset-based references instead of raw pointers.

**Milestone:** An IPS instance persisted to disk, reloaded, and invariant-checked without serialization.

### Phase 5: Test and Fuzzing Engine (Weeks 19–22)

**Objective:** Build automated testing infrastructure for invariant coverage.

**Steps:**
1. Implement invariant exhaustion fuzzer (generates inputs targeting invariant boundaries).
2. Build path coverage analyzer for IR control flow graphs.
3. Implement IR mutation fuzzer for proof infrastructure validation.
4. Integrate with CI: every IR change triggers verification + fuzzing.

**Tools:** libFuzzer, LLVM coverage instrumentation, custom IR mutation engine.

**Pitfalls:**
- Fuzzing IR directly can produce invalid IR. Mitigation: use grammar-aware fuzzing that respects IR well-formedness rules.
- Path explosion in verification. Mitigation: bound analysis depth and use abstraction refinement.

**Milestone:** A fuzzing run that discovers a metadata bug in a PCF module and reports the invariant violation.

### Phase 6: Agent Protocols (Weeks 23–26)

**Objective:** Define how agents interact with the stack.

**Steps:**
1. Define the agent API: generate_ir, optimize_ir, verify_ir, link_modules, execute_wasm.
2. Build the self-modification protocol: request_mutation → re-verify → hot-swap.
3. Implement agent-to-agent communication for collaborative optimization.
4. Build an agent loop: observe execution → identify optimization opportunity → mutate IR → verify → deploy.

**Tools:** Custom protocol (protobuf or Cap'n Proto), LLVM C API, Wasmtime embedding API.

**Pitfalls:**
- Self-modification can introduce infinite loops (optimize → invalidate → re-optimize). Mitigation: monotonic improvement metric with convergence check.
- Hot-swapping WASM modules during execution risks state inconsistency. Mitigation: quiesce module, swap, resume with state migration.

**Milestone:** An agent that optimizes a running WASM module by modifying its IR and hot-swapping the compiled result.

---

## 6. Demo: "Hello World" WebServer

### 6.1 Overview

The demo implements a minimal HTTP server entirely in LLVM IR, compiled to WASM, with invariant metadata demonstrating the proof-carrying concept. The server:

1. Listens on a TCP socket (via WASI).
2. Accepts connections.
3. Reads HTTP requests.
4. Responds with a static HTML page.
5. Enforces invariants: response is never null, status code is always valid, content-length matches body.

### 6.2 Architecture

```
┌─────────────────────────────────┐
│         Agent Reasoning          │
│  "Generate webserver from spec"  │
└────────────┬────────────────────┘
             │ generates
             ▼
┌─────────────────────────────────┐
│       LLVM IR Module            │
│  • main() — entry point         │
│  • handle_request() — PCF       │
│  • build_response() — PCF       │
│  • HttpResponse IPS             │
│  Metadata: pre/post/invariants  │
└────────────┬────────────────────┘
             │ llc → wasm32
             ▼
┌─────────────────────────────────┐
│       WASM Module (.wasm)       │
│  Sandboxed, portable            │
│  Imports: WASI sock/fd ops      │
└────────────┬────────────────────┘
             │ wasmtime/host
             ▼
┌─────────────────────────────────┐
│       Runtime Execution         │
│  TCP :8080 → HTML response      │
│  Contract checks on boundaries  │
└─────────────────────────────────┘
```

### 6.3 Implementation

The demo is provided in the `demo/` directory with:

- `server.ll` — LLVM IR source with PCF metadata
- `build.sh` — Compilation pipeline: IR → WASM (+ native fallback)
- `verify.sh` — Extracts and checks SMT invariants
- `run.sh` — Executes the compiled server

Since WASI networking support is limited in most runtimes, the demo provides a **native compilation path** as the primary executable, demonstrating the same IR-level concepts (PCF metadata, IPS structures, invariant annotations) compiled to a native Linux binary via LLVM.

### 6.4 Invariants Demonstrated

| Invariant | Encoding | Enforcement |
|-----------|----------|-------------|
| Response body is never null | `!pcf.post` metadata | Static (provable from IR) |
| Status code ∈ {200} | `!pcf.post` metadata | Static (constant propagation) |
| Content-Length = len(body) | `!ips.inv` metadata | Runtime check in accessor |
| Socket fd ≥ 0 after bind | `!pcf.post` metadata | Runtime check (depends on OS) |

---

## 7. Expected Outcomes

### 7.1 What This Stack Achieves

1. **Immediate structural navigation (Stage 1).** Agents grep `@calls`, `@reads`, `@invariant` tags to traverse the code graph without reading every file. Zero tooling required — the graph is in the comments they were going to read anyway.

2. **Elimination of redundant parsing (Stage 2+).** As the stack matures, code moves from text to typed IR. The lexer-parser-typechecker pipeline is removed — not because text is bad, but because structure is better when agents no longer need text as a crutch.

3. **Formal correctness by construction (Stage 3).** Every function proves its specification. Linking is proof-checked. The concept of a "bug" shifts from "code doesn't match intent" to "specification doesn't match intent" — a strictly smaller problem surface.

4. **Zero-cost persistence.** Data structures in memory are identical to data structures on disk. There is no serialization, no ORM, no schema migration (schema evolution is handled by typed structural transformations on the IPS).

5. **Self-improvement.** Agents can observe their own execution, identify hot paths, and optimize them — modifying IR, re-verifying, and hot-swapping — without human intervention.

6. **Reproducible execution.** WASM provides deterministic execution. The same IR, compiled to WASM, produces identical behavior on any platform. Debugging is trivially reproducible.

### 7.2 What Remains Human

This stack does not eliminate humans from software development. It eliminates humans from **implementation**. Humans retain:

- **Intent specification.** What should the system do? Humans define goals, constraints, and values.
- **Specification review.** Formal specifications are readable (SMT-LIB, temporal logic). Humans audit specifications, not code.
- **Acceptance criteria.** Humans define what "correct" means at the system level.

The role shifts from "programmer" to "specifier" — from writing instructions to defining outcomes.

### 7.3 Open Problems

- **Annotation drift.** Inline graph annotations are maintained by the agent, not derived automatically. If the agent adds a call but forgets to update `@calls`, the graph becomes incorrect. Mitigation: lint scripts that cross-check annotations against actual IR instructions.
- **Specification completeness.** Formal specifications can be incomplete. A function may satisfy its spec while violating unstated expectations. Fuzzing specifications (invariant exhaustion) partially addresses this.
- **Proof scalability.** SMT solving is NP-hard in general. Practical systems require decomposition strategies and bounded verification. Not all properties are cost-effective to prove.
- **Legacy interop.** Real systems must interface with human-written code. The boundary requires translation layers (C ABI compatibility in WASM, FFI bridges for system libraries).
- **Agent trust.** An agent that modifies its own IR could, in principle, modify its own proof checker. The verification layer must be immutable and externally auditable.

---

## 8. Conclusion

The last stack humans build should be the one that makes human-built stacks unnecessary. But it won't be built in a single leap. Agents today think in text — and that's fine. The mistake would be either ignoring that fact or treating it as permanent.

Alien Stack is a blueprint for an incremental transition. Stage 1 — inline graph annotations — requires no tooling at all. Add `@calls`, `@called-by`, `@reads`, `@invariant` comments to your code files. Agents grep them. That's it. The graph is in the code. The code is the graph.

Stage 2 moves the source of truth from human-language source to LLVM IR, with annotations and metadata carrying the structure. Stage 3 adds formal verification, proof-carrying functions, and invariant-preserving data structures. Each stage is independently useful. You don't need to believe in the long-term vision to benefit from structured comments today.

The demo accompanying this paper — a webserver written as LLVM IR with inline graph annotations and proof metadata, compiled to a native binary — demonstrates both the near-term and long-term layers working together in the same file.

The tools exist today. Grep exists. LLVM IR is mature. SMT solvers are fast. WASM runtimes are production-grade. What remains is convention: agreeing on the tags, writing them consistently, and building the habit of treating comments as navigable structure rather than prose.

This is the last stack. It starts with a comment.

---

## References

1. Lattner, C., & Adve, V. (2004). LLVM: A Compilation Framework for Lifelong Program Analysis & Transformation. *CGO '04*.
2. De Moura, L., & Bjørner, N. (2008). Z3: An Efficient SMT Solver. *TACAS '08*.
3. Haas, A., et al. (2017). Bringing the Web up to Speed with WebAssembly. *PLDI '17*.
4. Necula, G. C. (1997). Proof-Carrying Code. *POPL '97*.
5. Google. (2014). FlatBuffers: Memory Efficient Serialization Library.
6. Sandstrom, K., et al. (2014). Cap'n Proto: Infinity Times Faster Than Protocol Buffers.
7. Bytecode Alliance. (2019). Wasmtime: A Fast and Secure Runtime for WebAssembly.
8. WASI. (2019). WebAssembly System Interface. *Bytecode Alliance*.
9. Knuth, D. E. (1984). Literate Programming. *The Computer Journal*, 27(2).
10. Parnas, D. L. (1972). On the Criteria To Be Used in Decomposing Systems into Modules. *CACM*, 15(12).
