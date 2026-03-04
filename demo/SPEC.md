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

## Benchmark Tool

**File:** `bench.ll`

Sequential HTTP benchmark written in LLVM IR.

**Usage:**
```
./laststack-bench [port [n_requests]]
```

**Output:** requests ok/total, elapsed ms, RPS, avg latency µs.

**Internals:**
- `@get_time_ns` — `clock_gettime(CLOCK_MONOTONIC)` → nanoseconds
- `@make_request` — TCP connect → `write` GET / → `read` response → `close`; always closes fd
- `@run_benchmark` — loop with loop-invariant proof in PCF metadata
- `@main` — parses `argv[1]` (port) and `argv[2]` (n_requests)

---

## Server Performance Optimizations

### Implemented

The following optimizations were applied to `server.ll` after initial benchmarking revealed per-request overhead:

| Optimization | Before | After |
|---|---|---|
| File I/O per request | `open` + `read` + `close` (3 syscalls) | 0 — prebuilt at startup |
| Header construction | `snprintf` + `memcpy` per request | 0 — prebuilt at startup |
| Request buffer | 1025-byte `memset` per request | 1 null-byte store |
| Invariant check | `printf` syscall per request | removed |
| Per-request logging | 2× `printf` per connection | removed |
| 404 length | `strlen` call | precomputed `i64 99` global |

**Mechanism — `@load_assets`:** called once from `@main` before the accept loop.
Reads `index.html` and `fractal.wasm` into `@file_load_buf`, calls `snprintf` once per asset
to build the full `HTTP/1.1 200 OK ...` header, then `memcpy`s the file body immediately
after. The resulting complete responses are stored in `@html_resp` / `@wasm_resp` globals.

**Per-request hot path after optimization:**
```
read(fd, req_buf, 1024)          ; 1 syscall
store i8 0 at req_buf[bytes_read] ; null-terminate
strstr(req_buf, "GET /fractal.wasm") ; in-process
write(fd, prebuilt_resp, resp_len) ; 1 syscall
close(fd)                         ; 1 syscall
```

**Measured result (loopback, same machine):**

| Server | Sequential RPS | Concurrent wall-clock (8 clients) |
|--------|---------------|-----------------------------------|
| LastStack (pre-optimization) | ~6,700 | — |
| LastStack (optimized) | ~13,000 | ~33,000 |
| Caddy v2 (Go, HTTP/1.1, no TLS) | ~3,400 | — |

LastStack outperforms Caddy in sequential no-keep-alive benchmarks because Caddy carries
Go runtime, middleware, file-stat checks, and content-negotiation overhead per request.
Under concurrent load with keep-alive Caddy scales much better (see below).

---

## Concurrency and Parallelization Strategy

Three layers, ordered by impact-to-complexity ratio. Each layer is independent and
additive — they compose to reach the full nginx-class architecture.

### Layer 1 — Pre-fork workers + SO_REUSEPORT ✅ implemented

Fork `nproc` workers before the accept loop. Each worker runs the existing optimized
hot path independently on the same listening socket. `SO_REUSEPORT` (Linux 3.9+) tells
the kernel to distribute incoming connections across all workers with no userspace lock.

```
main: socket → bind → setsockopt(SO_REUSEPORT) → listen → load_assets
      for i in 0..nproc: fork → child runs accept_loop
      parent: wait() loop
```

Each worker is a copy-on-write clone of the parent. The prebuilt response globals
(`@html_resp`, `@wasm_resp`) are read-only after `load_assets`, so they map to the same
physical pages across all workers — zero memory overhead per worker for response data.

**Expected gain:** near-linear with core count. 40-core machine → theoretical 40× single-core RPS.

### Layer 2 — HTTP keep-alive (planned)

Every request currently pays ~80 µs in TCP handshake overhead. Keep-alive reuses the
connection across multiple requests:

```
serve_html/wasm: write response
                 read next request on same fd
                 loop until Connection: close or bytes_read == 0
```

**Implementation in server.ll:** `handle_client` becomes a loop; parse `Connection:` header
to decide teardown. The prebuilt response globals already omit `Connection: close` once
this is toggled.

**Expected gain:** 3–5× per worker on top of Layer 1.

### Layer 3 — epoll event loop per worker (planned)

A blocking `accept → handle_client → accept` chain means one slow client stalls all
others queued behind it in the same worker. An epoll loop lets each worker handle
thousands of concurrent connections:

```
epoll_create → add listen_fd
loop: epoll_wait → for each ready fd: accept or read/write
```

**Implementation in server.ll:** requires `epoll_create1`, `epoll_ctl`, `epoll_wait`
declarations, non-blocking socket (`O_NONBLOCK`), and a per-connection state machine.

**Expected gain:** critical for slow clients or long-lived connections; less significant
for the fast loopback benchmark.

---

## State-of-the-Art Concurrency Strategies (reference)

Production servers (nginx, lighttpd, h2o) reach 100,000–1,000,000+ RPS on commodity
hardware by combining all three layers above. Additional micro-optimizations:

### 1. HTTP Keep-Alive (Connection Reuse)

Each TCP connection currently costs ~50–100 µs of kernel overhead (SYN/SYN-ACK/ACK +
FIN/FIN-ACK). HTTP/1.1 keep-alive reuses the TCP connection across multiple requests,
eliminating this cost entirely after the first request.

**Implementation in server.ll:**
- Remove `Connection: close` from the response header
- Loop `read → dispatch → write` on the same `client_fd` until `bytes_read == 0`
- Parse `Connection: close` request header to decide when to tear down

**Expected impact:** 3–5× RPS improvement for typical browser request patterns.

### 2. epoll / Event-Driven I/O

Single-threaded blocking `accept` + synchronous `read/write` means the server sits idle
while the kernel processes each syscall. An event loop using `epoll` allows one thread to
manage thousands of concurrent connections without blocking:

```
epoll_create → add listen_fd
loop:
  epoll_wait(events)
  for each ready fd:
    if fd == listen_fd: accept, add to epoll
    else: read request, write response
```

**Implementation in server.ll:** requires `epoll_create1`, `epoll_ctl`, `epoll_wait`
declarations and a non-blocking socket (`O_NONBLOCK`). The accept loop becomes an event
dispatch table.

**Expected impact:** 10–50× improvement under high concurrency vs. blocking I/O.

### 3. Multi-Worker / Pre-fork

Fork N workers (one per CPU core) before the accept loop. Each worker calls `accept` on
the shared socket independently. The kernel distributes connections across workers via
`SO_REUSEPORT` (Linux 3.9+), eliminating the thundering-herd problem.

```
for i in 0..NCPU:
    fork()
    if child: run_accept_loop()
parent: wait()
```

**Implementation in server.ll:** add `fork`, `sysconf(_SC_NPROCESSORS_ONLN)`, `waitpid`
declarations. Each child runs the existing accept loop independently. `SO_REUSEPORT`
requires adding a second `setsockopt` call.

**Expected impact:** near-linear scaling with core count (40-core machine → 40× single-core RPS).

### 4. `sendfile` / Zero-Copy Transfer

Currently: `read(file_fd)` copies bytes to user-space, then `write(client_fd)` copies them
back to kernel. `sendfile(2)` performs the transfer entirely in kernel space, eliminating
both copies and the intermediate buffer.

```llvm
declare i64 @sendfile(i32, i32, i64*, i64)
; sendfile(client_fd, file_fd, offset=0, count=file_size)
```

Since responses are prebuilt at startup (headers + body in one buffer), `sendfile` applies
to the entire `@html_resp` / `@wasm_resp` global via a memfd or by reopening the buffer as
a file descriptor.

**Expected impact:** ~20–30% improvement for large files; less significant for small assets
like this demo (5 KB HTML, 1 KB WASM).

### 5. `TCP_CORK` / `TCP_NODELAY`

`TCP_CORK` (Linux) holds outgoing data in the kernel buffer until the cork is removed or
the MSS is reached. This batches headers + body into a single TCP segment, reducing packet
count. `TCP_NODELAY` disables Nagle's algorithm for latency-sensitive use cases.

```llvm
; setsockopt(client_fd, IPPROTO_TCP=6, TCP_CORK=3, &one, 4)
; ... write header, write body ...
; setsockopt(client_fd, IPPROTO_TCP=6, TCP_CORK=3, &zero, 4)
```

**Implementation in server.ll:** two additional `setsockopt` calls around each response
write. Already using `Connection: close` which flushes the kernel buffer on `close(fd)`.

**Expected impact:** minor for small responses already sent in a single `write` call.

### 6. Huge Pages / Memory Alignment

`@html_resp` and `@wasm_resp` are 266 KB globals accessed on every request. Aligning them
to 2 MB huge-page boundaries and using `madvise(MADV_HUGEPAGE)` keeps the response buffers
in TLB-resident huge pages, reducing TLB misses in the write path.

**Expected impact:** small but measurable (~5%) under very high RPS.

### Summary Table

| Strategy | Complexity | Expected RPS gain |
|---|---|---|
| HTTP keep-alive | Medium | 3–5× |
| epoll event loop | High | 10–50× under concurrency |
| Pre-fork multi-worker | Medium | N× (N = core count) |
| sendfile zero-copy | Low | ~20% for large files |
| TCP_CORK | Low | negligible for small responses |
| Huge pages | Low | ~5% |

A production-grade server implements all of the above. nginx's architecture combines
pre-fork workers (strategy 3) with an epoll event loop per worker (strategy 2) and
keep-alive (strategy 1), which is why it achieves 100,000–500,000 RPS on the same
hardware where LastStack currently achieves ~13,000 sequential RPS.

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
- HTTP keep-alive and epoll event loop in server.ll
- Pre-fork multi-worker with SO_REUSEPORT
