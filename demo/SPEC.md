# LastStack Demo: Fractal WASM Demo

## Overview

A LastStack demonstration featuring a minimal HTTP server that serves:
1. A static HTML page
2. A WebAssembly binary containing a fractal generation algorithm
3. The client renders a generative fractal animation in the browser using repeated WASM calculations

This demo showcases:
- **LastStack server** - HTTP server written in LLVM IR with PCF metadata
- **WASM with proofs** - Fractal algorithm in WebAssembly with correctness guarantees
- **Time-bounded generative animation** - 10 Hz frame cadence for 60 seconds (600 frames)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Client (Browser)                      │
│  ┌─────────────┐    ┌──────────────────────────────────┐   │
│  │  HTML/CSS   │───▶│     WASM Fractal Renderer        │   │
│  │  (index)    │    │     (fractal.wasm)               │   │
│  └─────────────┘    └──────────────────────────────────┘   │
│         │                                               │   │
│         │     Renders 10 Hz fractal animation           │   │
│         │         (60s, then auto-stop)                │   │
└─────────│───────────────────────────────────────────────┘───│────────────
          │                                                     │
          │ Fetches                                           │
          ▼                                                     │
┌─────────────────────────────────────────────────────────────┐
│                    LastStack Server                         │
│                  (LLVM IR + PCF metadata)                   │
│                                                              │
│  Endpoints:                                                 │
│    GET /          → index.html                              │
│    GET /fractal.wasm → fractal.wasm binary                 │
│                                                              │
│  Port: 9090                                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. LastStack Server (LLVM IR)

**File:** `server.ll`

An HTTP server written in LLVM IR that serves static files. Extends the current demo with file serving capabilities.

**Endpoints:**
| Path | Response | Content-Type |
|------|----------|---------------|
| `/` | index.html | text/html |
| `/fractal.wasm` | fractal.wasm | application/wasm |

**Metadata annotations:**
- `@pre` - socket bound, file descriptors valid
- `@post` - response sent, connection closed
- `@invariant` - no buffer overflow, valid Content-Length

### 2. Static HTML

**File:** `public/index.html`

Minimal HTML page that:
1. Loads the WASM module
2. Creates a canvas element for rendering
3. Executes a timed animation loop at 10 Hz
4. Calls the WASM fractal function every frame
5. Renders each generated frame to the canvas
6. Stops automatically after 60 seconds

**Features:**
- Full-viewport canvas
- 10 Hz deterministic frame cadence
- Fixed runtime budget: 60 seconds
- WASM initialization, frame diagnostics, and graceful stop

### 3. WebAssembly Fractal Module

**File:** `fractal.wasm` (source: `fractal.c` → `fractal.wat` → `fractal.wasm`)

A WebAssembly module implementing a fractal generation algorithm.

**Algorithm:** Mandelbrot set with frame-varying parameters

**WASM Interface:**
```wasm
;; Exports
(func $generate_fractal (export "generate_fractal")
    (param $width i32)
    (param $height i32)
    (param $max_iter i32)
    (result i32)          ;; pointer to pixel buffer
)

(func $get_buffer (export "get_buffer") (result i32))
(func $get_buffer_size (export "get_buffer_size") (result i32))
(func $free_buffer (export "free_buffer") (param i32))
```

**Animation Contract:**
- Frame rate target: `10 Hz` (one frame every `100 ms`)
- Total runtime: `60 s`
- Total frame budget: `600` frames
- Each frame must invoke `generate_fractal(...)` and render the returned buffer
- Frame parameters are generative and deterministic from `frame_index` (for example `max_iter = 64 + (frame_index mod 192)`)

**Metadata annotations:**
- `@pre` - width, height > 0, max_iter > 0
- `@post` - returns valid pointer to buffer of size width*height*4
- `@invariant` - buffer contains valid RGBA pixels, all values in [0,255]
- `@proof` - algorithm correctly computes Mandelbrot set

---

## Implementation Plan

### Phase 1: Fractal WASM Module

**Step 1.1: Write fractal C implementation**
- File: `fractal.c`
- Implements Mandelbrot set calculation
- Outputs RGBA pixel buffer
- Use WASI for memory allocation

**Step 1.2: Compile to WASM**
```bash
# Compile C to WASM
clang --target=wasm32 -O3 -nostdlib -Wl,--export-all fractal.c -o fractal.wasm
```

**Step 1.3: Verify WASM**
- Use `wasm-validate` to ensure well-formed
- Use `wasm-objdump` to inspect exports

### Phase 2: HTML Client

**Step 2.1: Create index.html**
- File: `public/index.html`
- Canvas element with full viewport
- Fetch and instantiate WASM module
- Timed animation loop: 100ms interval (10 Hz)
- Auto-stop after 600 frames / 60 seconds

**Step 2.2: Add JavaScript rendering**
- For each frame `f` in `[0, 599]`, compute frame parameters from `f`
- Call `generate_fractal(width, height, frame_max_iter)`
- Read pixel buffer from WASM memory
- Draw to canvas using ImageData
- Ensure visible output (alpha channel normalization to 255 if needed)
- Display simple diagnostics: frame count, elapsed time

### Phase 3: LastStack Server Enhancement

**Step 3.1: Extend server.ll**
- Add file serving capability
- Implement GET / and GET /fractal.wasm
- Serve files from `./public/` directory

**Step 3.2: Add PCF metadata**
- Annotate file handling functions
- Include proof of buffer safety
- Document invariants

**Step 3.3: Update build pipeline**
- File: `build.sh`
- Add WASM compilation step
- Include WASM in server binary (embedded)

### Phase 4: Testing

**Step 4.1: Unit test fractal algorithm**
- Verify against known Mandelbrot values
- Check boundary conditions

**Step 4.2: Integration test**
- Start server
- Fetch index.html
- Fetch fractal.wasm
- Verify animation renders at ~10 Hz and stops at 60 s
- Verify exactly 600 frames are attempted (±1 due timer drift)

**Step 4.3: Metadata verification**
- Run `verify.sh` to confirm PCF metadata intact
- Verify metadata survives optimization

---

## File Structure

```
demo/
├── build.sh              # Build pipeline
├── run.sh                # Run server
├── verify.sh             # Verify PCF metadata
├── server.ll             # LastStack HTTP server (LLVM IR)
├── server.bc             # Bitcode
├── server-opt.bc         # Optimized bitcode
├── server.o              # Native object
├── laststack-server      # Final executable
├── public/
│   ├── index.html        # Client HTML
│   └── fractal.wasm      # WASM module (or embedded)
├── src/
│   ├── fractal.c         # Fractal source
│   └── fractal.wat       # WASM text format (optional)
└── SPEC.md               # This file
```

---

## Fractal Algorithm Specification

### Mandelbrot Set

For each pixel (x, y) in the image:
1. Map pixel coordinates to complex plane: `c = map(x, y)`
2. Initialize `z = 0`
3. Iterate: `z = z² + c` up to `max_iter` times
4. If `|z| < 2` for all iterations, pixel is in the set
5. Otherwise, color based on iteration count at escape

### Parameters
- Default viewport: x ∈ [-2.5, 1.0], y ∈ [-1.5, 1.5]
- Frame max_iter: deterministic function of frame index
- Default resolution: canvas size (responsive)
- Animation cadence: 100 ms/frame
- Animation duration: 60 s

### Output Format
- RGBA pixels (4 bytes per pixel)
- Buffer layout: `[R, G, B, A, R, G, B, A, ...]`
- Client normalizes alpha to 255 before draw if module output alpha is 0

---

## Acceptance Criteria

1. ✅ Server starts on port 9090
2. ✅ GET / returns index.html with 200 OK
3. ✅ GET /fractal.wasm returns WASM binary with correct Content-Type
4. ✅ HTML loads and instantiates WASM without errors
5. ✅ Browser renders animated fractal frames generated from WASM output
6. ✅ Animation runs for 60 seconds at 10 Hz target cadence
7. ✅ Animation stops automatically after frame budget is exhausted
8. ✅ Server binary includes PCF metadata
9. ✅ Metadata survives optimization passes
10. ✅ All components have appropriate @invariant / @pre / @post annotations

---

## Security Considerations

- Server must not serve files outside `./public/`
- WASM module runs in browser sandbox (no system access)
- Buffer sizes validated before allocation
- No user input passed to server (static files only)

---

## Future Enhancements

- Interactive pan/zoom of fractal
- Multiple fractal types (Julia, Burning Ship)
- Progressive fidelity ramp across frames
- WebGL rendering for performance
- Server-side rendering option
