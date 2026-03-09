# Isomorphic UI Kit Demo Specification

This document defines the requirements, constraints, and architecture for the Isomorphic UI Kit demonstration component library in the Alien Stack repository.

## 1. Goal

Create a demonstration of a feature-rich, interactive UI component library that provides modern, premium aesthetics (similar to Tailwind CSS), but operates under the strict constraints of the Alien Stack client architecture (`docs/isomorphic-web-whitepaper.md`). The objective is to **completely replace high-level JS frameworks (React, etc.) and CSS frameworks (Bootstrap, Tailwind, etc.)** with agent-optimized, proof-carrying IR, resulting in extreme tree-shaking for the browser runtime.

## 2. Constraints (Non-Negotiable)

- **Isomorphic Compliance**: All UI policy, layout logic, interaction state, AND CSS style generation must reside exclusively in a WebAssembly module compiled from LLVM IR (`.ll` files). External static CSS files (like Tailwind CDNs) are prohibited.
- **Device Driver Shim**: The JavaScript execution environment is limited to the `alien-stack.client.abi.v1` specification. The logic is inlined in `index.html` (≤50 lines) and provides no runtime scheduling or state management.
- **No JS Frameworks**: React, Vue, Svelte, or any other JavaScript-based UI libraries are strictly prohibited.
- **Dynamic CSS Injection**: The IR logic must generate the raw CSS strings for its components and dynamically inject them into the DOM upon initialization.

## 3. Architecture Overview

1.  **Syscall Abstraction (Wasm/IR)**: An IR layer that wraps the host browser ABI (e.g., `dom_create`, `dom_set_attr`, `dom_listen`).
2.  **CSS Style Engine (Wasm/IR)**: IR strings containing CSS rules that define the look and feel of the components. These are injected into a `<style>` tag on boot.
3.  **Component Library (Wasm/IR)**: High-level IR functions that instantiate DOM structures and attach interaction logic.
    *   **Button**: Handles hover, active, and focus states via event routing.
    *   **Card**: Provides layout containers with padding, shadows, and rounded corners.
    *   **Input**: Demonstrates two-way binding concepts by reacting to `input` events and managing focus states algebraically.
4.  **Display Surface (Host)**: The `index.html` file that loads the shim and provides the root mount point (`#root`).

## 4. Required Components & Aesthetics

The demo must showcase a premium design aesthetic without relying on external CSS frameworks. The Wasm module will generate classes for:

*   **Color Palette**: Use rich, modern colors (e.g., matching standard blue and slate palettes).
*   **Typography**: Utilize modern sans-serif fonts.
*   **Micro-interactions**: Implement subtle hover and focus states defined dynamically by Wasm handling `mouseenter`/`mouseleave`.
*   **Layout**: Demonstrate flexbox and grid layouts.

## 5. Code Cleanup & Hygiene
- Removed 4 redundant Tailwind-based reference HTML files.
- Deleted legacy `core.o` object file and superseded `button-demo.html`.
- Unified the build process by removing `build-view.sh` and updating `shim.js` to target `app.wasm` (instead of the inconsistent `view.wasm`).
- The project now strictly follows the `spec-uikit.md` architecture.

## 6. Verification Requirements

*   **Build Artifacts**: The IR must compile to a single `app.wasm` file using `clang --target=wasm32`.
*   **Visual Fidelity**: The rendered output must be indistinguishable from a standard Tailwind-based HTML/JS implementation.
*   **Event Handling**: All interactions must route through the `shim.js` -> Wasm `on_event` -> Wasm internal state -> Wasm DOM mutation cycle.
