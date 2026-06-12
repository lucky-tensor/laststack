# Alien Stack

![Plaintext](https://github.com/superfield-ai/alien-stack/actions/workflows/demo-plaintext.yml/badge.svg)
![Webserver](https://github.com/superfield-ai/alien-stack/actions/workflows/demo-webserver.yml/badge.svg)
![Storage](https://github.com/superfield-ai/alien-stack/actions/workflows/demo-storage.yml/badge.svg)
![UI Kit](https://github.com/superfield-ai/alien-stack/actions/workflows/ui-kit-test.yml/badge.svg)

Alien Stack is an architecture for **agent-native software development**, described in detail in the [Alien Stack Whitepaper](docs/alien-stack-whitepaper.md). It's intentionally alien.

The paper imagines a future where humans stop writing text-based source code to align with human cognitive constraints. Instead direct agent coders to generate artifacts which have semantic representations of programs. We explored here how the LLVM Intermediary Representation could today provide much of that for agents. Then we add a thin framework to provide guardrails for the agent and program: the graph structure, formal verification, and effects.

The stack doesn't propose an end state. It shows what is possible with the constraints of agent tools as of Q1 2026. For example the reliance on text files: agents want to read documents sequentially and discover them via file system searches (like `ripgrep`).

This repository contains proof-of-concept demonstrations that validate the foundational claims of the architecture. The demos are not production software — they exist to show that agents can construct complete, working systems directly in LLVM IR, and that doing so is faster, more self-contained, and surprisingly competitive with traditional high-level abstractions.

## Why

We set out to explore what software architecture looks like when the primary author is a coding agent rather than a human. The question is not whether agents can write code — they clearly can — but whether they would choose the same representations, abstractions, and build conventions that humans have settled on, and if not, what they would choose instead.

Currently, when an agent is asked to build a product, it follows the same patterns a human developer would: search for prior art, select libraries written by other humans, configure a build environment, and iterate with write-run loops. We wanted to know what an agent would propose if asked to reason from first principles about its own working environment.

## How
We asked the agent directly: given your actual constraints — sequential text access, grep-based search, limited context — how would you structure a codebase optimized for yourself rather than for humans? The result was **Alien Stack**. We then asked it to write a scientific paper formalizing the idea, conduct a mock peer review, and produce minimal demonstrations. The demos have a few notable properties:
1. **Speed**: Produced within 15 minutes, without internet searches or build tool configuration.
2. **Specificity**: The agent made concrete architectural choices rather than deferring to existing conventions.
3. **Performance**: Competitive with hand-written baselines at low-to-medium concurrency (see benchmark section).
4. **Minimalism**: No extraneous dependencies; each demo contains only what the architectural claim requires.


### Semantic Representation

We want a program representation that:
- Is **explicit and navigable** — agents can find what calls what, what reads what, without reconstructing the whole program
- Has **machine-checkable contracts** — specifications that can be automatically verified, not just human-readable docs
- Declares **effects explicitly** — what syscalls, memory operations, I/O a function performs, verifiable against actual behavior

An **Intermediate Representation (IR)** is a program representation that sits between source code and machine code — executable but not tied to any specific hardware. It's structured data (not a tree like an AST) that compilers work with directly. An IR has explicit control flow, typed operands, and a fixed instruction set, making it ideal for program analysis, optimization, and verification.

LLVM IR is a good starting point — it's low-level enough to have explicit semantics but high-level enough to remain readable, with an actual compiler, optimizer, and two supported targets (native + WASM). But it lacks:
- **Structural annotations** for agent navigation (grep-friendly call/data graphs)
- **Machine-checkable contracts** (pre/post conditions attached to functions)
- **Effect declarations** that can be mechanically validated

So we extend LLVM IR with these capabilities:

- **Structural Graph** — `@fn`, `@calls`, `@called-by`, `@reads` tags in IR comments let agents traverse the program structure via grep
- **PCF Metadata** — Named metadata nodes (`!pcf.pre`, `!pcf.post`, `!pcf.effects`, `!pcf.proof`, `!pcf.bind`) attach machine-checkable contracts to functions
- **Effect Atoms** — A vocabulary of effect declarations (`sys.read`, `libc.pwrite`, `alloc.heap`, etc.) validated against actual IR call targets

These extensions live in the IR itself — with no external DSLs. The IR remains valid LLVM IR; the metadata is simply ignored by standard toolchains unless the Alien Stack verification tools are invoked.

Together, these lead to better autonomous software: agents can navigate code more efficiently (structural graph), verify correctness without human oversight (formal verification), and catch unintended side effects (effect declarations).

---

## Core Concepts

Alien Stack is defined by six design principles:

### 1. One Canonical Representation
LLVM IR is the only authoritative source representation for executable behavior. No high-level language sits between the agent's intent and the deployed artifact.

### 2. Proof-Carrying Linkage
A function may be linked only when its contract and proof artifact pass machine verification. The build pipeline enforces this via a **Link Gate** that checks PCF metadata before linking.

### 3. Declared Effects, Not Inferred Intent
Every function declares its external effects (syscalls, global writes, I/O classes, allocator use). Effect declarations are mechanically validated against actual IR call targets — any undeclared effect fails the build.

### 4. Deterministic Artifacts
Build outputs, proof outputs, and benchmark reports are reproducible from commit + toolchain digest.

### 5. Typed Persistent State with Invariants
Persistent layouts are typed binary structures with invariants validated on mutation and recovery (IPS — Invariant-Preserving Structure).

### 6. Small Explicit Trust Base
The trusted computing base (TCB) is versioned and auditable.

---

### Core Units

**Proof-Carrying Function (PCF):** An LLVM IR function bundled with its specification — pre/post conditions, effect declarations, and a machine-checkable proof. Every exported PCF must include complete metadata (`!pcf.pre`, `!pcf.post`, `!pcf.effects`, `!pcf.proof`). Without this metadata, the function is not linkable.

**Invariant-Preserving Structure (IPS):** Typed binary layouts with embedded contracts. An IPS consists of a binary layout schema, SMT-asserted invariants, accessor PCFs that preserve invariants, and recovery validation rules checked on startup.

**Effect Surface:** Effects are part of the contract surface, not comments. Every function declares a set of effect atoms (e.g., `sys.read`, `libc.pwrite`, `alloc.heap`). Actual effects must be a subset of declared effects — under-declaration fails the build.

### Structural Graph

Code is annotated with tags (`@fn`, `@calls`, `@called-by`, `@reads`, `@pre`, `@post`, `@inv`) that allow agents to navigate the system via simple disk searches (`grep`) rather than needing full semantic understanding of a high-level language. These annotations live in IR comments and are discarded at compile time — zero runtime cost.

---

## Open Research

In the short term, Dot Matrix Labs uses this to improve our understanding of end-to-end Rust-based "supergreenfield" apps (Calypso RS).

Long term, we're curious whether there is a graph representation of the code which can be ingested faster by agents, potentially obviating text files like LLVM IR. We are also exploring different ways of proving correctness beyond the current toolchain (Z3 SMT).

---

## Demos

Each demo is scoped to prove one specific architectural claim. They are not production software — they exist to show that the core ideas are technically coherent and implementable at small scale.

### Verification coverage

| Demo | Claim being proved | Behavioral checks | Effect lint | Z3 solver discharge |
|------|--------------------|:-----------------:|:-----------:|:-------------------:|
| webserver | Agents can build a full web stack (server + WASM client) directly in LLVM IR | ✓ | — | — |
| plaintext | IR-authored servers are performance-competitive with hand-written Rust at low-to-medium concurrency | ✓ | — | — |
| **storage** | **PCF contracts and IPS invariants can be formally verified — Z3 discharges SMT-LIB proof obligations, effect lint enforces declared vs. actual syscall sets** | **✓** | **✓** | **✓** |
| ui-kit | All UI policy and styling can reside in a WASM module compiled from IR, with a <50-line JS shim | ✓ | — | — |

The storage demo is the verification anchor for the architecture. The other demos establish that the stack is buildable across the full execution surface (server, WASM client, durable storage, browser UI).

You will need an LLVM toolchain (clang, llc, wasm-ld) and standard POSIX tools to build them. Z3 is required for the storage demo's solver discharge step. The native demos target `x86_64` Linux (they use POSIX syscalls such as `pread`/`pwrite`/`fork`); build them on Linux or in CI. The ui-kit demo targets `wasm32` and runs in any modern browser.

---

### 1. E2E Webserver (`demo/webserver`)

**Claim:** Agents can build a complete, working web stack — native HTTP server plus browser-side WASM module — directly in LLVM IR, without frameworks or high-level languages.

**Isomorphic Architecture:** The server logic authored in LLVM IR is directly compiled to the native binary, while the client fractal renderer is compiled to WebAssembly with a 1-to-1 mapping. Unlike traditional stacks where source is mangled by transpilers and minifiers, Alien Stack maintains verifiable preservation of IR across the compile target.

A full LLVM IR HTTP server coupled with a WASM fractal-rendering client. The server prebuilds HTTP responses at startup; the fractal module compiles LLVM IR to WASM and renders in the browser with a minimal JS shim. PCF metadata is attached to all gated functions; `verify.sh` and `link-gate.sh` check metadata presence and structural consistency.
*(See: [spec.md](demo/webserver/spec.md))*

**To build and run:**
```bash
cd demo/webserver
./build.sh
./run.sh
# Open http://localhost:9090
```
![Fractal output](docs/fractal-demo.png)

---

### 2. TechEmpower Plaintext Benchmark (`demo/plaintext`)

**Claim:** An LLVM IR server authored by an agent, without hand-tuning, is performance-competitive with a naive Rust Hyper baseline at low-to-medium concurrency.

A minimal single-threaded HTTP server tailored to the TechEmpower FrameworkBenchmarks `plaintext` profile — no heap allocations, one shared response buffer. Benchmarked head-to-head against a Rust Hyper `current-thread` server (also an agent's first pass, no hand-tuning). PCF metadata is present; verification checks structural completeness.
*(See: [spec.md](demo/plaintext/spec.md))*

**To build and run:**
```bash
cd demo/plaintext
./build.sh
./run.sh
```

---

### 3. IPS Durability, Recovery, and Formal Verification (`demo/storage`)

**Claim:** PCF contracts are formally verifiable — Z3 can discharge SMT-LIB proof obligations derived from IR-level postconditions. Effect declarations can be mechanically validated against actual IR call targets. IPS invariants hold across crash and recovery.

This is the verification anchor of the repository. The build pipeline runs three independent gates:
1. **`ips-evidence.sh`** — seven behavioral checks including a negative-path test (corrupt state must fail recovery).
2. **`verify-pcf.sh`** — invokes Z3 on two SMT-LIB files (`checksum-z3.smt2`, `roundtrip-z3.smt2`); all `check-sat` results must be `unsat`.
3. **`effect-lint.sh`** — parses `ips.ll`, extracts actual external call targets per function, maps them to effect atoms, and fails closed if any observed effect is absent from the function's `!pcf.effects` declaration.

*(See: [spec.md](demo/storage/spec.md))*

**To build and run:**
```bash
cd demo/storage
./build.sh
./run.sh
```

---

### 4. Isomorphic UI Kit (`demo/ui-kit`)

**Claim:** All UI policy, interaction state, and CSS generation can reside in a WASM module compiled from LLVM IR. The browser-facing interface can be reduced to a <50-line JS device-driver shim.

**Microkernel Client:** The browser is treated as a minimal host substrate (device microkernel), not a high-level runtime. No React, Vue, or Svelte — all application policy, layout, and dynamic CSS generation occur inside the Wasm module. The JavaScript shim provides raw syscalls (`dom_create`, `dom_listen`) with zero runtime scheduling or state management.

Renders interactive components (button, card, input) with hover and focus states. The WASM module dynamically injects raw CSS strings into the DOM at initialization. No React, Vue, Svelte, Bootstrap, or Tailwind. The demo validates one interactive component; it is not a complete component library.
*(See: [spec.md](demo/ui-kit/spec.md))*

**To build and run:**
```bash
cd demo/ui-kit
./build.sh
# Serve with any static server or use bun scripts
```

---

## Plaintext Benchmark Results

These results support the plaintext demo's specific claim: an agent-authored LLVM IR server is performance-competitive with a naive Rust Hyper baseline at low-to-medium concurrency. The IR server loses at saturation (c=16384) — expected and disclosed, because it uses a single-threaded accept loop. Hyper's async runtime is built for that regime.

Automated CI benchmark reflecting the TFB plaintext profile (`wrk`, shared GitHub Actions runner, 4 threads, 15s per level).

*(Both implementations represent an agent's first pass. No hand-tuning was applied to either.)*

### LLVM IR Baseline (`demo/plaintext/plaintext.ll`)
| Concurrency | Requests/sec | Latency |
| --- | --- | --- |
| 256 | 33,483.60 | 6.97ms |
| 1024 | 33,304.29 | 29.84ms |
| 4096 | 31,637.10 | 127.43ms |
| 16384 | 2,771.58 | 918.51ms |

### Rust Hyper Baseline (`demo/plaintext/hyper`)
| Concurrency | Requests/sec | Latency |
| --- | --- | --- |
| 256 | 23,393.95 | 10.67ms |
| 1024 | 23,130.47 | 43.82ms |
| 4096 | 21,549.12 | 187.09ms |
| 16384 | 3,739.76 | 977.52ms |

---

## Verification and Automation

Alien Stack enforces its contracts via **Verification and Link Gates**. In the demos (e.g., `demo/plaintext/build.sh`), compilation will **fail closed** if the required PCF metadata (`!pcf.pre`, `!pcf.effects`, etc.) is missing, invalid, or mismatches the code. The depth of the gates varies by demo: the storage demo additionally discharges SMT-LIB proof obligations with Z3 and runs a structural effect lint; the other demos currently enforce structural completeness of the metadata (conformance level L1 in the whitepaper's terms).

CI jobs run the verification gates on every push and pull request, and nightly benchmark jobs record latency snapshots as artifacts.

---

## Further Reading

- [Alien Stack Whitepaper](docs/alien-stack-whitepaper.md) (The core architecture)
- [Isomorphic Web Whitepaper](docs/isomorphic-web-whitepaper.md) (The client-side architecture — validated by the `demo/ui-kit` demo)
