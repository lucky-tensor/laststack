# Isomorphic UI Kit Demo

This demo showcases a premium, interactive UI component library built under the strict constraints of the Alien Stack architecture.

## Mission & Objective

The goal of this demo is to prove that agents can:
1.  **Replace JS Frameworks**: Eliminate React, Vue, Svelte, and their associated runtimes/complexities.
2.  **Replace CSS Frameworks**: Eliminate Bootstrap, Tailwind, and static CSS delivery.
3.  **Extreme Tree-shaking**: Deliver only the exact machine code (Wasm) required for the specific UI, minimizing the footprint on the browser runtime.

## Architecture

- **Wasm-Only Logic & Styling**: All UI policy, layout logic, and CSS generation reside exclusively in a WebAssembly module compiled from LLVM IR (`ir/*.ll`).
- **Inlined Shim**: A minimal JavaScript "device driver" (<50 lines) is inlined in `index.html`. It provides the host browser ABI (syscalls) for DOM manipulation and event routing.
- **No External CSS**: No Tailwind, Bootstrap, or static CSS files are used. The Wasm module dynamically injects raw CSS strings into the DOM.

## Project Structure

- `index.html`: The single entry point containing the inlined shim and the root mount point.
- `build.sh`: Compiles the LLVM IR in `ir/` into `app.wasm`.
- `ir/`: Contains the LLVM IR source files (e.g., `button.ll`).
- `scripts/`: Bun-based utility scripts for development, serving, and screenshot capture.
- `spec-uikit.md`: Detailed technical specification and constraints.

## Getting Started

### Prerequisites

- LLVM 18+ (`clang`, `wasm-ld`).
- [Bun](https://bun.sh/) (optional, for development scripts).

### Build

Compile the IR to Wasm:

```bash
./build.sh
```

### Serve

Serve the `index.html` locally:

```bash
bun run scripts/serve.bun.ts
```

Open `http://localhost:8080` in your browser.

## Continuous Integration

A GitHub Actions workflow (`.github/workflows/ui-kit-build.yml`) is configured to:
1. Build the Wasm module using Clang 18.
2. Install Bun and Playwright.
3. Capture a screenshot and DOM dump of the rendered UI as a CI artifact.
