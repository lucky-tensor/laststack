; =============================================================================
; LastStack Demo: Plaintext LLVM-IR Server
; =============================================================================
; Minimal single-threaded TCP server responding with constant plaintext payload.
; Designed to mirror TechEmpower plaintext test expectations.
;
; - Listens on port specified by $TFB_PORT, falling back to $PORT then 8080.
; - Responds to any request with HTTP/1.1 200 OK and "Hello, World!" body.
; - No allocation; single shared response buffer.
; - Includes PCF metadata for verification and linking.
;
; =============================================================================

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

%struct.sockaddr_in = type { i16, i16, i32, [8 x i8] }

@plaintext_response = private unnamed_addr constant [108 x i8] c"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: close\r\n\r\nHello, World!\00"
@plaintext_response_len = private unnamed_addr constant i64 108
@env_tfb_port = private unnamed_addr constant [9 x i8] c"TFB_PORT\00"
@env_port = private unnamed_addr constant [5 x i8] c"PORT\00"
@msg_listen = private unnamed_addr constant [48 x i8] c"[LastStack Plaintext] Listening on port %d\n\00"
@msg_socket_fail = private unnamed_addr constant [31 x i8] c"[LastStack Plaintext] socket failed\n\00"
@msg_bind_fail = private unnamed_addr constant [29 x i8] c"[LastStack Plaintext] bind failed\n\00"
@msg_listen_fail = private unnamed_addr constant [31 x i8] c"[LastStack Plaintext] listen failed\n\00"

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
declare i32 @printf(i8*, ...)
declare i8* @getenv(i8*)
declare i32 @atoi(i8*)
declare void @llvm.memcpy.p0i8.p0i8.i64(i8*, i8*, i64, i1)

define void @respond_plaintext(i32 %client_fd) !pcf.schema !30 !pcf.toolchain !31 !pcf.pre !1 !pcf.post !2 !pcf.proof !3 !pcf.effects !4 !pcf.bind !5 {
entry:
  %resp_ptr = getelementptr [97 x i8], [97 x i8]* @plaintext_response, i64 0, i64 0
  call i64 @write(i32 %client_fd, i8* %resp_ptr, i64 108)
  ret void
}

define void @handle_client(i32 %client_fd) !pcf.schema !30 !pcf.toolchain !31 !pcf.pre !6 !pcf.post !7 !pcf.proof !8 !pcf.effects !9 !pcf.bind !10 {
entry:
  %buf = alloca [1024 x i8], align 16
  %buf_ptr = getelementptr [1024 x i8], [1024 x i8]* %buf, i64 0, i64 0
  call i64 @read(i32 %client_fd, i8* %buf_ptr, i64 1024)
  call void @respond_plaintext(i32 %client_fd)
  call i32 @close(i32 %client_fd)
  ret void
}

define i32 @main() !pcf.schema !30 !pcf.toolchain !31 !pcf.pre !11 !pcf.post !12 !pcf.proof !13 !pcf.effects !14 !pcf.bind !15 {
entry:
  %tfb_env = call i8* @getenv(i8* getelementptr inbounds ([9 x i8], [9 x i8]* @env_tfb_port, i32 0, i32 0))
  %tfb_missing = icmp eq i8* %tfb_env, null
  br i1 %tfb_missing, label %port_env_check, label %parse_tfb

parse_tfb:
  %tfb_port = call i32 @atoi(i8* %tfb_env)
  br label %port_ready

port_env_check:
  %port_env = call i8* @getenv(i8* getelementptr inbounds ([5 x i8], [5 x i8]* @env_port, i32 0, i32 0))
  %port_env_missing = icmp eq i8* %port_env, null
  br i1 %port_env_missing, label %use_default_port, label %parse_port_env

parse_port_env:
  %parsed_port = call i32 @atoi(i8* %port_env)
  br label %port_ready

use_default_port:
  br label %port_ready

port_ready:
  %port_phi = phi i32 [8080, %use_default_port], [%parsed_port, %parse_port_env], [%tfb_port, %parse_tfb]
  %sockfd = call i32 @socket(i32 2, i32 1, i32 0)
  %socket_ok = icmp sge i32 %sockfd, 0
  br i1 %socket_ok, label %setup_socket, label %socket_fail

socket_fail:
  call i32 @printf(i8* getelementptr inbounds ([31 x i8], [31 x i8]* @msg_socket_fail, i32 0, i32 0))
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
  call i32 @printf(i8* getelementptr inbounds ([29 x i8], [29 x i8]* @msg_bind_fail, i32 0, i32 0))
  ret i32 1

listen_block:
  %listen_rc = call i32 @listen(i32 %sockfd, i32 4096)
  %listen_ok = icmp eq i32 %listen_rc, 0
  br i1 %listen_ok, label %announce_port, label %listen_fail_block

listen_fail_block:
  call i32 @printf(i8* getelementptr inbounds ([31 x i8], [31 x i8]* @msg_listen_fail, i32 0, i32 0))
  ret i32 1

announce_port:
  call i32 @printf(i8* getelementptr inbounds ([48 x i8], [48 x i8]* @msg_listen, i32 0, i32 0), i32 %port_phi)
  br label %accept_loop

accept_loop:
  %client_fd = call i32 @accept(i32 %sockfd, i8* null, i32* null)
  %client_ok = icmp sge i32 %client_fd, 0
  br i1 %client_ok, label %handle_client_block, label %accept_loop

handle_client_block:
  call void @handle_client(i32 %client_fd)
  br label %accept_loop
}

; PCF metadata definitions

!1 = !{"pcf.pre", !"smt", !"(assert (bvsge client_fd #x00000000))"}
!2 = !{"pcf.post", !"smt", !"(assert true)"}
!3 = !{"pcf.proof", !"witness", !"strategy: constant-response from static buffer"}
!4 = !{"pcf.effects", !"libc.write,global.read:@plaintext_response"}
!5 = !{"pcf.bind", !"client_fd->arg:%client_fd"}

!6 = !{"pcf.pre", !"smt", !"(assert (bvsge client_fd #x00000000))"}
!7 = !{"pcf.post", !"smt", !"(assert true)"}
!8 = !{"pcf.proof", !"witness", !"strategy: read-buff-then-respond-then-close"}
!9 = !{"pcf.effects", !"libc.read,libc.write,libc.close,global.read:@plaintext_response"}
!10 = !{"pcf.bind", !"client_fd->arg:%client_fd"}

!11 = !{"pcf.pre", !"smt", !"(assert true)"}
!12 = !{"pcf.post", !"smt", !"(assert (or (= exit_code #x00000000) (= exit_code #x00000001)))"}
!13 = !{"pcf.proof", !"witness", !"strategy: socket-bind-listen-accept loop"}
!14 = !{"pcf.effects", !"libc.socket,libc.setsockopt,libc.bind,libc.listen,libc.accept,libc.close,libc.printf,libc.getenv,libc.atoi,libc.htons"}
!15 = !{"pcf.bind", !"ret->exit_code"}

!30 = !{"pcf.schema", !"laststack.pcf.v1"}
!31 = !{"pcf.toolchain", !"checker:tfb-plaintext"}
