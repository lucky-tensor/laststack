; ============================================================================
; LastStack Demo: Post-Human WebServer (optimized)
; ============================================================================
;
; @module   server
; @sum      Minimal HTTP/1.1 server: HTML and WASM served from prebuilt response buffers.
; @target   x86_64-pc-linux-gnu
; @entry    @main
; @exports  @main
;
; IR Graph Comment Schema  (parsed by tools/extract-graph)
; ─────────────────────────────────────────────────────────
;   Node declarations  (start a new graph node context)
;     @module / @fn / @global / @type  <id>
;
;   Attribute tags  (free-form string — node properties)
;     @sum       one-line semantic summary
;     @layer     entry | init | hot-path | util | diagnostic
;     @pre       precondition on entry
;     @post      postcondition on normal exit
;     @inv       invariant that always holds
;     @proof     proof strategy / argument
;     @cfg       control-flow summary (block → successors)
;     @mut       mutation pattern  (global only)
;
;   Edge tags  (comma-separated targets — become directed edges in the graph)
;     @calls     fn → fn          direct call edges
;     @called-by fn → fn          reverse call edges (for agent search)
;     @reads     fn → global      global read edges
;     @writes    fn → global      global write edges
;     @read-by   global → fn      reverse read edges
;     @written-by global → fn     reverse write edges
;     @emits     fn → effect      effect emission edges
;     @uses-type fn → type        struct usage edges
;
;   Effect vocabulary for @emits
;     pure       no side effects
;     sys:net    network syscalls  (socket, bind, listen, accept)
;     sys:io     I/O syscalls      (read, write)
;     sys:fs     filesystem calls  (open, close, stat)
;     sys:proc   process calls     (fork, wait, sysconf)
;     io:stdout  stdio             (printf)
;
; Performance optimizations (see spec.md):
;   1. Asset caching     — files read once at startup into global buffers;
;                          complete HTTP responses (header+body) prebuilt.
;   2. Zero per-request  — no snprintf, no memset, no open/read/close,
;      heap/file work       no malloc per connection.
;   3. Global req buffer — single 1025-byte buffer, one null-byte store
;                          instead of memset(1025) per request.
;   4. No per-request    — check_invariants and printf removed from hot path.
;      logging/checks
;   5. Precomputed 404   — strlen replaced with stored constant.
;
; Hot path per request: read → store-1-byte → strstr → write → close (3 syscalls)
;
; ============================================================================

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

; ============================================================================
; Structs
; ============================================================================

%struct.sockaddr_in = type { i16, i16, i32, [8 x i8] }
%struct.stat        = type { i64, i64, i32, i32, i32, i32, i32, i32, i64, i64, i64, i64, [16 x i8] }

; ============================================================================
; Globals — compile-time constants (historical, kept for reference)
; ============================================================================

; @global html_body (used by @build_response, retained for documentation)
@html_body = private unnamed_addr constant [338 x i8] c"<!DOCTYPE html><html><head><meta charset=\22utf-8\22><title>LastStack</title><style>body{background:#0a0a0a;color:#00ff41;font-family:monospace;display:flex;justify-content:center;align-items:center;height:100vh;margin:0}h1{font-size:3em;text-shadow:0 0 20px #00ff41}</style></head><body><h1>LastStack: Post-Human Software</h1></body></html>\00"
@http_status           = private unnamed_addr constant [18 x i8]  c"HTTP/1.1 200 OK\0D\0A\00"
@http_content_type     = private unnamed_addr constant [41 x i8]  c"Content-Type: text/html; charset=utf-8\0D\0A\00"
@http_content_length   = private unnamed_addr constant [17 x i8]  c"Content-Length: \00"
@http_crlf             = private unnamed_addr constant [3  x i8]  c"\0D\0A\00"
@http_connection_close = private unnamed_addr constant [20 x i8]  c"Connection: close\0D\0A\00"
@content_length_str    = private unnamed_addr constant [4  x i8]  c"337\00"

; @global server messages
@msg_start        = private unnamed_addr constant [46 x i8] c"[LastStack] Server listening on port 9090...\0A\00"
@msg_error_socket = private unnamed_addr constant [35 x i8] c"[LastStack] Error: socket failed.\0A\00"
@msg_error_bind   = private unnamed_addr constant [33 x i8] c"[LastStack] Error: bind failed.\0A\00"
@msg_error_listen = private unnamed_addr constant [35 x i8] c"[LastStack] Error: listen failed.\0A\00"
@msg_invariant_ok = private unnamed_addr constant [51 x i8] c"[LastStack] Invariant check: all invariants hold.\0A\00"

; @global file paths
@path_index = private unnamed_addr constant [20 x i8] c"./public/index.html\00"
@path_wasm  = private unnamed_addr constant [22 x i8] c"./public/fractal.wasm\00"

; @global content type strings
@content_type_html = private unnamed_addr constant [26 x i8] c"Content-Type: text/html\0D\0A\00"
@content_type_wasm = private unnamed_addr constant [33 x i8] c"Content-Type: application/wasm\0D\0A\00"

; @global request parser strings
@req_fractal = private unnamed_addr constant [18 x i8] c"GET /fractal.wasm\00"

; @global header/response templates
@fmt_header_200 = private unnamed_addr constant [62 x i8] c"HTTP/1.1 200 OK\0D\0A%sContent-Length: %ld\0D\0AConnection: close\0D\0A\0D\0A\00"
@response_404   = private unnamed_addr constant [100 x i8] c"HTTP/1.1 404 Not Found\0D\0AContent-Type: text/plain\0D\0AContent-Length: 9\0D\0AConnection: close\0D\0A\0D\0ANot Found\00"

; @global helper strings (used by @get_content_type)
@str_wasm = private unnamed_addr constant [6 x i8] c".wasm\00"

; ============================================================================
; Globals — runtime state (populated at startup by @load_assets)
; ============================================================================

; @global  @html_resp
; @sum     Prebuilt HTTP/1.1 200 response buffer for HTML: header + body in one contiguous allocation.
; @mut     startup-only (written once by @load_assets before accept loop)
; @written-by @load_assets
; @read-by @handle_client
; @inv     html_resp_len == header_len + html_file_size  (set by @load_assets)
@html_resp     = global [266240 x i8] zeroinitializer, align 16

; @global  @html_resp_len
; @sum     Byte length of valid content in @html_resp.
; @mut     startup-only
; @written-by @load_assets
; @read-by @handle_client
@html_resp_len = global i64 0, align 8

; @global  @wasm_resp
; @sum     Prebuilt HTTP/1.1 200 response buffer for WASM: header + body in one contiguous allocation.
; @mut     startup-only
; @written-by @load_assets
; @read-by @handle_client
; @inv     wasm_resp_len == header_len + wasm_file_size  (set by @load_assets)
@wasm_resp     = global [266240 x i8] zeroinitializer, align 16

; @global  @wasm_resp_len
; @sum     Byte length of valid content in @wasm_resp.
; @mut     startup-only
; @written-by @load_assets
; @read-by @handle_client
@wasm_resp_len = global i64 0, align 8

; @global  @response_404_len
; @sum     Precomputed byte length of @response_404 (99); avoids strlen on hot path.
; @mut     constant (initialised to 99, never written at runtime)
; @read-by @handle_client
; @inv     value == strlen(@response_404) == 99
@response_404_len = global i64 99, align 8

; @global  @req_buf
; @sum     Single shared 1025-byte request-read buffer; safe because server is single-threaded.
; @mut     per-request (written by @handle_client, null-terminated after each read)
; @written-by @handle_client
; @read-by @handle_client
@req_buf = global [1025 x i8] zeroinitializer, align 16

; @global  @file_load_buf
; @sum     262 KiB scratch buffer used by @load_assets to stage file data before building responses.
; @mut     startup-only (written twice: once for HTML, once for WASM; not read at runtime)
; @written-by @load_assets
; @read-by @load_assets
@file_load_buf = global [262144 x i8] zeroinitializer, align 16

; Startup messages
@msg_load_ok   = private unnamed_addr constant [28 x i8] c"[LastStack] Assets loaded.\0A\00"
@msg_load_fail = private unnamed_addr constant [39 x i8] c"[LastStack] Error: asset load failed.\0A\00"

; ============================================================================
; External declarations (libc / POSIX)
; ============================================================================

declare i32 @socket(i32, i32, i32)
declare i32 @bind(i32, i8*, i32)
declare i32 @listen(i32, i32)
declare i32 @accept(i32, i8*, i32*)
declare i64 @read(i32, i8*, i64)
declare i64 @write(i32, i8*, i64)
declare i32 @close(i32)
declare i32 @setsockopt(i32, i32, i32, i8*, i32)
declare i32 @htons(i32)
declare i32 @printf(i8*, ...)
declare i32 @snprintf(i8*, i64, i8*, ...)
declare i64 @strlen(i8*)
declare i32 @open(i8*, i32)
declare i8* @strstr(i8*, i8*)
declare i64 @sysconf(i32)
declare i32 @fork()
declare i32 @wait(i32*)

; ============================================================================
; @fn        @build_response
; @sum       Assemble an HTTP/1.1 200 response into a caller-supplied buffer; all sources are compile-time constants.
; @layer     util
; @called-by (unused — retained for documentation)
; @calls     @strlen, @llvm.memcpy
; @reads     @http_status, @http_content_type, @http_content_length, @http_crlf, @http_connection_close, @content_length_str, @html_body
; @writes    (none — writes to argument buffer only)
; @emits     pure
; @cfg       entry (single block)
; @pre       buf points to >= 1024 writable bytes
; @post      return > 0; buf contains a valid HTTP/1.1 200 response
; @inv       all source strings are compile-time constants; length sum is statically bounded
; @proof     constant-propagation: total = sum(strlen(each constant)), QED
; ============================================================================

define i64 @build_response(i8* %buf) !pcf.schema !36 !pcf.toolchain !37 !pcf.pre !1 !pcf.post !2 !pcf.proof !3 !pcf.effects !16 !pcf.bind !17 {
entry:
  %offset = alloca i64
  store i64 0, i64* %offset

  %status_ptr = getelementptr [18 x i8], [18 x i8]* @http_status, i64 0, i64 0
  %status_len = call i64 @strlen(i8* %status_ptr)
  %off0 = load i64, i64* %offset
  %dst0 = getelementptr i8, i8* %buf, i64 %off0
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst0, i8* %status_ptr, i64 %status_len, i1 false)
  %off1 = add i64 %off0, %status_len
  store i64 %off1, i64* %offset

  %ct_ptr = getelementptr [41 x i8], [41 x i8]* @http_content_type, i64 0, i64 0
  %ct_len = call i64 @strlen(i8* %ct_ptr)
  %off2 = load i64, i64* %offset
  %dst1 = getelementptr i8, i8* %buf, i64 %off2
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst1, i8* %ct_ptr, i64 %ct_len, i1 false)
  %off3 = add i64 %off2, %ct_len
  store i64 %off3, i64* %offset

  %cl_ptr = getelementptr [17 x i8], [17 x i8]* @http_content_length, i64 0, i64 0
  %cl_len = call i64 @strlen(i8* %cl_ptr)
  %off4 = load i64, i64* %offset
  %dst2 = getelementptr i8, i8* %buf, i64 %off4
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst2, i8* %cl_ptr, i64 %cl_len, i1 false)
  %off5 = add i64 %off4, %cl_len
  store i64 %off5, i64* %offset

  %clv_ptr = getelementptr [4 x i8], [4 x i8]* @content_length_str, i64 0, i64 0
  %clv_len = call i64 @strlen(i8* %clv_ptr)
  %off6 = load i64, i64* %offset
  %dst3 = getelementptr i8, i8* %buf, i64 %off6
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst3, i8* %clv_ptr, i64 %clv_len, i1 false)
  %off7 = add i64 %off6, %clv_len
  store i64 %off7, i64* %offset

  %crlf_ptr = getelementptr [3 x i8], [3 x i8]* @http_crlf, i64 0, i64 0
  %crlf_len = call i64 @strlen(i8* %crlf_ptr)
  %off8 = load i64, i64* %offset
  %dst4 = getelementptr i8, i8* %buf, i64 %off8
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst4, i8* %crlf_ptr, i64 %crlf_len, i1 false)
  %off9 = add i64 %off8, %crlf_len
  store i64 %off9, i64* %offset

  %cc_ptr = getelementptr [20 x i8], [20 x i8]* @http_connection_close, i64 0, i64 0
  %cc_len = call i64 @strlen(i8* %cc_ptr)
  %off10 = load i64, i64* %offset
  %dst5 = getelementptr i8, i8* %buf, i64 %off10
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst5, i8* %cc_ptr, i64 %cc_len, i1 false)
  %off11 = add i64 %off10, %cc_len
  store i64 %off11, i64* %offset

  %off12 = load i64, i64* %offset
  %dst6 = getelementptr i8, i8* %buf, i64 %off12
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst6, i8* %crlf_ptr, i64 %crlf_len, i1 false)
  %off13 = add i64 %off12, %crlf_len
  store i64 %off13, i64* %offset

  %body_ptr = getelementptr [338 x i8], [338 x i8]* @html_body, i64 0, i64 0
  %body_len = call i64 @strlen(i8* %body_ptr)
  %off14 = load i64, i64* %offset
  %dst7 = getelementptr i8, i8* %buf, i64 %off14
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst7, i8* %body_ptr, i64 %body_len, i1 false)
  %off15 = add i64 %off14, %body_len
  store i64 %off15, i64* %offset

  %total = load i64, i64* %offset
  ret i64 %total
}

; ============================================================================
; @fn        @read_file
; @sum       Open a file, read up to buf_size bytes into buf, close fd; returns byte count or -1.
; @layer     util
; @called-by @load_assets
; @calls     @open, @read, @close
; @reads     (path arg — not a module global)
; @writes    (buf arg — not a module global)
; @emits     sys:fs, sys:io
; @pre       path is a valid null-terminated C string; buf points to buf_size writable bytes
; @post      return >= 0 bytes read on success; return -1 if open failed; fd closed on all paths
; @inv       fd is closed on every exit path
; @proof     case-analysis: read_open calls @close before ret; file_fail never opens fd. QED
; ============================================================================

define i64 @read_file(i8* %path, i8* %buf, i64 %buf_size) !pcf.schema !36 !pcf.toolchain !37 !pcf.pre !18 !pcf.post !19 !pcf.proof !20 !pcf.effects !21 !pcf.bind !22 {
entry:
  %fd = call i32 @open(i8* %path, i32 0)
  %fd_ok = icmp sge i32 %fd, 0
  br i1 %fd_ok, label %read_open, label %file_fail

read_open:
  %bytes = call i64 @read(i32 %fd, i8* %buf, i64 %buf_size)
  call i32 @close(i32 %fd)
  ret i64 %bytes

file_fail:
  ret i64 -1
}

; ============================================================================
; @fn        @get_content_type
; @sum       Return a Content-Type header string pointer based on path suffix (.wasm → wasm, else html).
; @layer     util
; @called-by (unused — @load_assets inlines this logic; retained for reference)
; @calls     @strstr
; @reads     @str_wasm, @content_type_wasm, @content_type_html
; @writes    (none)
; @emits     pure
; @pre       path is a valid null-terminated C string
; @post      return points to a valid null-terminated Content-Type header line (compile-time constant)
; ============================================================================

define i8* @get_content_type(i8* %path) !pcf.schema !36 !pcf.toolchain !37 !pcf.pre !23 !pcf.post !24 !pcf.proof !25 !pcf.effects !26 !pcf.bind !27 {
entry:
  %wasm_suffix  = getelementptr [6 x i8], [6 x i8]* @str_wasm, i64 0, i64 0
  %is_wasm_ptr  = call i8* @strstr(i8* %path, i8* %wasm_suffix)
  %is_wasm      = icmp ne i8* %is_wasm_ptr, null
  br i1 %is_wasm, label %ret_wasm, label %ret_html

ret_wasm:
  %ptr_wasm = getelementptr [33 x i8], [33 x i8]* @content_type_wasm, i64 0, i64 0
  ret i8* %ptr_wasm

ret_html:
  %ptr_html = getelementptr [26 x i8], [26 x i8]* @content_type_html, i64 0, i64 0
  ret i8* %ptr_html
}

; ============================================================================
; @fn        @check_invariants
; @sum       Assert response buffer validity and log result to stdout; diagnostic only, removed from hot path.
; @layer     diagnostic
; @called-by (removed from hot path — retained for offline/diagnostic use)
; @calls     @printf
; @reads     (args only — no module globals)
; @writes    (none)
; @emits     io:stdout
; @pre       response_buf != null; response_len > 0
; @post      logs invariant status to stdout; no mutation of response data
; @inv       invariants_fail block is unreachable given @load_assets postcondition
; @proof     runtime-assertion: checks are redundant given caller's proof. QED
; ============================================================================

define void @check_invariants(i8* %response_buf, i64 %response_len) !pcf.schema !36 !pcf.toolchain !37 !pcf.pre !4 !pcf.post !5 !pcf.proof !6 !pcf.effects !28 !pcf.bind !29 {
entry:
  %inv1 = icmp sgt i64 %response_len, 0
  %inv2 = icmp ne i8* %response_buf, null
  %ok   = and i1 %inv1, %inv2
  br i1 %ok, label %invariants_ok, label %invariants_fail

invariants_ok:
  %ok_msg = getelementptr [51 x i8], [51 x i8]* @msg_invariant_ok, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %ok_msg)
  ret void

invariants_fail:
  ret void
}

; ============================================================================
; @fn        @load_assets
; @sum       Read HTML and WASM assets from disk and build prebuilt HTTP responses into globals; called once at startup.
; @layer     init
; @called-by @main
; @calls     @read_file, @snprintf, @llvm.memcpy, @printf
; @reads     @path_index, @path_wasm, @fmt_header_200, @content_type_html, @content_type_wasm, @file_load_buf
; @writes    @html_resp, @html_resp_len, @wasm_resp, @wasm_resp_len, @file_load_buf
; @emits     sys:fs, sys:io, io:stdout
; @cfg       entry → build_html_resp → load_wasm → build_wasm_resp → done | entry → asset_fail | load_wasm → asset_fail
; @pre       no clients connected; filesystem accessible; @html_resp and @wasm_resp are zeroed
; @post      @html_resp and @wasm_resp contain complete HTTP/1.1 200 responses iff return == 0
; @inv       @file_load_buf is reused sequentially (HTML load then WASM load); not read after startup
; @proof     each @read_file result is checked against > 0; return 0 only when both assets load. QED
; ============================================================================

define i32 @load_assets() !pcf.schema !36 !pcf.toolchain !37 !pcf.pre !13 !pcf.post !14 !pcf.proof !15 !pcf.effects !30 !pcf.bind !31 {
entry:
  %file_buf   = getelementptr [262144 x i8], [262144 x i8]* @file_load_buf, i64 0, i64 0
  %hdr_fmt    = getelementptr [62 x i8], [62 x i8]* @fmt_header_200, i64 0, i64 0
  %index_path = getelementptr [20 x i8], [20 x i8]* @path_index, i64 0, i64 0
  %html_size  = call i64 @read_file(i8* %index_path, i8* %file_buf, i64 262144)
  %html_ok    = icmp sgt i64 %html_size, 0
  br i1 %html_ok, label %build_html_resp, label %asset_fail

build_html_resp:
  %html_resp_ptr  = getelementptr [266240 x i8], [266240 x i8]* @html_resp, i64 0, i64 0
  %html_ct        = getelementptr [26 x i8], [26 x i8]* @content_type_html, i64 0, i64 0
  %html_hdr_len32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %html_resp_ptr, i64 4096, i8* %hdr_fmt, i8* %html_ct, i64 %html_size)
  %html_hdr_len   = sext i32 %html_hdr_len32 to i64
  %html_body_dst  = getelementptr i8, i8* %html_resp_ptr, i64 %html_hdr_len
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %html_body_dst, i8* %file_buf, i64 %html_size, i1 false)
  %html_total = add i64 %html_hdr_len, %html_size
  store i64 %html_total, i64* @html_resp_len, align 8
  br label %load_wasm

load_wasm:
  %wasm_path = getelementptr [22 x i8], [22 x i8]* @path_wasm, i64 0, i64 0
  %wasm_size = call i64 @read_file(i8* %wasm_path, i8* %file_buf, i64 262144)
  %wasm_ok   = icmp sgt i64 %wasm_size, 0
  br i1 %wasm_ok, label %build_wasm_resp, label %asset_fail

build_wasm_resp:
  %wasm_resp_ptr  = getelementptr [266240 x i8], [266240 x i8]* @wasm_resp, i64 0, i64 0
  %wasm_ct        = getelementptr [33 x i8], [33 x i8]* @content_type_wasm, i64 0, i64 0
  %wasm_hdr_len32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %wasm_resp_ptr, i64 4096, i8* %hdr_fmt, i8* %wasm_ct, i64 %wasm_size)
  %wasm_hdr_len   = sext i32 %wasm_hdr_len32 to i64
  %wasm_body_dst  = getelementptr i8, i8* %wasm_resp_ptr, i64 %wasm_hdr_len
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %wasm_body_dst, i8* %file_buf, i64 %wasm_size, i1 false)
  %wasm_total = add i64 %wasm_hdr_len, %wasm_size
  store i64 %wasm_total, i64* @wasm_resp_len, align 8
  br label %done

done:
  %ok_msg = getelementptr [28 x i8], [28 x i8]* @msg_load_ok, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %ok_msg)
  ret i32 0

asset_fail:
  %fail_msg = getelementptr [39 x i8], [39 x i8]* @msg_load_fail, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %fail_msg)
  ret i32 1
}

; ============================================================================
; @fn        @handle_client
; @sum       Read one HTTP request, route to a prebuilt response (HTML, WASM, or 404), write to fd, close.
; @layer     hot-path
; @called-by @main
; @calls     @read, @write, @close, @strstr
; @reads     @req_fractal, @html_resp, @html_resp_len, @wasm_resp, @wasm_resp_len, @response_404, @response_404_len
; @writes    @req_buf
; @emits     sys:io, sys:fs
; @cfg       entry → parse_request → serve_wasm | serve_html | entry → serve_404
; @pre       client_fd >= 0; @load_assets has returned 0
; @post      one complete HTTP response written to client_fd; client_fd closed
; @inv       client_fd is closed on every exit path (serve_wasm, serve_html, serve_404)
; @proof     case-analysis: all three serve paths call @close before ret. QED
; ============================================================================

define void @handle_client(i32 %client_fd) !pcf.schema !36 !pcf.toolchain !37 !pcf.pre !7 !pcf.post !8 !pcf.proof !9 !pcf.effects !32 !pcf.bind !33 {
entry:
  ; Read into global buffer (single-threaded: no concurrent access)
  %req_ptr    = getelementptr [1025 x i8], [1025 x i8]* @req_buf, i64 0, i64 0
  %bytes_read = call i64 @read(i32 %client_fd, i8* %req_ptr, i64 1024)
  %has_data   = icmp sgt i64 %bytes_read, 0
  br i1 %has_data, label %parse_request, label %serve_404

parse_request:
  ; Null-terminate after the received data (one store, no memset)
  %null_pos = getelementptr i8, i8* %req_ptr, i64 %bytes_read
  store i8 0, i8* %null_pos, align 1

  %fractal_str   = getelementptr [18 x i8], [18 x i8]* @req_fractal, i64 0, i64 0
  %fractal_match = call i8* @strstr(i8* %req_ptr, i8* %fractal_str)
  %is_fractal    = icmp ne i8* %fractal_match, null
  br i1 %is_fractal, label %serve_wasm, label %serve_html

serve_wasm:
  %wasm_ptr = getelementptr [266240 x i8], [266240 x i8]* @wasm_resp, i64 0, i64 0
  %wasm_len = load i64, i64* @wasm_resp_len, align 8
  call i64 @write(i32 %client_fd, i8* %wasm_ptr, i64 %wasm_len)
  call i32 @close(i32 %client_fd)
  ret void

serve_html:
  %html_ptr = getelementptr [266240 x i8], [266240 x i8]* @html_resp, i64 0, i64 0
  %html_len = load i64, i64* @html_resp_len, align 8
  call i64 @write(i32 %client_fd, i8* %html_ptr, i64 %html_len)
  call i32 @close(i32 %client_fd)
  ret void

serve_404:
  %nf_ptr = getelementptr [100 x i8], [100 x i8]* @response_404, i64 0, i64 0
  %nf_len = load i64, i64* @response_404_len, align 8
  call i64 @write(i32 %client_fd, i8* %nf_ptr, i64 %nf_len)
  call i32 @close(i32 %client_fd)
  ret void
}

; ============================================================================
; @fn        @main
; @sum       Program entry: bind TCP/9090, load assets, fork CPU-count workers, accept loop forever.
; @layer     entry
; @called-by (program entry point)
; @calls     @socket, @setsockopt, @htons, @bind, @listen, @load_assets, @sysconf, @fork, @wait, @accept, @handle_client, @printf, @close, @llvm.memset
; @reads     @msg_start, @msg_error_socket, @msg_error_bind, @msg_error_listen
; @writes    (none — stack locals only)
; @emits     sys:net, sys:io, sys:proc, io:stdout
; @uses-type %struct.sockaddr_in
; @cfg       entry → socket_ok → bind_success → listen_success → start_workers → accept_loop → (forever) | → socket_fail | → bind_fail | → listen_fail | → load_fail
; @pre       (program entry — no preconditions)
; @post      return 1 on setup failure; never returns on success (infinite accept loop)
; @inv       sockfd is closed on every error exit path
; @proof     case-analysis: 4 error exits close sockfd and return 1; success path loops forever. QED
; ============================================================================

define i32 @main() !pcf.schema !36 !pcf.toolchain !37 !pcf.pre !10 !pcf.post !11 !pcf.proof !12 !pcf.effects !34 !pcf.bind !35 {
entry:
  %sockfd  = call i32 @socket(i32 2, i32 1, i32 0)
  %sock_ok = icmp sge i32 %sockfd, 0
  br i1 %sock_ok, label %socket_ok, label %socket_fail

socket_fail:
  %err_sock = getelementptr [35 x i8], [35 x i8]* @msg_error_socket, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %err_sock)
  ret i32 1

socket_ok:
  ; SO_REUSEADDR — allow fast restart without waiting for TIME_WAIT
  %optval     = alloca i32
  store i32 1, i32* %optval
  %optval_ptr = bitcast i32* %optval to i8*
  call i32 @setsockopt(i32 %sockfd, i32 1, i32 2, i8* %optval_ptr, i32 4)

  ; SO_REUSEPORT — kernel load-balances across all forked workers (Linux 3.9+)
  call i32 @setsockopt(i32 %sockfd, i32 1, i32 15, i8* %optval_ptr, i32 4)

  ; Prepare sockaddr_in { AF_INET=2, htons(9090), INADDR_ANY=0, pad=0 }
  %addr       = alloca %struct.sockaddr_in
  %addr_fam   = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 0
  store i16 2, i16* %addr_fam
  %port_net   = call i32 @htons(i32 9090)
  %port_i16   = trunc i32 %port_net to i16
  %addr_port  = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 1
  store i16 %port_i16, i16* %addr_port
  %addr_ip    = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 2
  store i32 0, i32* %addr_ip
  %addr_pad   = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 3, i32 0
  call void @llvm.memset.p0i8.i64(i8* %addr_pad, i8 0, i64 8, i1 false)

  %addr_ptr    = bitcast %struct.sockaddr_in* %addr to i8*
  %bind_result = call i32 @bind(i32 %sockfd, i8* %addr_ptr, i32 16)
  %bind_ok     = icmp sge i32 %bind_result, 0
  br i1 %bind_ok, label %bind_success, label %bind_fail

bind_fail:
  %err_bind = getelementptr [33 x i8], [33 x i8]* @msg_error_bind, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %err_bind)
  call i32 @close(i32 %sockfd)
  ret i32 1

bind_success:
  %listen_result = call i32 @listen(i32 %sockfd, i32 128)
  %listen_ok     = icmp sge i32 %listen_result, 0
  br i1 %listen_ok, label %listen_success, label %listen_fail

listen_fail:
  %err_listen = getelementptr [35 x i8], [35 x i8]* @msg_error_listen, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %err_listen)
  call i32 @close(i32 %sockfd)
  ret i32 1

listen_success:
  %start_msg = getelementptr [46 x i8], [46 x i8]* @msg_start, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %start_msg)
  %load_result = call i32 @load_assets()
  %load_ok     = icmp eq i32 %load_result, 0
  br i1 %load_ok, label %start_workers, label %load_fail

load_fail:
  call i32 @close(i32 %sockfd)
  ret i32 1

start_workers:
  ; _SC_NPROCESSORS_ONLN = 84 on Linux — number of online CPUs
  %ncpus_l  = call i64 @sysconf(i32 84)
  %ncpus_i  = trunc i64 %ncpus_l to i32
  %ncpus_ok = icmp sgt i32 %ncpus_i, 0
  %nworkers = select i1 %ncpus_ok, i32 %ncpus_i, i32 1
  br label %fork_loop

fork_loop:
  ; @invariant  i in [0, nworkers]; child processes never reach this block
  %i          = phi i32 [ 0, %start_workers ], [ %i_next, %fork_parent ]
  %all_forked = icmp sge i32 %i, %nworkers
  br i1 %all_forked, label %parent_wait, label %do_fork

do_fork:
  %pid      = call i32 @fork()
  %is_child = icmp eq i32 %pid, 0
  br i1 %is_child, label %accept_loop, label %fork_parent

fork_parent:
  %i_next = add i32 %i, 1
  br label %fork_loop

parent_wait:
  ; Parent blocks until a child exits; loop to catch all children
  call i32 @wait(i32* null)
  br label %parent_wait

accept_loop:
  ; Only child processes reach here
  %client_fd = call i32 @accept(i32 %sockfd, i8* null, i32* null)
  %client_ok = icmp sge i32 %client_fd, 0
  br i1 %client_ok, label %client_accepted, label %accept_loop

client_accepted:
  call void @handle_client(i32 %client_fd)
  br label %accept_loop
}

; ============================================================================
; LLVM intrinsics
; ============================================================================

declare void @llvm.memcpy.p0i8.p0i8.i64(i8* nocapture writeonly, i8* nocapture readonly, i64, i1 immarg)
declare void @llvm.memset.p0i8.i64(i8* nocapture writeonly, i8, i64, i1 immarg)

; ============================================================================
; PCF Metadata — formal specifications in SMT-LIB
; ============================================================================

; build_response precondition
!1 = !{!"pcf.pre", !"smt",
       !"(declare-const buf (_ BitVec 64))
         (assert (not (= buf #x0000000000000000)))"}

; build_response postcondition
!2 = !{!"pcf.post", !"smt",
       !"(declare-const result (_ BitVec 64))
         (assert (bvsgt result #x0000000000000000))
         (assert (= result (bvadd status_len ct_len cl_len clv_len crlf_len cc_len crlf_len body_len)))"}

; build_response proof
!3 = !{!"pcf.proof", !"witness",
       !"strategy: constant-propagation
         all-writes-are-to-compile-time-constant-strings
         total-length = sum(strlen(each-constant))
         result > 0 because all constants are non-empty
         qed"}

!16 = !{!"pcf.effects",
        !"libc.strlen,llvm.memcpy,global.read:@http_status,@http_content_type,@http_content_length,@content_length_str,@http_crlf,@http_connection_close,@html_body"}
!17 = !{!"pcf.bind",
        !"buf->arg:%buf,result->ret"}

; check_invariants precondition
!4 = !{!"pcf.pre", !"smt",
       !"(declare-const response_buf (_ BitVec 64))
         (declare-const response_len (_ BitVec 64))
         (assert (not (= response_buf #x0000000000000000)))
         (assert (bvsgt response_len #x0000000000000000))"}

; check_invariants postcondition
!5 = !{!"pcf.post", !"smt", !"(assert true)  ; side effect is logging only"}

; check_invariants proof
!6 = !{!"pcf.proof", !"witness",
       !"strategy: runtime-assertion
         invariants-checked-at-runtime
         failure-branch-unreachable-given-load_assets-postcondition
         qed"}

!18 = !{!"pcf.pre", !"smt",
        !"(declare-const path (_ BitVec 64))
          (declare-const buf (_ BitVec 64))
          (declare-const buf_size (_ BitVec 64))
          (assert (not (= path #x0000000000000000)))
          (assert (not (= buf #x0000000000000000)))
          (assert (bvugt buf_size #x0000000000000000))"}
!19 = !{!"pcf.post", !"smt",
        !"(declare-const result (_ BitVec 64))
          (assert (or (= result #xffffffffffffffff) (bvuge result #x0000000000000000)))"}
!20 = !{!"pcf.proof", !"witness",
        !"strategy: case-analysis
          if open fails -> return -1
          if open succeeds -> read then close then return bytes
          fd is closed on success path
          qed"}
!21 = !{!"pcf.effects",
        !"sys.open,sys.read,sys.close,global.read:none,global.write:none"}
!22 = !{!"pcf.bind",
        !"path->arg:%path,buf->arg:%buf,buf_size->arg:%buf_size,result->ret"}

!23 = !{!"pcf.pre", !"smt",
        !"(declare-const path (_ BitVec 64))
          (assert (not (= path #x0000000000000000)))"}
!24 = !{!"pcf.post", !"smt",
        !"(declare-const result (_ BitVec 64))
          (assert (not (= result #x0000000000000000)))"}
!25 = !{!"pcf.proof", !"witness",
        !"strategy: branch-complete
          wasm suffix match returns content_type_wasm
          else returns content_type_html
          both branches return non-null static pointers
          qed"}
!26 = !{!"pcf.effects",
        !"libc.strstr,global.read:@str_wasm,@content_type_wasm,@content_type_html"}
!27 = !{!"pcf.bind",
        !"path->arg:%path,result->ret"}

!28 = !{!"pcf.effects",
        !"libc.printf,global.read:@msg_invariant_ok"}
!29 = !{!"pcf.bind",
        !"response_buf->arg:%response_buf,response_len->arg:%response_len"}

; handle_client precondition
!7 = !{!"pcf.pre", !"smt",
       !"(declare-const client_fd (_ BitVec 32))
         (assert (bvsge client_fd #x00000000))
         (assert (bvsgt html_resp_len #x0000000000000000))
         (assert (bvsgt wasm_resp_len #x0000000000000000))"}

; handle_client postcondition
!8 = !{!"pcf.post", !"smt",
       !"(declare-const client_fd (_ BitVec 32))
         (assert (= (fd_state client_fd) closed))"}

; handle_client proof
!9 = !{!"pcf.proof", !"witness",
       !"strategy: case-analysis
         case serve_wasm: write(wasm_resp, wasm_resp_len) then close(fd)
         case serve_html: write(html_resp, html_resp_len) then close(fd)
         case serve_404:  write(response_404, 99)        then close(fd)
         all-cases-covered, fd-always-closed
         qed"}

!30 = !{!"pcf.effects",
        !"libc.printf,libc.snprintf,sys.open,sys.read,sys.close,llvm.memcpy,global.read:@path_index,@path_wasm,@fmt_header_200,@content_type_html,@content_type_wasm,global.write:@html_resp,@html_resp_len,@wasm_resp,@wasm_resp_len"}
!31 = !{!"pcf.bind",
        !"result->ret"}

!32 = !{!"pcf.effects",
        !"sys.read,libc.strstr,sys.write,sys.close,global.read:@req_fractal,@html_resp,@html_resp_len,@wasm_resp,@wasm_resp_len,@response_404,@response_404_len,global.write:@req_buf"}
!33 = !{!"pcf.bind",
        !"client_fd->arg:%client_fd"}

!34 = !{!"pcf.effects",
        !"sys.socket,sys.setsockopt,sys.bind,sys.listen,sys.accept,sys.close,sys.fork,sys.wait,libc.printf,libc.sysconf,global.read:@msg_start,@msg_error_socket,@msg_error_bind,@msg_error_listen"}
!35 = !{!"pcf.bind",
        !"exit_code->ret,sockfd->state:%sockfd"}

!36 = !{!"pcf.schema",
        !"laststack.pcf.v1"}

!37 = !{!"pcf.toolchain",
        !"checker:laststack-verify-gate",
        !"version:0.1.0",
        !"hash:dev"}

; main precondition
!10 = !{!"pcf.pre", !"smt", !"(assert true)"}

; main postcondition
!11 = !{!"pcf.post", !"smt",
        !"(declare-const exit_code (_ BitVec 32))
          (assert (or (= exit_code #x00000000) (= exit_code #x00000001)))"}

; main proof
!12 = !{!"pcf.proof", !"witness",
        !"strategy: case-analysis
          case socket_fail:  exit_code = 1
          case bind_fail:    exit_code = 1
          case listen_fail:  exit_code = 1
          case load_fail:    exit_code = 1
          case parent_wait:  infinite wait() loop (no exit, parent)
          case accept_loop:  infinite accept() loop (no exit, each child)
          all-cases-covered
          qed"}

; load_assets precondition
!13 = !{!"pcf.pre", !"smt", !"(assert true)  ; called once at startup"}

; load_assets postcondition
!14 = !{!"pcf.post", !"smt",
        !"(declare-const result (_ BitVec 32))
          (assert (or (= result #x00000000) (= result #x00000001)))
          (assert (=> (= result #x00000000)
                      (and (bvsgt html_resp_len #x0000000000000000)
                           (bvsgt wasm_resp_len #x0000000000000000))))"}

; load_assets proof
!15 = !{!"pcf.proof", !"witness",
        !"strategy: case-analysis
          case asset_fail (html): read_file returned <= 0, return 1
          case asset_fail (wasm): read_file returned <= 0, return 1
          case done: both reads succeeded, both responses built, return 0
          all-cases-covered
          qed"}
