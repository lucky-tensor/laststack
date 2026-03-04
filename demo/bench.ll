; ============================================================================
; LastStack Demo: HTTP Benchmark Tool
; ============================================================================
;
; @module       bench
; @description  Sequential HTTP benchmark for the LastStack server (or any
;               HTTP/1.1 server on localhost).
; @entry        @main
; @build        demo/build.sh
;
; Usage: ./laststack-bench [port [n_requests]]
;   port         TCP port to connect to (default: 9090)
;   n_requests   Number of sequential GET / requests (default: 1000)
;
; Output:
;   requests  : succeeded / attempted
;   elapsed   : wall-clock milliseconds
;   rps       : requests per second
;   avg       : average latency in microseconds
;
; Navigation convention: same as server.ll — grep @calls/@reads/@cfg.
;
; ============================================================================

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

; ============================================================================
; Types
; ============================================================================

%struct.sockaddr_in = type { i16, i16, i32, [8 x i8] }
%struct.timespec    = type { i64, i64 }

; ============================================================================
; Globals
; ============================================================================

; HTTP GET request (55 bytes incl. null):
;   "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
@http_get    = private unnamed_addr constant [55 x i8] c"GET / HTTP/1.1\0D\0AHost: localhost\0D\0AConnection: close\0D\0A\0D\0A\00"

; Banner / config messages
@msg_banner  = private unnamed_addr constant [34 x i8] c"[bench] LastStack HTTP Benchmark\0A\00"
@msg_target  = private unnamed_addr constant [34 x i8] c"[bench] target    : localhost:%d\0A\00"
@msg_nreqs   = private unnamed_addr constant [24 x i8] c"[bench] requests  : %d\0A\00"
@msg_running = private unnamed_addr constant [20 x i8] c"[bench] running...\0A\00"

; Result messages
@msg_results = private unnamed_addr constant [18 x i8] c"\0A--- Results ---\0A\00"
@msg_req_ok  = private unnamed_addr constant [23 x i8] c"  requests  : %d / %d\0A\00"
@msg_elapsed = private unnamed_addr constant [22 x i8] c"  elapsed   : %ld ms\0A\00"
@msg_rps     = private unnamed_addr constant [19 x i8] c"  rps       : %ld\0A\00"
@msg_avg     = private unnamed_addr constant [22 x i8] c"  avg       : %ld us\0A\00"

; ============================================================================
; External declarations (libc / POSIX)
; ============================================================================

declare i32 @socket(i32, i32, i32)
declare i32 @connect(i32, i8*, i32)
declare i64 @write(i32, i8*, i64)
declare i64 @read(i32, i8*, i64)
declare i32 @close(i32)
declare i32 @clock_gettime(i32, i8*)
declare i32 @printf(i8*, ...)
declare i64 @strlen(i8*)
declare i32 @htons(i32)
declare i32 @atoi(i8*)

; ============================================================================
; @function     @get_time_ns
; @calls        @clock_gettime
; @cfg          entry (single block)
; @post         returns monotonic nanosecond timestamp
; @invariant    CLOCK_MONOTONIC never decreases
; ============================================================================

define i64 @get_time_ns() {
entry:
  %ts     = alloca %struct.timespec
  %ts_ptr = bitcast %struct.timespec* %ts to i8*
  ; CLOCK_MONOTONIC = 1
  call i32 @clock_gettime(i32 1, i8* %ts_ptr)
  %sec_ptr  = getelementptr %struct.timespec, %struct.timespec* %ts, i32 0, i32 0
  %nsec_ptr = getelementptr %struct.timespec, %struct.timespec* %ts, i32 0, i32 1
  %sec    = load i64, i64* %sec_ptr
  %nsec   = load i64, i64* %nsec_ptr
  %sec_ns = mul i64 %sec, 1000000000
  %total  = add i64 %sec_ns, %nsec
  ret i64 %total
}

; ============================================================================
; @function     @make_request
; @calls        @socket, @connect, @htons, @strlen, @write, @read, @close
; @reads        @http_get
; @cfg          entry → do_connect → do_send → done
;               entry → fail_socket
;               do_connect → fail_connect
; @pre          %port > 0
; @post         returns 1 iff any response bytes were received, else 0
; @invariant    socket fd is closed on every exit path
; @proof        case-analysis: do_send closes before ret; fail_connect closes before ret;
;               fail_socket has no fd to close. QED
; ============================================================================

define i32 @make_request(i32 %port) !pcf.pre !1 !pcf.post !2 !pcf.proof !3 {
entry:
  %fd    = call i32 @socket(i32 2, i32 1, i32 0)
  %fd_ok = icmp sge i32 %fd, 0
  br i1 %fd_ok, label %do_connect, label %fail_socket

do_connect:
  %addr     = alloca %struct.sockaddr_in
  %addr_ptr = bitcast %struct.sockaddr_in* %addr to i8*
  call void @llvm.memset.p0i8.i64(i8* %addr_ptr, i8 0, i64 16, i1 false)

  ; sin_family = AF_INET = 2
  %fam_ptr = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 0
  store i16 2, i16* %fam_ptr

  ; sin_port = htons(port)
  %port_net = call i32 @htons(i32 %port)
  %port_i16 = trunc i32 %port_net to i16
  %port_ptr = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 1
  store i16 %port_i16, i16* %port_ptr

  ; sin_addr = 127.0.0.1
  ; Network byte order (big-endian) bytes: 7F 00 00 01
  ; As i32 stored in little-endian memory: 0x0100007F = 16777343
  %ip_ptr = getelementptr %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 2
  store i32 16777343, i32* %ip_ptr

  %conn    = call i32 @connect(i32 %fd, i8* %addr_ptr, i32 16)
  %conn_ok = icmp eq i32 %conn, 0
  br i1 %conn_ok, label %do_send, label %fail_connect

do_send:
  ; Send HTTP GET request
  %req_ptr = getelementptr [55 x i8], [55 x i8]* @http_get, i64 0, i64 0
  %req_len = call i64 @strlen(i8* %req_ptr)
  call i64 @write(i32 %fd, i8* %req_ptr, i64 %req_len)

  ; Read response into stack buffer (server sends Connection: close so one read suffices)
  %resp_buf = alloca [4096 x i8]
  %resp_ptr = getelementptr [4096 x i8], [4096 x i8]* %resp_buf, i64 0, i64 0
  %bytes    = call i64 @read(i32 %fd, i8* %resp_ptr, i64 4096)
  call i32 @close(i32 %fd)

  %got_data = icmp sgt i64 %bytes, 0
  %ret      = zext i1 %got_data to i32
  ret i32 %ret

fail_connect:
  call i32 @close(i32 %fd)
  ret i32 0

fail_socket:
  ret i32 0
}

; ============================================================================
; @function     @run_benchmark
; @calls        @get_time_ns, @make_request, @printf
; @reads        @msg_results, @msg_req_ok, @msg_elapsed, @msg_rps, @msg_avg
; @cfg          entry → bench_loop → bench_body → bench_loop (loop)
;               bench_loop → bench_done (exit)
; @pre          %n_requests > 0, %port > 0
; @post         prints benchmark results to stdout
; @invariant    exactly %n_requests calls to @make_request
; @proof        loop-invariant: i increases by 1 each iteration; terminates at i == n. QED
; ============================================================================

define void @run_benchmark(i32 %n_requests, i32 %port) !pcf.pre !4 !pcf.post !5 !pcf.proof !6 {
entry:
  %start = call i64 @get_time_ns()
  br label %bench_loop

bench_loop:
  %i       = phi i32 [ 0,         %entry      ], [ %i_next,       %bench_body ]
  %success = phi i32 [ 0,         %entry      ], [ %success_next, %bench_body ]
  %done    = icmp sge i32 %i, %n_requests
  br i1 %done, label %bench_done, label %bench_body

bench_body:
  %ok           = call i32 @make_request(i32 %port)
  %i_next       = add i32 %i, 1
  %success_next = add i32 %success, %ok
  br label %bench_loop

bench_done:
  %end        = call i64 @get_time_ns()
  %elapsed_ns = sub i64 %end, %start
  %elapsed_ms = sdiv i64 %elapsed_ns, 1000000

  ; rps = n * 1_000_000_000 / elapsed_ns  (guard: use 1 if elapsed == 0)
  %n64          = sext i32 %n_requests to i64
  %elapsed_pos  = icmp sgt i64 %elapsed_ns, 0
  %safe_elapsed = select i1 %elapsed_pos, i64 %elapsed_ns, i64 1
  %n_giga       = mul i64 %n64, 1000000000
  %rps          = sdiv i64 %n_giga, %safe_elapsed

  ; avg_us = elapsed_ns / (n * 1_000)
  %n_kilo      = mul i64 %n64, 1000
  %n_kilo_pos  = icmp sgt i64 %n_kilo, 0
  %safe_n_kilo = select i1 %n_kilo_pos, i64 %n_kilo, i64 1
  %avg_us      = sdiv i64 %elapsed_ns, %safe_n_kilo

  %p_results = getelementptr [18 x i8], [18 x i8]* @msg_results, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_results)

  %p_req_ok = getelementptr [23 x i8], [23 x i8]* @msg_req_ok, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_req_ok, i32 %success, i32 %n_requests)

  %p_elapsed = getelementptr [22 x i8], [22 x i8]* @msg_elapsed, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_elapsed, i64 %elapsed_ms)

  %p_rps = getelementptr [19 x i8], [19 x i8]* @msg_rps, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_rps, i64 %rps)

  %p_avg = getelementptr [22 x i8], [22 x i8]* @msg_avg, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_avg, i64 %avg_us)

  ret void
}

; ============================================================================
; @function     @main
; @calls        @run_benchmark, @printf, @atoi
; @reads        @msg_banner, @msg_target, @msg_nreqs, @msg_running
; @cfg          entry → check_port → parse_port | use_default_port
;               → check_nreqs → parse_nreqs | use_default_nreqs
;               → start_bench → done
; @pre          (program entry)
; @post         exit 0
; @proof        all paths reach done and return 0. QED
; ============================================================================

define i32 @main(i32 %argc, i8** %argv) !pcf.pre !7 !pcf.post !8 !pcf.proof !9 {
entry:
  br label %check_port

check_port:
  %has_port = icmp sge i32 %argc, 2
  br i1 %has_port, label %parse_port, label %use_default_port

parse_port:
  %argv1_ptr = getelementptr i8*, i8** %argv, i64 1
  %argv1     = load i8*, i8** %argv1_ptr
  %port_raw  = call i32 @atoi(i8* %argv1)
  %port_pos  = icmp sgt i32 %port_raw, 0
  %port_val  = select i1 %port_pos, i32 %port_raw, i32 9090
  br label %check_nreqs

use_default_port:
  br label %check_nreqs

check_nreqs:
  %port      = phi i32 [ %port_val, %parse_port ], [ 9090, %use_default_port ]
  %has_nreqs = icmp sge i32 %argc, 3
  br i1 %has_nreqs, label %parse_nreqs, label %use_default_nreqs

parse_nreqs:
  %argv2_ptr = getelementptr i8*, i8** %argv, i64 2
  %argv2     = load i8*, i8** %argv2_ptr
  %nreqs_raw = call i32 @atoi(i8* %argv2)
  %nreqs_pos = icmp sgt i32 %nreqs_raw, 0
  %nreqs_val = select i1 %nreqs_pos, i32 %nreqs_raw, i32 1000
  br label %start_bench

use_default_nreqs:
  br label %start_bench

start_bench:
  %nreqs = phi i32 [ %nreqs_val, %parse_nreqs ], [ 1000, %use_default_nreqs ]

  %p_banner = getelementptr [34 x i8], [34 x i8]* @msg_banner, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_banner)

  %p_target = getelementptr [34 x i8], [34 x i8]* @msg_target, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_target, i32 %port)

  %p_nreqs = getelementptr [24 x i8], [24 x i8]* @msg_nreqs, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_nreqs, i32 %nreqs)

  %p_running = getelementptr [20 x i8], [20 x i8]* @msg_running, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %p_running)

  call void @run_benchmark(i32 %nreqs, i32 %port)
  ret i32 0
}

; ============================================================================
; LLVM intrinsics
; ============================================================================

declare void @llvm.memset.p0i8.i64(i8* nocapture writeonly, i8, i64, i1 immarg)

; ============================================================================
; PCF Metadata
; ============================================================================

; make_request precondition
!1 = !{!"pcf.pre", !"smt",
       !"(declare-const port (_ BitVec 32))
         (assert (bvsgt port #x00000000))"}

; make_request postcondition
!2 = !{!"pcf.post", !"smt",
       !"(declare-const result (_ BitVec 32))
         (declare-const client_fd (_ BitVec 32))
         (assert (or (= result #x00000000) (= result #x00000001)))
         (assert (= (fd_state client_fd) closed))"}

; make_request proof
!3 = !{!"pcf.proof", !"witness",
       !"strategy: case-analysis
         case fail_socket: no fd created, return 0
         case fail_connect: close(fd) before return 0
         case do_send: close(fd) before return ok-bit
         all-cases-covered, fd-always-closed
         qed"}

; run_benchmark precondition
!4 = !{!"pcf.pre", !"smt",
       !"(declare-const n_requests (_ BitVec 32))
         (declare-const port (_ BitVec 32))
         (assert (bvsgt n_requests #x00000000))
         (assert (bvsgt port #x00000000))"}

; run_benchmark postcondition
!5 = !{!"pcf.post", !"smt",
       !"(assert true)  ; side effect: results printed to stdout"}

; run_benchmark proof
!6 = !{!"pcf.proof", !"witness",
       !"strategy: loop-invariant
         invariant: i in [0, n_requests], success in [0, i]
         termination: i increments by 1 each iteration, bounded by n_requests
         qed"}

; main precondition
!7 = !{!"pcf.pre", !"smt", !"(assert true)"}

; main postcondition
!8 = !{!"pcf.post", !"smt",
       !"(declare-const exit_code (_ BitVec 32))
         (assert (= exit_code #x00000000))"}

; main proof
!9 = !{!"pcf.proof", !"witness",
       !"strategy: case-analysis
         all arg-parse paths lead to start_bench
         start_bench calls run_benchmark then returns 0
         qed"}
