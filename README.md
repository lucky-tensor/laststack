# Alien Stack 

![Plaintext](https://github.com/dot-matrix-labs/alien-stack/actions/workflows/demo-plaintext.yml/badge.svg)
![Webserver](https://github.com/dot-matrix-labs/alien-stack/actions/workflows/demo-webserver.yml/badge.svg)
![Storage](https://github.com/dot-matrix-labs/alien-stack/actions/workflows/demo-storage.yml/badge.svg)

## Why

We set out to find if, in Q1 2026, agents could write superhuman code. There is an opportunity for software to take a quantum leap: software which is proven to be correct, tree-shaken, and free to self-improve unconstrained by human patterns or the tools they depend on.

Currently, if an agent is asked to build a product, it will do what a junior developer would do: search the internet for prior art, choose libraries written by other humans, set up a development environment, and brute-force the features with write-run loops. Today, it’s widely reported that humans aren't even reviewing agent code that is being shipped to production.

It’s been speculated a super agent might just need binary, and write binary. We set out to find out what was possible; we asked the agent how it would do this, and it came up with **Alien Stack**. We asked it to write a scientific paper about it, then peer-review it by a mock committee, and finally make some demos. These demos are impressive for several reasons:
1. **Speed**: Created within 15 minutes, without internet searches or build tool struggles.
2. **Completeness**: Fully specified even for ambitious cases.
3. **Performance**: Surprisingly performant.
4. **Efficiency**: Thoroughly tree-shaken, with nothing extraneous.

Why this stack? It’s likely ephemeral because of the current state of agent tools. Agents want to read text files sequentially and discover them via disk searches (like `ripgrep`). We can’t yet feed it a specialized graph binary of a program’s semantics—but that day may soon arrive, and we’ll keep trying.

---

# The Stack

Alien Stack is an architecture for **agent-native software development**, described in detail in the [Alien Stack Whitepaper](docs/alien-stack-whitepaper.md). It's intentionally alien.

The paper imagines a future where humans stop writing text-based source code to accommodate human cognitive constraints, and instead direct agent coders to generate and optimize **Proof-Carrying Functions (PCFs)** directly in LLVM IR. Text becomes a view for documentation and structural navigation, while the machine-checkable contracts, invariants, and effects become the authoritative interface.

This repository contains proof-of-concept demonstrations that validate the foundational claims of the architecture. The demos are not production software — they exist to show that agents can construct complete, working systems directly in LLVM IR, and that doing so is faster, more self-contained, and surprisingly competitive with traditional high-level abstractions.

---

## Core Concepts

The Alien Stack is built on three pillars that redefine the relationship between agents and code:

### 1. Isomorphic Architecture
An **isomorphic codebase** means internal program representations (LLVM IR) are directly and verifiably preserved in the deployment artifact (WebAssembly). Unlike traditional web stacks where source code is mangled by transpilers and minifiers, Alien Stack maintains a 1-to-1 mapping that an AI agent can reason about without a complex, human-centric build pipeline.

### 2. AI-Native Development
The stack is designed to be **read and written by machines**, prioritizing machine-checkable contracts over human legibility:
- **Structural Graph**: Code is annotated with tags (`@module`, `@fn`, `@calls`) that allow agents to navigate the system via simple disk searches (like `grep`) rather than a full semantic understanding of a high-level language.
- **Proof-Carrying Functions (PCF)**: Agents don't just write logic; they write mathematical proofs of behavior (pre/post-conditions, effects). The **Link Gate** in the build pipeline then mechanically verifies these proofs.

### 3. Microkernel Client
The browser is treated as a **dumb hardware substrate** (device microkernel), not a high-level runtime:
- **Zero Frameworks**: No React, Vue, or Svelte. All application policy, layout, and even **dynamic CSS generation** occur inside the Wasm module.
- **Minimal Host Shim**: A tiny (<50 lines) JavaScript "device driver" provides raw syscalls (`dom_create`, `dom_listen`) to the Wasm module, with zero runtime scheduling or state management.

---

## Open Research

In the short term, Dot Matrix Labs uses this to improve our understanding of end-to-end Rust-based "supergreenfield" apps (Calypso RS). 

Long term, we're curious whether there is a graph representation of the code which can be ingested faster by agents, potentially obviating text files like LLVM IR. We are also exploring different ways of proving correctness beyond the current toolchain (Z3 SMT).

---

## Demos

This repository contains four primary demos verifying the architecture. You will need an LLVM toolchain (clang, llc, wasm-ld) and standard POSIX tools to build them.

### 1. E2E Webserver (`demo/webserver`)
A full LLVM IR HTTP server coupled with a WASM fractal-rendering client. Demonstrates the viability of building end-to-end web experiences without frameworks or high-level languages, relying purely on IR-level proofs and WASM sandbox safety. 
*(See: [spec.md](demo/webserver/spec.md))*

**To build and run:**
```bash
cd demo/webserver
./build.sh
./run.sh
# Open http://localhost:9090
```
![Fractal output](docs/fractal-demo.png)

### 2. TechEmpower Plaintext Benchmark (`demo/plaintext`)
A naive LLVM IR HTTP server specifically tailored to the TechEmpower FrameworkBenchmarks (TFB) `plaintext` test. It is benchmarked directly against a naive Rust Hyper `current-thread` server.
*(See: [spec.md](demo/plaintext/spec.md))*

**To build and run:**
```bash
cd demo/plaintext
./build.sh
./run.sh
```

### 3. IPS Durability and Recovery (`demo/storage`)
Demonstrates Invariant-Preserving Structures (IPS) living in a memory-mapped durable heap, with crash recovery and validation.
*(See: [spec.md](demo/storage/spec.md))*

**To build and run:**
```bash
cd demo/storage
./build.sh
./run.sh
```

### 4. Isomorphic UI Kit (`demo/ui-kit`)
A demonstration of a feature-rich, interactive UI component library that aims to **replace JS frameworks (React, etc.) and CSS frameworks (Bootstrap, Tailwind, etc.)**. All logic and styling reside in a Wasm module compiled from LLVM IR, achieving extreme tree-shaking for the browser runtime.
*(See: [README.md](demo/ui-kit/README.md))*

**To build and run:**
```bash
cd demo/ui-kit
./build.sh
# Serve with any static server or use bun scripts
```

---

## Plaintext Benchmark Results

Automated CI benchmark reflecting the TFB plaintext profile (`wrk`, shared GitHub Actions runner, 4 threads, 15s per level). The LLVM IR server outperforms the Rust Hyper baseline at low-to-medium concurrency. At saturation (c=16384), Hyper's async runtime holds better — expected, given the IR server uses a single-threaded accept loop.

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
