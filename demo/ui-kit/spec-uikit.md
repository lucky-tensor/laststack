# Isomorphic UI Kit Demo Specification

This document defines the requirements, constraints, architecture, and development workflow for the Isomorphic UI Kit demonstration component library in the Alien Stack repository.

## 1. Goal

Create a demonstration of a feature-rich, interactive UI component library that provides modern, premium aesthetics (similar to Tailwind CSS), but operates under the strict constraints of the Alien Stack client architecture (`docs/isomorphic-web-whitepaper.md`). The objective is to **completely replace high-level JS frameworks (React, etc.) and CSS frameworks (Bootstrap, Tailwind, etc.)** with agent-optimized, proof-carrying IR, resulting in extreme tree-shaking for the browser runtime.

## 2. Constraints (Non-Negotiable)

- **Isomorphic Compliance**: All UI policy, layout logic, interaction state, AND CSS style generation must reside exclusively in a WebAssembly module compiled from LLVM IR (`.ll` files). External static CSS files (like Tailwind CDNs) are prohibited.
- **Device Driver Shim**: The JavaScript execution environment is limited to the `alien-stack.client.abi.v1` specification. The logic is inlined in `public/index.html` (≤50 lines) and provides no runtime scheduling or state management.
- **No JS Frameworks**: React, Vue, Svelte, or any other JavaScript-based UI libraries are strictly prohibited.
- **Dynamic CSS Injection**: The IR logic must generate the raw CSS strings for its components and dynamically inject them into the DOM upon initialization.

## 3. Architecture Overview

1. **Syscall Abstraction (Wasm/IR)**: An IR layer that wraps the host browser ABI (e.g., `dom_create`, `dom_set_attr`, `dom_listen`).
2. **CSS Style Engine (Wasm/IR)**: IR strings containing CSS rules that define the look and feel of the components. These are injected into a `<style>` tag on boot. The engine composes styles dynamically — it is NOT a hardcoded string repository.
3. **Component Library (Wasm/IR)**: High-level IR functions that instantiate DOM structures and attach interaction logic.
   - **Button**: Handles hover, active, and focus states via event routing.
   - **Card**: Provides layout containers with padding, shadows, and rounded corners.
   - **Input**: Demonstrates two-way binding concepts by reacting to `input` events and managing focus states algebraically.
4. **Display Surface (Host)**: `public/index.html` loads the shim and provides the root mount point (`#root`).

### Style Engine Architecture

```
┌─────────────────────────────────────────────┐
│              styles.ll (Engine)             │
├─────────────────────────────────────────────┤
│  • Style composition functions              │
│  • Class name parsing                       │
│  • CSS rule generation                      │
│  • Dynamic style injection                  │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│            DOM + <style> tag                │
└─────────────────────────────────────────────┘
```

### Core IR Files

| File | Purpose |
|------|---------|
| `ir/core.ll` | Syscall wrappers for DOM operations |
| `ir/dom.ll` | DOM node creation and manipulation |
| `ir/memory.ll` | String/buffer management in linear memory |
| `ir/styles.ll` | CSS engine — composition, parsing, injection |
| `ir/components.ll` | Component definitions using the style engine |

## 4. Required Components & Aesthetics

The demo must showcase a premium design aesthetic without relying on external CSS frameworks. The Wasm module will generate classes for:

- **Color Palette**: Rich, modern colors (e.g., matching standard blue and slate palettes).
- **Typography**: Modern sans-serif fonts.
- **Micro-interactions**: Subtle hover and focus states defined dynamically by Wasm handling `mouseenter`/`mouseleave`.
- **Layout**: Flexbox and grid layouts.

## 5. Development Workflow

```
[1. Reference] → [2. Capture] → [3. Develop IR] → [4. Build] → [5. Compare]
      ↑                                                                    │
      └──────────────────── feedback loop ────────────────────────────────┘
```

### Key Principles

1. **No Tailwind in development HTML**: The development version must work WITHOUT any Tailwind CSS.
2. **Style engine, not hardcoded strings**: The LLVM IR must be a CSS generation engine that composes styles dynamically.
3. **Pixel-perfect matching**: Screenshots of reference (Tailwind) vs development (Wasm) must match exactly.
4. **Component-by-component**: Build and test each component iteratively.

### Step 1: Reference HTML (Baseline)

Create reference HTML files using actual Tailwind from CDN as gold standards.

Location: `demo/ui-kit/reference-*.html`

| File | Components |
|------|------------|
| `reference-layout.html` | Container, Flex, Grid, Spacing, Sizing |
| `reference-buttons.html` | Colors, Sizes, Variants, States, Shadows |
| `reference-forms.html` | Inputs, Textarea, Select, Checkbox, Radio, Forms |

### Step 2: Capture Reference

For each component, capture both a screenshot (PNG) and a DOM dump (HTML).

```bash
# Serve reference
bun run scripts/serve.ts --port 8081 --root reference

# Capture screenshot + DOM
bun run scripts/capture.ts index.html ci-capture
```

Output saved to `/tmp/alien-stack-captures/<name>/`.

### Step 3: Develop Style Engine (LLVM IR)

The style engine in `ir/styles.ll` must be a **CSS composition engine**, not a hardcoded string repository.

#### Anti-pattern (wrong)

```llvm
; WRONG: Hardcoded CSS string
@btn_css = private constant [50 x i8] c"bg-blue-600 hover:bg-blue-700 ..."
```

#### Correct approach

```llvm
; RIGHT: Compose styles from primitives
define void @apply_button_class(i32 %node) {
  ; Look up color "blue-600" from color table
  ; Look up state "hover" from pseudo-class map
  ; Compose into full CSS rule
  ; Inject into <style> tag
}
```

The engine should be able to generate any class dynamically, not just pre-defined ones.

### Step 4: Build & Serve

```bash
cd demo/ui-kit

# Build Wasm to public/app.wasm
./build.sh

# Serve development version (no Tailwind)
bun run scripts/serve.ts --port 8080
```

The development HTML (`public/index.html`) must NOT include Tailwind:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Alien Stack UI</title>
    <!-- NO Tailwind! -->
</head>
<body id="root">
    <script type="module">/* alien-stack.client.abi.v1 shim */</script>
</body>
</html>
```

### Step 5: Compare

```bash
# Capture development version
bun run scripts/capture.ts index.html dev-capture

# Compare screenshots and DOM
bun run scripts/compare.ts captures/reference/card captures/dev/card
```

| Metric | Threshold |
|--------|-----------|
| Pixel diff | 0 (must be identical) |
| DOM structure | Must match |
| Computed styles | Must match |

### Full Development Loop

```bash
# Full iteration
bun run scripts/dev.ts --component card

# This does:
# 1. Build Wasm
# 2. Serve dev on 8080
# 3. Capture both dev and reference
# 4. Compare and report
```

## 6. Tooling Reference

| Tool | Purpose |
|------|---------|
| `clang --target=wasm32` | Compile IR to Wasm |
| `scripts/serve.ts` | Static file server |
| `scripts/capture.ts` | Screenshot + DOM capture via Playwright |
| `scripts/compare.ts` | Pixel and DOM comparison |
| `scripts/test.ts` | Playwright assertions (CI gate) |
| `scripts/dev.ts` | Full development loop |

## 7. File Structure

```
demo/ui-kit/
├── ir/
│   ├── button.ll           # Button component IR
│   ├── styles.ll           # CSS engine (NOT hardcoded strings)
│   ├── dom.ll              # DOM operations
│   ├── memory.ll           # Memory management
│   └── components.ll       # Component definitions
├── public/
│   ├── index.html          # Development entry point (no Tailwind)
│   └── app.wasm            # Compiled Wasm output
├── scripts/
│   ├── serve.ts            # Static file server
│   ├── capture.ts          # Screenshot + DOM dump
│   ├── compare.ts          # Image/DOM comparison
│   ├── screenshot.ts       # Quick screenshot utility
│   ├── test.ts             # Playwright CI test
│   └── dev.ts              # Full development loop
├── build.sh                # Wasm build script
├── package.json            # Dev dependencies (Playwright)
└── spec-uikit.md           # This file
```

## 8. Verification Requirements

- **Build Artifacts**: The IR must compile to `public/app.wasm` using `clang --target=wasm32`.
- **Visual Fidelity**: The rendered output must be indistinguishable from a standard Tailwind-based implementation.
- **Event Handling**: All interactions must route through the shim → Wasm `on_event` → Wasm internal state → Wasm DOM mutation cycle.
- **CI Gate**: `bun run test` must pass, asserting the expected components are present and visible on load.
