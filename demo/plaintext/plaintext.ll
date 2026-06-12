; =============================================================================
; Alien Stack Demo: Plaintext LLVM-IR Server
; =============================================================================
; Minimal single-threaded TCP server responding with constant plaintext payload.
; Designed to mirror TechEmpower plaintext test expectations.
;
; - Listens on fixed port 18081.
; - Responds to any request with HTTP/1.1 200 OK and "Hello, World!" body.
; - No allocation; single shared response buffer.
; - Includes PCF metadata for verification and linking.
;
; =============================================================================

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

%struct.sockaddr_in = type { i16, i16, i32, [8 x i8] }

@plaintext_response = private unnamed_addr constant [97 x i8] c"HTTP/1.1 200 OK\0D\0AContent-Type: text/plain\0D\0AContent-Length: 13\0D\0AConnection: close\0D\0A\0D\0AHello, World!"
@plaintext_response_len = private unnamed_addr constant i64 97

; External dependencies (libc / syscalls)
declare i32 @socket(i32, i32, i32)
declare i32 @setsockopt(i32, i32, i32, i8*, i32)
declare i32 @bind(i32, i8*, i32)
declare i32 @listen(i32, i32)
declare i32 @accept(i32, i8*, i32*)
declare i64 @read(i32, i8*, i64)
declare i64 @write(i32, i8*, i64)
declare i32 @close(i32)
declare i32 @htons(i32)
declare i32 @usleep(i32)
declare void @llvm.memcpy.p0i8.p0i8.i64(i8*, i8*, i64, i1)

define i64 @respond_plaintext(i32 %client_fd) !pcf.schema !30 !pcf.toolchain !31 !pcf.pre !1 !pcf.post !2 !pcf.proof !3 !pcf.effects !4 !pcf.bind !5 {
entry:
  %resp_ptr = getelementptr [97 x i8], [97 x i8]* @plaintext_response, i64 0, i64 0
  %written = call i64 @write(i32 %client_fd, i8* %resp_ptr, i64 97)
  ret i64 %written
}

define void @handle_client(i32 %client_fd) !pcf.schema !30 !pcf.toolchain !31 !pcf.pre !6 !pcf.post !7 !pcf.proof !8 !pcf.effects !9 !pcf.bind !10 {
entry:
  %buf = alloca [1024 x i8], align 16
  %buf_ptr = getelementptr [1024 x i8], [1024 x i8]* %buf, i64 0, i64 0
  call i64 @read(i32 %client_fd, i8* %buf_ptr, i64 1024)
  ; write result is observed but does not change control flow: the connection
  ; is closed on every path (short write / EPIPE simply ends this client)
  %wrc = call i64 @respond_plaintext(i32 %client_fd)
  call i32 @close(i32 %client_fd)
  ret void
}

define i32 @main() !pcf.schema !30 !pcf.toolchain !31 !pcf.pre !11 !pcf.post !12 !pcf.proof !13 !pcf.effects !14 !pcf.bind !15 {
entry:
  br label %port_ready

port_ready:
  %port_phi = add i32 18081, 0
  %sockfd = call i32 @socket(i32 2, i32 1, i32 0)
  %socket_ok = icmp sge i32 %sockfd, 0
  br i1 %socket_ok, label %setup_socket, label %socket_fail

socket_fail:
  ret i32 1

setup_socket:
  %reuse = alloca i32, align 4
  store i32 1, i32* %reuse
  %reuse_ptr = bitcast i32* %reuse to i8*
  call i32 @setsockopt(i32 %sockfd, i32 1, i32 2, i8* %reuse_ptr, i32 4)
  %addr = alloca %struct.sockaddr_in, align 4
  %family_ptr = getelementptr inbounds %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 0
  store i16 2, i16* %family_ptr
  %port_htons = call i32 @htons(i32 %port_phi)
  %port_trunc = trunc i32 %port_htons to i16
  %port_ptr = getelementptr inbounds %struct.sockaddr_in, %struct.sockaddr_in* %addr, i32 0, i32 1
  store i16 %port_trunc, i16* %port_ptr
  %addr_i8 = bitcast %struct.sockaddr_in* %addr to i8*
  %bind_rc = call i32 @bind(i32 %sockfd, i8* %addr_i8, i32 16)
  %bind_ok = icmp eq i32 %bind_rc, 0
  br i1 %bind_ok, label %listen_block, label %bind_fail

bind_fail:
  ret i32 1

listen_block:
  %listen_rc = call i32 @listen(i32 %sockfd, i32 4096)
  %listen_ok = icmp eq i32 %listen_rc, 0
  br i1 %listen_ok, label %announce_port, label %listen_fail_block

listen_fail_block:
  ret i32 1

announce_port:
  br label %accept_loop

accept_loop:
  ; %fail_count tracks consecutive accept() failures; a healthy accept resets
  ; it to 0. Persistent failure (e.g. EMFILE, dead socket) terminates the
  ; server instead of spinning in a busy-loop.
  %fail_count = phi i32 [ 0, %announce_port ], [ 0, %handle_client_block ], [ %fail_next, %accept_backoff ]
  %client_fd = call i32 @accept(i32 %sockfd, i8* null, i32* null)
  %client_ok = icmp sge i32 %client_fd, 0
  br i1 %client_ok, label %handle_client_block, label %accept_fail

accept_fail:
  %fail_next = add i32 %fail_count, 1
  %give_up = icmp uge i32 %fail_next, 1024
  br i1 %give_up, label %accept_exhausted, label %accept_backoff

accept_backoff:
  ; 10ms backoff between failed accepts: avoids pegging the CPU on transient
  ; failures (e.g. EMFILE) while bounding total retry time to ~10s
  call i32 @usleep(i32 10000)
  br label %accept_loop

accept_exhausted:
  call i32 @close(i32 %sockfd)
  ret i32 1

handle_client_block:
  call void @handle_client(i32 %client_fd)
  br label %accept_loop
}

; PCF metadata definitions

!1 = !{!"pcf.pre", !"smt", !"(assert (bvsge client_fd #x00000000))"}
!2 = !{!"pcf.post", !"smt", !"(assert (or (= result #x0000000000000061) (bvslt result #x0000000000000061)))"}
!3 = !{!"pcf.proof", !"witness", !"strategy: constant-response from static buffer; returns write() result (97 on full write, fewer or -1 on short write/error) so callers can observe delivery"}
!4 = !{!"pcf.effects", !"libc.write,global.read:@plaintext_response"}
!5 = !{!"pcf.bind", !"client_fd->arg:%client_fd,ret->result"}

!6 = !{!"pcf.pre", !"smt", !"(assert (bvsge client_fd #x00000000))"}
!7 = !{!"pcf.post", !"smt", !"(assert true)"}
!8 = !{!"pcf.proof", !"witness", !"strategy: read-buff-then-respond-then-close; client_fd is closed on every path regardless of write outcome"}
!9 = !{!"pcf.effects", !"libc.read,libc.write,libc.close,global.read:@plaintext_response"}
!10 = !{!"pcf.bind", !"client_fd->arg:%client_fd"}

!11 = !{!"pcf.pre", !"smt", !"(assert true)"}
!12 = !{!"pcf.post", !"smt", !"(assert (or (= exit_code #x00000000) (= exit_code #x00000001)))"}
!13 = !{!"pcf.proof", !"witness", !"strategy: socket-bind-listen-accept loop; consecutive accept() failures back off 10ms each (usleep) and the server exits 1 (closing the listen socket) after 1024 in a row instead of busy-looping"}
!14 = !{!"pcf.effects", !"libc.socket,libc.setsockopt,libc.bind,libc.listen,libc.accept,libc.close,libc.htons,libc.usleep"}
!15 = !{!"pcf.bind", !"ret->exit_code"}

!30 = !{!"pcf.schema", !"alienstack.pcf.v1"}
!31 = !{!"pcf.toolchain", !"checker:tfb-plaintext"}
