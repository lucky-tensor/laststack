# LastStack Client Development Workflow

This document defines the development workflow for building a pure Wasm CSS engine that matches Tailwind CSS pixel-perfect - without using Tailwind.

## Overview

The goal is to build a **Tailwind-equivalent CSS engine in LLVM IR/WebAssembly**. The Wasm module generates CSS dynamically at runtime, not by hardcoding Tailwind class strings.

```
[1. Reference] → [2. Capture] → [3. Develop IR] → [4. Build] → [5. Compare]
      ↑                                                                    │
      └──────────────────── feedback loop ────────────────────────────────┘
```

## Key Principles

1. **No Tailwind in development HTML**: The development version must work WITHOUT any Tailwind CSS
2. **Style engine, not hardcoded strings**: The LLVM IR should be a CSS generation engine that composes styles dynamically
3. **Pixel-perfect matching**: Screenshots of reference (Tailwind) vs development (Wasm) must match exactly
4. **Component-by-component**: Build and test each Tailwind component iteratively

---

## Step 1: Reference HTML (Baseline)

Create reference HTML files using actual Tailwind from CDN. These are the "gold standards".

Location: `demo/ui-kit/reference-*.html`

| File | Components |
|------|------------|
| `reference-layout.html` | Container, Flex, Grid, Spacing, Sizing |
| `reference-buttons.html` | Colors, Sizes, Variants, States, Shadows |
| `reference-forms.html` | Inputs, Textarea, Select, Checkbox, Radio, Forms |

---

## Step 2: Capture Reference

For each component, capture both:

1. **Screenshot**: PNG of the rendered component
2. **DOM Dump**: HTML structure for reference

### Capture Script

```bash
# Serve reference
bun run scripts/serve.bun.js --port 8081 --root reference

# Capture screenshot + DOM
bun run scripts/capture.bun.ts http://localhost:8081 components/card
```

Output saved to:
- `demo/ui-kit/captures/reference/components/card.png`
- `demo/ui-kit/captures/reference/components/card.html`

---

## Step 3: Develop Style Engine (LLVM IR)

The style engine in `styles.ll` should be a **CSS composition engine**, NOT a hardcoded string repository.

### Architecture

```
┌─────────────────────────────────────────────┐
│              styles.ll (Engine)            │
├─────────────────────────────────────────────┤
│  • Style composition functions             │
│  • Class name parsing                      │
│  • CSS rule generation                     │
│  • Dynamic style injection                 │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│            DOM + <style> tag                │
└─────────────────────────────────────────────┘
```

### Style Engine Interface

```llvm
; Parse a Tailwind class string and generate corresponding CSS
; @fn parse_class
; @param class_ptr: i32 - pointer to class name string
; @param class_len: i32 - length of class name
; @post "appends CSS rule to internal style buffer"

; Inject all accumulated styles into DOM
; @fn inject_styles
; @post "creates <style> tag in document head with all CSS rules"

; Apply class to element
; @fn apply_class
; @param element_handle: i32
; @param class_ptr: i32
; @param class_len: i32
; @post "adds class attribute and injects CSS if needed"
```

### Example: Button Style Engine

Instead of hardcoding:
```llvm
; WRONG: Hardcoded CSS string
@btn_css = private constant [50 x i8] c"bg-blue-600 hover:bg-blue-700 ..."
```

The engine should:
```llvm
; RIGHT: Compose styles from primitives
define void @apply_button_class(i32 %node) {
  ; Look up color "blue-600" from color table
  ; Look up state "hover" from pseudo-class map
  ; Compose into full CSS rule
  ; Inject into <style> tag
}
```

### Core IR Files

| File | Purpose |
|------|---------|
| `core.ll` | Syscall wrappers for DOM operations |
| `dom.ll` | DOM node creation, manipulation |
| `memory.ll` | String/buffer management in linear memory |
| `styles.ll` | **CSS engine** - composition, parsing, injection |
| `components.ll` | Component definitions using style engine |

---

## Step 4: Build & Serve Development

```bash
# Build Wasm
cd demo/ui-kit
./build.sh

# Serve development version (no Tailwind)
bun run scripts/serve.bun.js --port 8080
```

The development HTML (`index.html`) must NOT include Tailwind:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>LastStack UI</title>
    <!-- NO Tailwind! -->
</head>
<body id="root">
    <script type="module" src="shim.js"></script>
</body>
</html>
```

---

## Step 5: Compare

Capture development version and compare with reference:

```bash
# Capture development
bun run scripts/capture.bun.ts http://localhost:8080 components/card

# Compare screenshots
bun run scripts/compare.bun.ts captures/reference/components/card.png captures/dev/components/card.png
```

### Comparison Metrics

| Metric | Threshold |
|--------|-----------|
| Pixel diff | 0 (must be identical) |
| DOM structure | Must match |
| Computed styles | Must match |

---

## Development Loop

```bash
# Full iteration
bun run scripts/dev.bun.js --component card

# This does:
# 1. Build Wasm
# 2. Serve dev on 8080
# 3. Serve reference on 8081  
# 4. Capture both
# 5. Compare and report
```

---

## Tooling Reference

| Tool | Purpose |
|------|---------|
| `clang --target=wasm32` | Compile IR to Wasm |
| `bun serve` | Static file server |
| `playwright` | Screenshot + DOM capture |
| `image-diff` | Pixel comparison |

---

## File Structure

```
demo/ui-kit/
├── ir/
│   ├── core.ll         # Syscall wrappers
│   ├── dom.ll          # DOM operations
│   ├── memory.ll       # Memory management
│   ├── styles.ll       # CSS engine (NOT hardcoded strings)
│   └── components.ll   # Component definitions
├── reference-layout.html   # Tailwind CDN - Layout/Grid (gold standard)
├── reference-buttons.html  # Tailwind CDN - Buttons (gold standard)
├── reference-forms.html    # Tailwind CDN - Forms (gold standard)
├── index.html              # Development (no Tailwind)
├── shim.js                 # Browser ABI shim
├── build.sh                # Build script
├── app.wasm                # Compiled output
├── captures/
│   ├── reference/          # Tailwind screenshots + DOM
│   │   ├── layout/
│   │   ├── buttons/
│   │   └── forms/
│   └── dev/                # Wasm screenshots + DOM
└── scripts/
    ├── serve.bun.js         # Server
    ├── capture.bun.ts       # Screenshot + DOM dump
    ├── compare.bun.ts       # Image comparison
    └── dev.bun.js          # Full loop
```
demo/ui-kit/
├── ir/
│   ├── core.ll         # Syscall wrappers
│   ├── dom.ll          # DOM operations
│   ├── memory.ll       # Memory management
│   ├── styles.ll       # CSS engine (NOT hardcoded strings)
│   └── components.ll   # Component definitions
├── reference.html      # Tailwind CDN baseline
├── index.html          # Development (no Tailwind)
├── shim.js             # Browser ABI shim
├── build.sh            # Build script
├── app.wasm            # Compiled output
├── captures/
│   ├── reference/      # Tailwind screenshots + DOM
│   └── dev/            # Wasm screenshots + DOM
└── scripts/
    ├── serve.bun.js     # Server
    ├── capture.bun.ts   # Screenshot + DOM dump
    ├── compare.bun.ts   # Image comparison
    └── dev.bun.js      # Full loop
```

---

## Anti-Patterns (What NOT to Do)

### ❌ Hardcoded CSS Strings

```llvm
; WRONG - This is just embedding Tailwind as strings
@bg_blue_600 = constant [12 x i8] c"background..."
define void @btn() { 
  call @set_attr(..., @bg_blue_600, 12)
}
```

### ✅ Style Engine Approach

```llvm
; RIGHT - Compose styles dynamically
define void @apply_color(i32 %node, i32 %color_id) {
  ; Look up color from color table
  ; Compose background-color rule
  ; Inject CSS if not already present
}
```

The engine should be able to generate ANY Tailwind class, not just pre-defined ones.
