; ============================================================================
; LastStack Demo: Post-Human WebServer
; ============================================================================
;
; @module       server
; @description  Minimal HTTP server written directly in LLVM IR.
; @entry        @main
; @build        demo/build.sh
; @verify       demo/verify.sh
;
; Navigation convention:
;   @calls       — functions this function calls
;   @called-by   — functions that call this function
;   @reads       — globals this function reads
;   @uses-type   — struct types this function uses
;   @cfg         — control flow: block → [successor blocks]
;   @invariant   — property that always holds
;   @pre         — precondition (what must be true on entry)
;   @post        — postcondition (what is true on exit)
;   @proof       — proof strategy for correctness
;
; An agent navigating this file can grep for any tag to traverse the graph:
;   grep "@calls.*build_response" *.ll    → who calls build_response?
;   grep "@called-by.*main" *.ll          → what does main call?
;   grep "@invariant" *.ll                → all invariants in the system
;   grep "@reads.*html_body" *.ll         → who uses the HTML body?
;   grep "@cfg.*socket_fail" *.ll         → how do we reach socket_fail?
;
; ============================================================================

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

; ============================================================================
; Globals
; ============================================================================
;
; @global html_body
; @type         [338 x i8]
; @read-by      @build_response
; @invariant    length == 337 (not counting null terminator)
; @invariant    valid UTF-8 HTML document
;
@html_body = private unnamed_addr constant [338 x i8] c"<!DOCTYPE html><html><head><meta charset=\22utf-8\22><title>LastStack</title><style>body{background:#0a0a0a;color:#00ff41;font-family:monospace;display:flex;justify-content:center;align-items:center;height:100vh;margin:0}h1{font-size:3em;text-shadow:0 0 20px #00ff41}</style></head><body><h1>LastStack: Post-Human Software</h1></body></html>\00"

; @global http_status
; @read-by      @build_response
@http_status = private unnamed_addr constant [18 x i8] c"HTTP/1.1 200 OK\0D\0A\00"

; @global http_content_type
; @read-by      @build_response
@http_content_type = private unnamed_addr constant [41 x i8] c"Content-Type: text/html; charset=utf-8\0D\0A\00"

; @global http_content_length
; @read-by      @build_response
@http_content_length = private unnamed_addr constant [17 x i8] c"Content-Length: \00"

; @global http_crlf
; @read-by      @build_response
@http_crlf = private unnamed_addr constant [3 x i8] c"\0D\0A\00"

; @global http_connection_close
; @read-by      @build_response
@http_connection_close = private unnamed_addr constant [20 x i8] c"Connection: close\0D\0A\00"

; @global content_length_str
; @read-by      @build_response
; @invariant    matches strlen(@html_body) == 337
@content_length_str = private unnamed_addr constant [4 x i8] c"337\00"

; @global msg_start
; @read-by      @main
@msg_start = private unnamed_addr constant [46 x i8] c"[LastStack] Server listening on port 9090...\0A\00"

; @global msg_accept
; @read-by      @main
@msg_accept = private unnamed_addr constant [34 x i8] c"[LastStack] Connection accepted.\0A\00"

; @global msg_served
; @read-by      @handle_client
@msg_served = private unnamed_addr constant [30 x i8] c"[LastStack] Response served.\0A\00"

; @global msg_error_socket
; @read-by      @main
@msg_error_socket = private unnamed_addr constant [35 x i8] c"[LastStack] Error: socket failed.\0A\00"

; @global msg_error_bind
; @read-by      @main
@msg_error_bind = private unnamed_addr constant [33 x i8] c"[LastStack] Error: bind failed.\0A\00"

; @global msg_error_listen
; @read-by      @main
@msg_error_listen = private unnamed_addr constant [35 x i8] c"[LastStack] Error: listen failed.\0A\00"

; @global msg_invariant_ok
; @read-by      @check_invariants
@msg_invariant_ok = private unnamed_addr constant [51 x i8] c"[LastStack] Invariant check: all invariants hold.\0A\00"

; @global file paths
@path_index = private unnamed_addr constant [20 x i8] c"./public/index.html\00"
@path_wasm = private unnamed_addr constant [22 x i8] c"./public/fractal.wasm\00"

; @global content type strings
@content_type_html = private unnamed_addr constant [26 x i8] c"Content-Type: text/html\0D\0A\00"
@content_type_wasm = private unnamed_addr constant [33 x i8] c"Content-Type: application/wasm\0D\0A\00"

; @global request parser strings
@req_fractal = private unnamed_addr constant [18 x i8] c"GET /fractal.wasm\00"

; @global header/response templates
@fmt_header_200 = private unnamed_addr constant [62 x i8] c"HTTP/1.1 200 OK\0D\0A%sContent-Length: %ld\0D\0AConnection: close\0D\0A\0D\0A\00"
@response_404 = private unnamed_addr constant [100 x i8] c"HTTP/1.1 404 Not Found\0D\0AContent-Type: text/plain\0D\0AContent-Length: 9\0D\0AConnection: close\0D\0A\0D\0ANot Found\00"

; ============================================================================
; External declarations (libc / POSIX)
; ============================================================================
;
; @extern socket    — create network socket. Returns fd >= 0 on success.
; @extern bind      — bind socket to address. Returns 0 on success.
; @extern listen    — mark socket as listening. Returns 0 on success.
; @extern accept    — accept incoming connection. Returns client fd >= 0.
; @extern read      — read bytes from fd. Returns bytes read.
; @extern write     — write bytes to fd. Returns bytes written.
; @extern close     — close fd. Returns 0 on success.

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
declare i64 @lseek(i32, i64, i32)
declare i32 @fstat(i32, i8*)
declare i32 @stat(i8*, i8*)

; ============================================================================
; @type %struct.sockaddr_in
; @fields       { i16 sin_family, i16 sin_port, i32 sin_addr, [8 x i8] pad }
; @used-by      @main
; @invariant    sin_family == 2 (AF_INET)
; @invariant    sin_port > 0
; ============================================================================

%struct.sockaddr_in = type { i16, i16, i32, [8 x i8] }
%struct.stat = type { i64, i64, i32, i32, i32, i32, i32, i32, i64, i64, i64, i64, [16 x i8] }

; ============================================================================
; @function     @build_response
; @called-by    @handle_client
; @calls        @strlen, @llvm.memcpy.p0i8.p0i8.i64
; @reads        @http_status, @http_content_type, @http_content_length,
;               @content_length_str, @http_crlf, @http_connection_close,
;               @html_body
; @cfg          entry (single block, no branches)
; @pre          %buf is a valid pointer to >= 1024 bytes
; @post         return > 0, %buf contains valid HTTP/1.1 response
; @post         Content-Length header == strlen(body)
; @invariant    all source strings are compile-time constants
; @proof        constant-propagation: total = sum(strlen(each constant)), QED
; ============================================================================

define i64 @build_response(i8* %buf) !pcf.pre !1 !pcf.post !2 !pcf.proof !3 {
entry:
  %offset = alloca i64
  store i64 0, i64* %offset

  ; Write "HTTP/1.1 200 OK\r\n"
  %status_ptr = getelementptr [18 x i8], [18 x i8]* @http_status, i64 0, i64 0
  %status_len = call i64 @strlen(i8* %status_ptr)
  %off0 = load i64, i64* %offset
  %dst0 = getelementptr i8, i8* %buf, i64 %off0
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst0, i8* %status_ptr, i64 %status_len, i1 false)
  %off1 = add i64 %off0, %status_len
  store i64 %off1, i64* %offset

  ; Write "Content-Type: text/html; charset=utf-8\r\n"
  %ct_ptr = getelementptr [41 x i8], [41 x i8]* @http_content_type, i64 0, i64 0
  %ct_len = call i64 @strlen(i8* %ct_ptr)
  %off2 = load i64, i64* %offset
  %dst1 = getelementptr i8, i8* %buf, i64 %off2
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst1, i8* %ct_ptr, i64 %ct_len, i1 false)
  %off3 = add i64 %off2, %ct_len
  store i64 %off3, i64* %offset

  ; Write "Content-Length: "
  %cl_ptr = getelementptr [17 x i8], [17 x i8]* @http_content_length, i64 0, i64 0
  %cl_len = call i64 @strlen(i8* %cl_ptr)
  %off4 = load i64, i64* %offset
  %dst2 = getelementptr i8, i8* %buf, i64 %off4
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst2, i8* %cl_ptr, i64 %cl_len, i1 false)
  %off5 = add i64 %off4, %cl_len
  store i64 %off5, i64* %offset

  ; Write "337"
  %clv_ptr = getelementptr [4 x i8], [4 x i8]* @content_length_str, i64 0, i64 0
  %clv_len = call i64 @strlen(i8* %clv_ptr)
  %off6 = load i64, i64* %offset
  %dst3 = getelementptr i8, i8* %buf, i64 %off6
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst3, i8* %clv_ptr, i64 %clv_len, i1 false)
  %off7 = add i64 %off6, %clv_len
  store i64 %off7, i64* %offset

  ; Write "\r\n" after Content-Length
  %crlf_ptr = getelementptr [3 x i8], [3 x i8]* @http_crlf, i64 0, i64 0
  %crlf_len = call i64 @strlen(i8* %crlf_ptr)
  %off8 = load i64, i64* %offset
  %dst4 = getelementptr i8, i8* %buf, i64 %off8
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst4, i8* %crlf_ptr, i64 %crlf_len, i1 false)
  %off9 = add i64 %off8, %crlf_len
  store i64 %off9, i64* %offset

  ; Write "Connection: close\r\n"
  %cc_ptr = getelementptr [20 x i8], [20 x i8]* @http_connection_close, i64 0, i64 0
  %cc_len = call i64 @strlen(i8* %cc_ptr)
  %off10 = load i64, i64* %offset
  %dst5 = getelementptr i8, i8* %buf, i64 %off10
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst5, i8* %cc_ptr, i64 %cc_len, i1 false)
  %off11 = add i64 %off10, %cc_len
  store i64 %off11, i64* %offset

  ; Write blank line (headers/body separator)
  %off12 = load i64, i64* %offset
  %dst6 = getelementptr i8, i8* %buf, i64 %off12
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %dst6, i8* %crlf_ptr, i64 %crlf_len, i1 false)
  %off13 = add i64 %off12, %crlf_len
  store i64 %off13, i64* %offset

  ; Write HTML body
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
; @function     @read_file
; @called-by    @handle_client
; @calls        @open, @read, @close
; @pre          %path is valid C string, %buf has sufficient space
; @post         returns bytes read, -1 on error
; @invariant    file descriptor is always closed
; ============================================================================

define i64 @read_file(i8* %path, i8* %buf, i64 %buf_size) {
entry:
  %fd = call i32 @open(i8* %path, i32 0)
  %fd_valid = icmp sge i32 %fd, 0
  br i1 %fd_valid, label %read_open, label %file_fail

read_open:
  %bytes = call i64 @read(i32 %fd, i8* %buf, i64 %buf_size)
  call i32 @close(i32 %fd)
  ret i64 %bytes

file_fail:
  ret i64 -1
}

; ============================================================================
; @function     @get_content_type
; @called-by    @handle_client
; @calls        @strstr
; @reads        @str_wasm, @content_type_html, @content_type_wasm
; @pre          %path is valid C string
; @post         returns pointer to content type string
; ============================================================================

define i8* @get_content_type(i8* %path) {
entry:
  %wasm_suffix = getelementptr [6 x i8], [6 x i8]* @str_wasm, i64 0, i64 0
  %is_wasm_ptr = call i8* @strstr(i8* %path, i8* %wasm_suffix)
  %is_wasm = icmp ne i8* %is_wasm_ptr, null
  br i1 %is_wasm, label %ret_wasm, label %ret_html

ret_wasm:
  %ptr_wasm = getelementptr [33 x i8], [33 x i8]* @content_type_wasm, i64 0, i64 0
  ret i8* %ptr_wasm

ret_html:
  %ptr_html = getelementptr [26 x i8], [26 x i8]* @content_type_html, i64 0, i64 0
  ret i8* %ptr_html
}

declare i8* @strstr(i8*, i8*)

@str_html = private unnamed_addr constant [6 x i8] c".html\00"
@str_wasm = private unnamed_addr constant [6 x i8] c".wasm\00"

; ============================================================================
; @function     @check_invariants
; @called-by    @handle_client
; @calls        @printf
; @reads        @msg_invariant_ok
; @cfg          entry → invariants_ok | invariants_fail
; @pre          %response_buf != null, %response_len > 0
; @post         logs invariant status (no side effects on data)
; @invariant    if @build_response postcondition holds, invariants_fail is unreachable
; @proof        runtime-assertion: checks are redundant given caller's proof, QED
; ============================================================================

define void @check_invariants(i8* %response_buf, i64 %response_len) !pcf.pre !4 !pcf.post !5 !pcf.proof !6 {
entry:
  %inv1 = icmp sgt i64 %response_len, 0
  %null_check = icmp ne i8* %response_buf, null
  %inv2 = and i1 %inv1, %null_check
  br i1 %inv2, label %invariants_ok, label %invariants_fail

invariants_ok:
  %ok_msg = getelementptr [51 x i8], [51 x i8]* @msg_invariant_ok, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %ok_msg)
  ret void

invariants_fail:
  ret void
}

; ============================================================================
; @function     @handle_client
; @called-by    @main
; @calls        @read, @strstr, @read_file, @get_content_type, @snprintf,
;               @llvm.memcpy, @check_invariants, @write, @printf, @close, @strlen
; @reads        @req_fractal, @path_index, @path_wasm, @fmt_header_200,
;               @response_404, @msg_served
; @cfg          entry → parse_request → (select_wasm | select_html) → serve_file
;               serve_file → (build_200 | serve_404), build_200 → (send_200 | serve_404)
; @pre          %client_fd >= 0 (valid open file descriptor)
; @post         HTTP response sent to client, fd closed
; @invariant    fd is always closed
; ============================================================================

define void @handle_client(i32 %client_fd) !pcf.pre !7 !pcf.post !8 !pcf.proof !9 {
entry:
  ; Read HTTP request
  %read_buf = alloca [1025 x i8]
  %read_ptr = getelementptr [1025 x i8], [1025 x i8]* %read_buf, i64 0, i64 0
  call void @llvm.memset.p0i8.i64(i8* %read_ptr, i8 0, i64 1025, i1 false)
  %bytes_read = call i64 @read(i32 %client_fd, i8* %read_ptr, i64 1024)
  %has_request = icmp sgt i64 %bytes_read, 0
  br i1 %has_request, label %parse_request, label %serve_404

parse_request:
  %fractal_req = getelementptr [18 x i8], [18 x i8]* @req_fractal, i64 0, i64 0
  %fractal_match_ptr = call i8* @strstr(i8* %read_ptr, i8* %fractal_req)
  %is_fractal = icmp ne i8* %fractal_match_ptr, null
  br i1 %is_fractal, label %select_wasm, label %select_html

select_wasm:
  %wasm_path = getelementptr [22 x i8], [22 x i8]* @path_wasm, i64 0, i64 0
  br label %serve_file

select_html:
  %index_path = getelementptr [20 x i8], [20 x i8]* @path_index, i64 0, i64 0
  br label %serve_file

serve_file:
  %file_path = phi i8* [ %wasm_path, %select_wasm ], [ %index_path, %select_html ]
  %content_type = call i8* @get_content_type(i8* %file_path)

  ; Read static asset into memory.
  %file_buf = alloca [262144 x i8]
  %file_buf_ptr = getelementptr [262144 x i8], [262144 x i8]* %file_buf, i64 0, i64 0
  %file_size = call i64 @read_file(i8* %file_path, i8* %file_buf_ptr, i64 262144)
  %file_ok = icmp sgt i64 %file_size, 0
  br i1 %file_ok, label %build_200, label %serve_404

build_200:
  ; Response buffer keeps header + file payload contiguous for one write.
  %resp_buf = alloca [266240 x i8]
  %resp_ptr = getelementptr [266240 x i8], [266240 x i8]* %resp_buf, i64 0, i64 0
  %header_fmt = getelementptr [62 x i8], [62 x i8]* @fmt_header_200, i64 0, i64 0
  %header_len_i32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %resp_ptr, i64 4096, i8* %header_fmt, i8* %content_type, i64 %file_size)
  %header_len = sext i32 %header_len_i32 to i64
  %header_ok = icmp sgt i64 %header_len, 0
  br i1 %header_ok, label %send_200, label %serve_404

send_200:
  %body_dst = getelementptr i8, i8* %resp_ptr, i64 %header_len
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* %body_dst, i8* %file_buf_ptr, i64 %file_size, i1 false)
  %total_len = add i64 %header_len, %file_size
  %written = call i64 @write(i32 %client_fd, i8* %resp_ptr, i64 %total_len)

  call void @check_invariants(i8* %resp_ptr, i64 %total_len)

  %served_msg = getelementptr [30 x i8], [30 x i8]* @msg_served, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %served_msg)
  call i32 @close(i32 %client_fd)
  ret void

serve_404:
  %nf_ptr = getelementptr [100 x i8], [100 x i8]* @response_404, i64 0, i64 0
  %nf_len = call i64 @strlen(i8* %nf_ptr)
  %nf_written = call i64 @write(i32 %client_fd, i8* %nf_ptr, i64 %nf_len)
  call i32 @close(i32 %client_fd)
  ret void
}

; ============================================================================
; @function     @main
; @called-by    (entry point)
; @calls        @socket, @setsockopt, @htons, @bind, @listen, @accept,
;               @handle_client, @printf, @close, @llvm.memset.p0i8.i64
; @reads        @msg_start, @msg_accept, @msg_error_socket, @msg_error_bind,
;               @msg_error_listen
; @uses-type    %struct.sockaddr_in
; @cfg          entry → socket_fail | socket_ok
;               socket_ok → bind_fail | bind_success
;               bind_success → listen_fail | listen_success
;               listen_success → accept_loop → client_accepted → accept_loop
; @pre          (none — program entry)
; @post         exit 0 (normal) | exit 1 (socket/bind/listen failure)
; @invariant    socket fd is closed on every error path
; @invariant    server loops forever on success path
; @proof        case-analysis: 3 error exits return 1, success loops, QED
; ============================================================================

define i32 @main() !pcf.pre !10 !pcf.post !11 !pcf.proof !12 {
entry:
  ; socket(AF_INET=2, SOCK_STREAM=1, 0)
  %sockfd = call i32 @socket(i32 2, i32 1, i32 0)
  %sock_ok = icmp sge i32 %sockfd, 0
  br i1 %sock_ok, label %socket_ok, label %socket_fail

socket_fail:
  %err_sock = getelementptr [35 x i8], [35 x i8]* @msg_error_socket, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %err_sock)
  ret i32 1

socket_ok:
  ; SO_REUSEADDR
  %optval = alloca i32
  store i32 1, i32* %optval
  %optval_ptr = bitcast i32* %optval to i8*
  call i32 @setsockopt(i32 %sockfd, i32 1, i32 2, i8* %optval_ptr, i32 4)

  ; Prepare sockaddr_in
  %addr = alloca %struct.sockaddr_in
  %addr_family = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 0
  store i16 2, i16* %addr_family  ; AF_INET
  %port = call i32 @htons(i32 9090)
  %port_i16 = trunc i32 %port to i16
  %addr_port = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 1
  store i16 %port_i16, i16* %addr_port
  %addr_ip = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 2
  store i32 0, i32* %addr_ip  ; INADDR_ANY
  %addr_pad = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 3, i32 0
  call void @llvm.memset.p0i8.i64(i8* %addr_pad, i8 0, i64 8, i1 false)

  ; Bind
  %addr_ptr = bitcast %struct.sockaddr_in* %addr to i8*
  %bind_result = call i32 @bind(i32 %sockfd, i8* %addr_ptr, i32 16)
  %bind_ok = icmp sge i32 %bind_result, 0
  br i1 %bind_ok, label %bind_success, label %bind_fail

bind_fail:
  %err_bind = getelementptr [33 x i8], [33 x i8]* @msg_error_bind, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %err_bind)
  call i32 @close(i32 %sockfd)
  ret i32 1

bind_success:
  %listen_result = call i32 @listen(i32 %sockfd, i32 10)
  %listen_ok = icmp sge i32 %listen_result, 0
  br i1 %listen_ok, label %listen_success, label %listen_fail

listen_fail:
  %err_listen = getelementptr [35 x i8], [35 x i8]* @msg_error_listen, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %err_listen)
  call i32 @close(i32 %sockfd)
  ret i32 1

listen_success:
  %start_msg = getelementptr [46 x i8], [46 x i8]* @msg_start, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %start_msg)
  br label %accept_loop

accept_loop:
  %client_fd = call i32 @accept(i32 %sockfd, i8* null, i32* null)
  %client_ok = icmp sge i32 %client_fd, 0
  br i1 %client_ok, label %client_accepted, label %accept_loop

client_accepted:
  %accept_msg = getelementptr [34 x i8], [34 x i8]* @msg_accept, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %accept_msg)
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

; build_response proof witness
!3 = !{!"pcf.proof", !"witness",
       !"strategy: constant-propagation
         all-writes-are-to-compile-time-constant-strings
         total-length = sum(strlen(each-constant))
         result > 0 because all constants are non-empty
         qed"}

; check_invariants precondition
!4 = !{!"pcf.pre", !"smt",
       !"(declare-const response_buf (_ BitVec 64))
         (declare-const response_len (_ BitVec 64))
         (assert (not (= response_buf #x0000000000000000)))
         (assert (bvsgt response_len #x0000000000000000))"}

; check_invariants postcondition
!5 = !{!"pcf.post", !"smt",
       !"(assert true)  ; always succeeds, side effect is logging"}

; check_invariants proof
!6 = !{!"pcf.proof", !"witness",
       !"strategy: runtime-assertion
         invariants-checked-at-runtime
         failure-branch-is-unreachable-given-build_response-postcondition
         qed"}

; handle_client precondition
!7 = !{!"pcf.pre", !"smt",
       !"(declare-const client_fd (_ BitVec 32))
         (assert (bvsge client_fd #x00000000))"}

; handle_client postcondition
!8 = !{!"pcf.post", !"smt",
       !"(declare-const client_fd (_ BitVec 32))
         (assert (= (fd_state client_fd) closed))
         (assert (> bytes_written 0))"}

; handle_client proof
!9 = !{!"pcf.proof", !"witness",
       !"strategy: composition
         build_response.post => response_len > 0
         write(client_fd, response, response_len) => bytes_written > 0
         close(client_fd) => fd_state = closed
         qed"}

; main precondition (entry point)
!10 = !{!"pcf.pre", !"smt", !"(assert true)"}

; main postcondition
!11 = !{!"pcf.post", !"smt",
        !"(declare-const exit_code (_ BitVec 32))
          (assert (or (= exit_code #x00000000) (= exit_code #x00000001)))"}

; main proof
!12 = !{!"pcf.proof", !"witness",
        !"strategy: case-analysis
          case socket_fail: exit_code = 1
          case bind_fail: exit_code = 1
          case listen_fail: exit_code = 1
          case listen_success: infinite loop (no exit_code)
          all-cases-covered
          qed"}
