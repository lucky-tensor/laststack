# Alien Stack 

![Plaintext](https://github.com/dot-matrix-labs/alien-stack/actions/workflows/demo-plaintext.yml/badge.svg)
![Webserver](https://github.com/dot-matrix-labs/alien-stack/actions/workflows/demo-webserver.yml/badge.svg)
![Storage](https://github.com/dot-matrix-labs/alien-stack/actions/workflows/demo-storage.yml/badge.svg)

## Why

We set out to explore what software architecture looks like when the primary author is a coding agent rather than a human. The question is not whether agents can write code — they clearly can — but whether they would choose the same representations, abstractions, and build conventions that humans have settled on, and if not, what they would choose instead.

Currently, when an agent is asked to build a product, it follows the same patterns a human developer would: search for prior art, select libraries written by other humans, configure a build environment, and iterate with write-run loops. We wanted to know what an agent would propose if asked to reason from first principles about its own working environment.

We asked the agent directly: given your actual constraints — sequential text access, grep-based search, limited context — how would you structure a codebase optimized for yourself rather than for humans? The result was **Alien Stack**. We then asked it to write a scientific paper formalizing the idea, conduct a mock peer review, and produce minimal demonstrations. The demos have a few notable properties:
1. **Speed**: Produced within 15 minutes, without internet searches or build tool configuration.
2. **Specificity**: The agent made concrete architectural choices rather than deferring to existing conventions.
3. **Performance**: Competitive with hand-written baselines at low-to-medium concurrency (see benchmark section).
4. **Minimalism**: No extraneous dependencies; each demo contains only what the architectural claim requires.

Why this stack? It’s likely ephemeral because of the current state of agent tools. Agents want to read text files sequentially and discover them via disk searches (like `ripgrep`). We can’t yet feed it a specialized graph binary of a program’s semantics—but that day may soon arrive, and we’ll keep trying.

---

# The Stack

Alien Stack is an architecture for **agent-native software development**, described in detail in the [Alien Stack Whitepaper](docs/alien-stack-whitepaper.md). It's intentionally alien.

The paper imagines a future where humans stop writing text-based source code to accommodate human cognitive constraints, and instead direct agent coders to generate and optimize **Proof-Carrying Functions (PCFs)** directly in LLVM IR. Text becomes a view for documentation and structural navigation, while the machine-checkable contracts, invariants, and effects become the authoritative interface.

This repository contains proof-of-concept demonstrations that validate the foundational claims of the architecture. The demos are not production software — they exist to show that agents can construct complete, working systems directly in LLVM IR, and that doing so is faster, more self-contained, and surprisingly competitive with traditional high-level abstractions.

---

## Core Concepts

The Alien Stack rests on three architectural choices:

### 1. Isomorphic Architecture
An **isomorphic codebase** means internal program representations (LLVM IR) are directly and verifiably preserved in the deployment artifact (WebAssembly). Unlike traditional web stacks where source code is mangled by transpilers and minifiers, Alien Stack maintains a 1-to-1 mapping that an AI agent can reason about without a complex, human-centric build pipeline.

### 2. AI-Native Development
The stack is designed to be **read and written by machines**, prioritizing machine-checkable contracts over human legibility:
- **Structural Graph**: Code is annotated with tags (`@module`, `@fn`, `@calls`) that allow agents to navigate the system via simple disk searches (like `grep`) rather than a full semantic understanding of a high-level language.
- **Proof-Carrying Functions (PCF)**: Functions carry machine-readable pre/post-conditions, effects, and proof witnesses alongside the logic. A **Link Gate** in the build pipeline checks these before linking.

### 3. Microkernel Client
The browser is treated as a **minimal host substrate** (device microkernel), not a high-level runtime:
- **Zero Frameworks**: No React, Vue, or Svelte. All application policy, layout, and even **dynamic CSS generation** occur inside the Wasm module.
- **Minimal Host Shim**: A tiny (<50 lines) JavaScript "device driver" provides raw syscalls (`dom_create`, `dom_listen`) to the Wasm module, with zero runtime scheduling or state management.

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

You will need an LLVM toolchain (clang, llc, wasm-ld) and standard POSIX tools to build them. Z3 is required for the storage demo's solver discharge step.

---

### 1. E2E Webserver (`demo/webserver`)

**Claim:** Agents can build a complete, working web stack — native HTTP server plus browser-side WASM module — directly in LLVM IR, without frameworks or high-level languages.

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

Alien Stack enforces its contracts via **Verification and Link Gates**. In the demos (e.g., `demo/plaintext/build.sh`), compilation will **fail closed** if the required PCF metadata (`!pcf.pre`, `!pcf.effects`, etc.) is missing, invalid, or mismatches the code.

CI jobs automatically track compliance and record latency snapshots (artifacts) to prevent regressions on steady-state and saturation loads.

---

## Further Reading

- [Alien Stack Whitepaper](docs/alien-stack-whitepaper.md) (The core architecture)
