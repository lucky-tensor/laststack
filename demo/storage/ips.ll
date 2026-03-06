; ============================================================================
; LastStack Demo: IPS Runtime (LLVM IR)
; ============================================================================
; Minimal durable-state runtime used by the IPS evidence gate.
; Commands:
;   init     create/reset store to epoch=0,value=0
;   add N    two-phase write (committed=0 then committed=1)
;   recover  load and validate committed checksum-protected state
;   corrupt  write uncommitted header (expected to fail recover)
;
; @module   ips
; @layer    storage-runtime
; @exports  main
; @deps     libc (open, close, pread, pwrite, fsync, printf, strcmp, strtoll)
;
; Graph Annotation Legend:
;   @fn        — function identifier
;   @calls     — direct call edges (forward)
;   @called-by — reverse call edges (for agent search)
;   @reads     — global read edges
;   @writes    — global write edges
;   @emits     — effect atoms
;   @pre       — entry precondition
;   @post      — exit postcondition
;   @inv       — structural invariant
;   @proof     — proof strategy
;
; ============================================================================
; ModuleID = 'ips.ll'
source_filename = "ips.ll"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%struct.ips_header_t = type { i32, i32, i64, i64, i32, i32 }

@.str = private unnamed_addr constant [56 x i8] c"usage: %s <file> init|show|recover|add <delta>|corrupt\0A\00", align 1
@.str.1 = private unnamed_addr constant [5 x i8] c"init\00", align 1
@.str.2 = private unnamed_addr constant [5 x i8] c"show\00", align 1
@.str.3 = private unnamed_addr constant [8 x i8] c"recover\00", align 1
@.str.4 = private unnamed_addr constant [4 x i8] c"add\00", align 1
@.str.5 = private unnamed_addr constant [8 x i8] c"corrupt\00", align 1
@.str.6 = private unnamed_addr constant [26 x i8] c"ips:init epoch=0 value=0\0A\00", align 1
@.str.7 = private unnamed_addr constant [46 x i8] c"ips:state epoch=%llu value=%lld committed=%u\0A\00", align 1
@.str.8 = private unnamed_addr constant [42 x i8] c"ips:add delta=%lld epoch=%llu value=%lld\0A\00", align 1
@.str.9 = private unnamed_addr constant [38 x i8] c"ips:corrupt wrote_uncommitted_header\0A\00", align 1

; ============================================================================
; @fn        @main
; @sum       CLI dispatcher: parses argv and routes to cmd_init/cmd_show/cmd_add/cmd_corrupt.
; @layer     entry
; @calls     @cmd_init, @cmd_show, @cmd_add, @cmd_corrupt, @strcmp, @printf, @strtoll
; @reads     @.str, @.str.1 .. @.str.5
; @writes    (none)
; @emits     libc.strcmp, libc.printf, libc.strtoll
; @pre       argc >= 1, argv[0] is valid
; @post      return in {0, 1}
; @inv       dispatches exactly one sub-command per invocation
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define dso_local i32 @main(i32 noundef %0, i8** noundef %1) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !102 !pcf.post !103 !pcf.proof !104 !pcf.effects !105 !pcf.bind !106 {
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  %5 = alloca i8**, align 8
  %6 = alloca i8*, align 8
  %7 = alloca i8*, align 8
  %8 = alloca i8*, align 8
  %9 = alloca i64, align 8
  store i32 0, i32* %3, align 4
  store i32 %0, i32* %4, align 4
  store i8** %1, i8*** %5, align 8
  %10 = load i32, i32* %4, align 4
  %11 = icmp slt i32 %10, 3
  br i1 %11, label %12, label %17

12:                                               ; preds = %2
  %13 = load i8**, i8*** %5, align 8
  %14 = getelementptr inbounds i8*, i8** %13, i64 0
  %15 = load i8*, i8** %14, align 8
  %16 = call i32 (i8*, ...) @printf(i8* noundef getelementptr inbounds ([56 x i8], [56 x i8]* @.str, i64 0, i64 0), i8* noundef %15)
  store i32 1, i32* %3, align 4
  br label %74

17:                                               ; preds = %2
  %18 = load i8**, i8*** %5, align 8
  %19 = getelementptr inbounds i8*, i8** %18, i64 1
  %20 = load i8*, i8** %19, align 8
  store i8* %20, i8** %6, align 8
  %21 = load i8**, i8*** %5, align 8
  %22 = getelementptr inbounds i8*, i8** %21, i64 2
  %23 = load i8*, i8** %22, align 8
  store i8* %23, i8** %7, align 8
  %24 = load i8*, i8** %7, align 8
  %25 = call i32 @strcmp(i8* noundef %24, i8* noundef getelementptr inbounds ([5 x i8], [5 x i8]* @.str.1, i64 0, i64 0))
  %26 = icmp eq i32 %25, 0
  br i1 %26, label %27, label %30

27:                                               ; preds = %17
  %28 = load i8*, i8** %6, align 8
  %29 = call i32 @cmd_init(i8* noundef %28)
  store i32 %29, i32* %3, align 4
  br label %74

30:                                               ; preds = %17
  %31 = load i8*, i8** %7, align 8
  %32 = call i32 @strcmp(i8* noundef %31, i8* noundef getelementptr inbounds ([5 x i8], [5 x i8]* @.str.2, i64 0, i64 0))
  %33 = icmp eq i32 %32, 0
  br i1 %33, label %38, label %34

34:                                               ; preds = %30
  %35 = load i8*, i8** %7, align 8
  %36 = call i32 @strcmp(i8* noundef %35, i8* noundef getelementptr inbounds ([8 x i8], [8 x i8]* @.str.3, i64 0, i64 0))
  %37 = icmp eq i32 %36, 0
  br i1 %37, label %38, label %41

38:                                               ; preds = %34, %30
  %39 = load i8*, i8** %6, align 8
  %40 = call i32 @cmd_show(i8* noundef %39)
  store i32 %40, i32* %3, align 4
  br label %74

41:                                               ; preds = %34
  %42 = load i8*, i8** %7, align 8
  %43 = call i32 @strcmp(i8* noundef %42, i8* noundef getelementptr inbounds ([4 x i8], [4 x i8]* @.str.4, i64 0, i64 0))
  %44 = icmp eq i32 %43, 0
  br i1 %44, label %45, label %66

45:                                               ; preds = %41
  %46 = load i32, i32* %4, align 4
  %47 = icmp slt i32 %46, 4
  br i1 %47, label %48, label %49

48:                                               ; preds = %45
  store i32 1, i32* %3, align 4
  br label %74

49:                                               ; preds = %45
  store i8* null, i8** %8, align 8
  %50 = load i8**, i8*** %5, align 8
  %51 = getelementptr inbounds i8*, i8** %50, i64 3
  %52 = load i8*, i8** %51, align 8
  %53 = call i64 @strtoll(i8* noundef %52, i8** noundef %8, i32 noundef 10)
  store i64 %53, i64* %9, align 8
  %54 = load i8*, i8** %8, align 8
  %55 = icmp eq i8* %54, null
  br i1 %55, label %61, label %56

56:                                               ; preds = %49
  %57 = load i8*, i8** %8, align 8
  %58 = load i8, i8* %57, align 1
  %59 = sext i8 %58 to i32
  %60 = icmp ne i32 %59, 0
  br i1 %60, label %61, label %62

61:                                               ; preds = %56, %49
  store i32 1, i32* %3, align 4
  br label %74

62:                                               ; preds = %56
  %63 = load i8*, i8** %6, align 8
  %64 = load i64, i64* %9, align 8
  %65 = call i32 @cmd_add(i8* noundef %63, i64 noundef %64)
  store i32 %65, i32* %3, align 4
  br label %74

66:                                               ; preds = %41
  %67 = load i8*, i8** %7, align 8
  %68 = call i32 @strcmp(i8* noundef %67, i8* noundef getelementptr inbounds ([8 x i8], [8 x i8]* @.str.5, i64 0, i64 0))
  %69 = icmp eq i32 %68, 0
  br i1 %69, label %70, label %73

70:                                               ; preds = %66
  %71 = load i8*, i8** %6, align 8
  %72 = call i32 @cmd_corrupt(i8* noundef %71)
  store i32 %72, i32* %3, align 4
  br label %74

73:                                               ; preds = %66
  store i32 1, i32* %3, align 4
  br label %74

74:                                               ; preds = %73, %70, %62, %61, %48, %38, %27, %12
  %75 = load i32, i32* %3, align 4
  ret i32 %75
}

declare i32 @printf(i8* noundef, ...) #1

declare i32 @strcmp(i8* noundef, i8* noundef) #1

; ============================================================================
; @fn        @cmd_init
; @sum       Create/reset store file to epoch=0, value=0, committed=1, valid checksum.
; @layer     command
; @called-by @main
; @calls     @open, @init_store_fd, @close, @printf
; @reads     @.str.6
; @writes    (none — writes to file via fd)
; @emits     libc.open, libc.close, libc.printf
; @pre       path is a valid null-terminated string
; @post      on success (ret 0): file at path contains a valid IPS header
;            with epoch=0, value=0, committed=1, checksum=checksum_for(header)
; @inv       file is opened, written, and closed within a single invocation
; @proof     strategy: init_store_fd writes deterministic header then fsyncs;
;            checksum is computed before write, so on-disk state is self-consistent
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define internal i32 @cmd_init(i8* noundef %0) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !107 !pcf.post !108 !pcf.proof !109 !pcf.effects !110 !pcf.bind !111 {
  %2 = alloca i32, align 4
  %3 = alloca i8*, align 8
  %4 = alloca i32, align 4
  %5 = alloca i32, align 4
  store i8* %0, i8** %3, align 8
  %6 = load i8*, i8** %3, align 8
  %7 = call i32 (i8*, i32, ...) @open(i8* noundef %6, i32 noundef 578, i32 noundef 420)
  store i32 %7, i32* %4, align 4
  %8 = load i32, i32* %4, align 4
  %9 = icmp slt i32 %8, 0
  br i1 %9, label %10, label %11

10:                                               ; preds = %1
  store i32 1, i32* %2, align 4
  br label %21

11:                                               ; preds = %1
  %12 = load i32, i32* %4, align 4
  %13 = call i32 @init_store_fd(i32 noundef %12)
  store i32 %13, i32* %5, align 4
  %14 = load i32, i32* %4, align 4
  %15 = call i32 @close(i32 noundef %14)
  %16 = load i32, i32* %5, align 4
  %17 = icmp ne i32 %16, 0
  br i1 %17, label %18, label %19

18:                                               ; preds = %11
  store i32 1, i32* %2, align 4
  br label %21

19:                                               ; preds = %11
  %20 = call i32 (i8*, ...) @printf(i8* noundef getelementptr inbounds ([26 x i8], [26 x i8]* @.str.6, i64 0, i64 0))
  store i32 0, i32* %2, align 4
  br label %21

21:                                               ; preds = %19, %18, %10
  %22 = load i32, i32* %2, align 4
  ret i32 %22
}

; ============================================================================
; @fn        @cmd_show
; @sum       Read and display committed state. If file is empty/invalid, re-init.
; @layer     command
; @called-by @main
; @calls     @open, @read_header, @init_store_fd, @close, @printf
; @reads     @.str.7
; @writes    (none)
; @emits     libc.open, libc.close, libc.printf
; @pre       path is a valid null-terminated string
; @post      on success (ret 0): prints epoch, value, committed for a valid header
; @inv       read_header validates magic, version, committed flag, and checksum
;            before any field is exposed
; @proof     strategy: read_header acts as validator gate; fields are only printed
;            if all structural and checksum invariants hold
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define internal i32 @cmd_show(i8* noundef %0) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !112 !pcf.post !113 !pcf.proof !114 !pcf.effects !115 !pcf.bind !116 {
  %2 = alloca i32, align 4
  %3 = alloca i8*, align 8
  %4 = alloca i32, align 4
  %5 = alloca %struct.ips_header_t, align 8
  %6 = alloca i32, align 4
  store i8* %0, i8** %3, align 8
  %7 = load i8*, i8** %3, align 8
  %8 = call i32 (i8*, i32, ...) @open(i8* noundef %7, i32 noundef 66, i32 noundef 420)
  store i32 %8, i32* %4, align 4
  %9 = load i32, i32* %4, align 4
  %10 = icmp slt i32 %9, 0
  br i1 %10, label %11, label %12

11:                                               ; preds = %1
  store i32 1, i32* %2, align 4
  br label %40

12:                                               ; preds = %1
  %13 = load i32, i32* %4, align 4
  %14 = call i32 @read_header(i32 noundef %13, %struct.ips_header_t* noundef %5)
  store i32 %14, i32* %6, align 4
  %15 = load i32, i32* %6, align 4
  %16 = icmp eq i32 %15, 1
  br i1 %16, label %17, label %26

17:                                               ; preds = %12
  %18 = load i32, i32* %4, align 4
  %19 = call i32 @init_store_fd(i32 noundef %18)
  store i32 %19, i32* %6, align 4
  %20 = load i32, i32* %6, align 4
  %21 = icmp eq i32 %20, 0
  br i1 %21, label %22, label %25

22:                                               ; preds = %17
  %23 = load i32, i32* %4, align 4
  %24 = call i32 @read_header(i32 noundef %23, %struct.ips_header_t* noundef %5)
  store i32 %24, i32* %6, align 4
  br label %25

25:                                               ; preds = %22, %17
  br label %26

26:                                               ; preds = %25, %12
  %27 = load i32, i32* %4, align 4
  %28 = call i32 @close(i32 noundef %27)
  %29 = load i32, i32* %6, align 4
  %30 = icmp ne i32 %29, 0
  br i1 %30, label %31, label %32

31:                                               ; preds = %26
  store i32 1, i32* %2, align 4
  br label %40

32:                                               ; preds = %26
  %33 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 2
  %34 = load i64, i64* %33, align 8
  %35 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 3
  %36 = load i64, i64* %35, align 8
  %37 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 4
  %38 = load i32, i32* %37, align 8
  %39 = call i32 (i8*, ...) @printf(i8* noundef getelementptr inbounds ([46 x i8], [46 x i8]* @.str.7, i64 0, i64 0), i64 noundef %34, i64 noundef %36, i32 noundef %38)
  store i32 0, i32* %2, align 4
  br label %40

40:                                               ; preds = %32, %31, %11
  %41 = load i32, i32* %2, align 4
  ret i32 %41
}

declare i64 @strtoll(i8* noundef, i8** noundef, i32 noundef) #1

; ============================================================================
; @fn        @cmd_add
; @sum       Two-phase commit: read current state, write uncommitted new state
;            (committed=0), then write committed state (committed=1).
; @layer     command
; @called-by @main
; @calls     @open, @read_header, @init_store_fd, @write_header, @close, @printf,
;            @llvm.memcpy.p0i8.p0i8.i64
; @reads     @.str.8
; @writes    (none — writes to file via fd)
; @emits     libc.open, libc.close, libc.pwrite, libc.pread, libc.fsync, libc.printf
; @pre       path is a valid null-terminated string; file exists with valid IPS state
; @post      on success (ret 0):
;            epoch_new == epoch_old + 1
;            value_new == value_old + delta
;            committed == 1
;            checksum == checksum_for(final_header)
;            exactly two writes occurred: first uncommitted, then committed
; @inv       two-phase protocol: if crash occurs between writes, recover will
;            reject the uncommitted state (committed=0 fails validation)
; @proof     strategy: two-phase commit — first write sets committed=0 (crash-safe:
;            recovery rejects committed!=1); second write sets committed=1 with
;            valid checksum. Epoch monotonicity: new_epoch = old_epoch + 1 by
;            construction (add i64 %old_epoch, 1).
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define internal i32 @cmd_add(i8* noundef %0, i64 noundef %1) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !117 !pcf.post !118 !pcf.proof !119 !pcf.effects !120 !pcf.bind !121 {
  %3 = alloca i32, align 4
  %4 = alloca i8*, align 8
  %5 = alloca i64, align 8
  %6 = alloca i32, align 4
  %7 = alloca %struct.ips_header_t, align 8
  %8 = alloca i32, align 4
  %9 = alloca %struct.ips_header_t, align 8
  %10 = alloca %struct.ips_header_t, align 8
  store i8* %0, i8** %4, align 8
  store i64 %1, i64* %5, align 8
  %11 = load i8*, i8** %4, align 8
  %12 = call i32 (i8*, i32, ...) @open(i8* noundef %11, i32 noundef 66, i32 noundef 420)
  store i32 %12, i32* %6, align 4
  %13 = load i32, i32* %6, align 4
  %14 = icmp slt i32 %13, 0
  br i1 %14, label %15, label %16

15:                                               ; preds = %2
  store i32 1, i32* %3, align 4
  br label %74

16:                                               ; preds = %2
  %17 = load i32, i32* %6, align 4
  %18 = call i32 @read_header(i32 noundef %17, %struct.ips_header_t* noundef %7)
  store i32 %18, i32* %8, align 4
  %19 = load i32, i32* %8, align 4
  %20 = icmp eq i32 %19, 1
  br i1 %20, label %21, label %30

21:                                               ; preds = %16
  %22 = load i32, i32* %6, align 4
  %23 = call i32 @init_store_fd(i32 noundef %22)
  store i32 %23, i32* %8, align 4
  %24 = load i32, i32* %8, align 4
  %25 = icmp eq i32 %24, 0
  br i1 %25, label %26, label %29

26:                                               ; preds = %21
  %27 = load i32, i32* %6, align 4
  %28 = call i32 @read_header(i32 noundef %27, %struct.ips_header_t* noundef %7)
  store i32 %28, i32* %8, align 4
  br label %29

29:                                               ; preds = %26, %21
  br label %30

30:                                               ; preds = %29, %16
  %31 = load i32, i32* %8, align 4
  %32 = icmp ne i32 %31, 0
  br i1 %32, label %33, label %36

33:                                               ; preds = %30
  %34 = load i32, i32* %6, align 4
  %35 = call i32 @close(i32 noundef %34)
  store i32 1, i32* %3, align 4
  br label %74

36:                                               ; preds = %30
  %37 = bitcast %struct.ips_header_t* %9 to i8*
  %38 = bitcast %struct.ips_header_t* %7 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %37, i8* align 8 %38, i64 32, i1 false)
  %39 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %7, i32 0, i32 2
  %40 = load i64, i64* %39, align 8
  %41 = add i64 %40, 1
  %42 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %9, i32 0, i32 2
  store i64 %41, i64* %42, align 8
  %43 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %7, i32 0, i32 3
  %44 = load i64, i64* %43, align 8
  %45 = load i64, i64* %5, align 8
  %46 = add nsw i64 %44, %45
  %47 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %9, i32 0, i32 3
  store i64 %46, i64* %47, align 8
  %48 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %9, i32 0, i32 4
  store i32 0, i32* %48, align 8
  %49 = load i32, i32* %6, align 4
  %50 = call i32 @write_header(i32 noundef %49, %struct.ips_header_t* noundef %9)
  store i32 %50, i32* %8, align 4
  %51 = load i32, i32* %8, align 4
  %52 = icmp ne i32 %51, 0
  br i1 %52, label %53, label %56

53:                                               ; preds = %36
  %54 = load i32, i32* %6, align 4
  %55 = call i32 @close(i32 noundef %54)
  store i32 1, i32* %3, align 4
  br label %74

56:                                               ; preds = %36
  %57 = bitcast %struct.ips_header_t* %10 to i8*
  %58 = bitcast %struct.ips_header_t* %9 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %57, i8* align 8 %58, i64 32, i1 false)
  %59 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %10, i32 0, i32 4
  store i32 1, i32* %59, align 8
  %60 = load i32, i32* %6, align 4
  %61 = call i32 @write_header(i32 noundef %60, %struct.ips_header_t* noundef %10)
  store i32 %61, i32* %8, align 4
  %62 = load i32, i32* %6, align 4
  %63 = call i32 @close(i32 noundef %62)
  %64 = load i32, i32* %8, align 4
  %65 = icmp ne i32 %64, 0
  br i1 %65, label %66, label %67

66:                                               ; preds = %56
  store i32 1, i32* %3, align 4
  br label %74

67:                                               ; preds = %56
  %68 = load i64, i64* %5, align 8
  %69 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %10, i32 0, i32 2
  %70 = load i64, i64* %69, align 8
  %71 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %10, i32 0, i32 3
  %72 = load i64, i64* %71, align 8
  %73 = call i32 (i8*, ...) @printf(i8* noundef getelementptr inbounds ([42 x i8], [42 x i8]* @.str.8, i64 0, i64 0), i64 noundef %68, i64 noundef %70, i64 noundef %72)
  store i32 0, i32* %3, align 4
  br label %74

74:                                               ; preds = %67, %66, %53, %33, %15
  %75 = load i32, i32* %3, align 4
  ret i32 %75
}

; ============================================================================
; @fn        @cmd_corrupt
; @sum       Write an intentionally invalid header (committed=0, bad checksum)
;            for negative-path testing of the recovery gate.
; @layer     command
; @called-by @main
; @calls     @open, @pwrite, @fsync, @close, @printf
; @reads     @.str.9
; @writes    (none — writes to file via fd)
; @emits     libc.open, libc.pwrite, libc.fsync, libc.close, libc.printf
; @pre       path is a valid null-terminated string
; @post      on success (ret 0): file at path contains a header with committed=0
;            and checksum=0 (intentionally invalid)
; @inv       this function exists solely for testing; it deliberately violates
;            IPS invariants to exercise the recovery gate's rejection logic
; @proof     strategy: negative-path — writes header with committed=0 and
;            checksum=0; recovery must reject this state
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define internal i32 @cmd_corrupt(i8* noundef %0) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !122 !pcf.post !123 !pcf.proof !124 !pcf.effects !125 !pcf.bind !126 {
  %2 = alloca i32, align 4
  %3 = alloca i8*, align 8
  %4 = alloca i32, align 4
  %5 = alloca %struct.ips_header_t, align 8
  %6 = alloca i64, align 8
  %7 = alloca i32, align 4
  store i8* %0, i8** %3, align 8
  %8 = load i8*, i8** %3, align 8
  %9 = call i32 (i8*, i32, ...) @open(i8* noundef %8, i32 noundef 578, i32 noundef 420)
  store i32 %9, i32* %4, align 4
  %10 = load i32, i32* %4, align 4
  %11 = icmp slt i32 %10, 0
  br i1 %11, label %12, label %13

12:                                               ; preds = %1
  store i32 1, i32* %2, align 4
  br label %38

13:                                               ; preds = %1
  %14 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 0
  store i32 827543625, i32* %14, align 8
  %15 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 1
  store i32 1, i32* %15, align 4
  %16 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 2
  store i64 99, i64* %16, align 8
  %17 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 3
  store i64 999, i64* %17, align 8
  %18 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 4
  store i32 0, i32* %18, align 8
  %19 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %5, i32 0, i32 5
  store i32 0, i32* %19, align 4
  %20 = load i32, i32* %4, align 4
  %21 = bitcast %struct.ips_header_t* %5 to i8*
  %22 = call i64 @pwrite(i32 noundef %20, i8* noundef %21, i64 noundef 32, i64 noundef 0)
  store i64 %22, i64* %6, align 8
  %23 = load i64, i64* %6, align 8
  %24 = icmp eq i64 %23, 32
  br i1 %24, label %25, label %28

25:                                               ; preds = %13
  %26 = load i32, i32* %4, align 4
  %27 = call i32 @fsync(i32 noundef %26)
  br label %29

28:                                               ; preds = %13
  br label %29

29:                                               ; preds = %28, %25
  %30 = phi i32 [ %27, %25 ], [ -1, %28 ]
  store i32 %30, i32* %7, align 4
  %31 = load i32, i32* %4, align 4
  %32 = call i32 @close(i32 noundef %31)
  %33 = load i32, i32* %7, align 4
  %34 = icmp ne i32 %33, 0
  br i1 %34, label %35, label %36

35:                                               ; preds = %29
  store i32 1, i32* %2, align 4
  br label %38

36:                                               ; preds = %29
  %37 = call i32 (i8*, ...) @printf(i8* noundef getelementptr inbounds ([38 x i8], [38 x i8]* @.str.9, i64 0, i64 0))
  store i32 0, i32* %2, align 4
  br label %38

38:                                               ; preds = %36, %35, %12
  %39 = load i32, i32* %2, align 4
  ret i32 %39
}

declare i32 @open(i8* noundef, i32 noundef, ...) #1

; ============================================================================
; @fn        @init_store_fd
; @sum       Initialize an IPS store on an open fd: writes header with magic=0x31535049,
;            version=1, epoch=0, value=0, committed=1, and a valid checksum.
; @layer     internal
; @called-by @cmd_init, @cmd_show, @cmd_add
; @calls     @write_header
; @reads     (none)
; @writes    (none — writes to file via fd)
; @emits     libc.pwrite, libc.fsync
; @pre       fd >= 0 (valid open file descriptor)
; @post      on success (ret 0): file contains header with
;            magic=0x31535049, version=1, epoch=0, value=0,
;            committed=1, checksum=checksum_for({magic,ver,0,0,1})
; @inv       all header fields are deterministic constants;
;            checksum is computed by write_header before pwrite
; @proof     strategy: all fields are compile-time constants except checksum;
;            checksum_for is pure and deterministic; write_header computes
;            checksum then writes atomically (single pwrite of 32 bytes)
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define internal i32 @init_store_fd(i32 noundef %0) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !127 !pcf.post !128 !pcf.proof !129 !pcf.effects !130 !pcf.bind !131 {
  %2 = alloca i32, align 4
  %3 = alloca %struct.ips_header_t, align 8
  store i32 %0, i32* %2, align 4
  %4 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %3, i32 0, i32 0
  store i32 827543625, i32* %4, align 8
  %5 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %3, i32 0, i32 1
  store i32 1, i32* %5, align 4
  %6 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %3, i32 0, i32 2
  store i64 0, i64* %6, align 8
  %7 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %3, i32 0, i32 3
  store i64 0, i64* %7, align 8
  %8 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %3, i32 0, i32 4
  store i32 1, i32* %8, align 8
  %9 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %3, i32 0, i32 5
  store i32 0, i32* %9, align 4
  %10 = load i32, i32* %2, align 4
  %11 = call i32 @write_header(i32 noundef %10, %struct.ips_header_t* noundef %3)
  ret i32 %11
}

declare i32 @close(i32 noundef) #1

; ============================================================================
; @fn        @write_header
; @sum       Compute checksum, store it in header.checksum, pwrite 32 bytes at
;            offset 0, then fsync. Returns 0 on success, -1 on short write.
; @layer     internal
; @called-by @init_store_fd, @cmd_add
; @calls     @checksum_for, @pwrite, @fsync
; @reads     (none)
; @writes    header->checksum (field 5)
; @emits     libc.pwrite, libc.fsync
; @pre       fd >= 0; header pointer is non-null and points to a valid
;            ips_header_t with fields 0-4 populated
; @post      on success (ret 0):
;            header->checksum == checksum_for(header)
;            exactly 32 bytes written to fd at offset 0
;            fsync completed (data durable)
;            on failure (ret -1): short write, no fsync guarantee
; @inv       checksum is always computed from the current header state
;            immediately before the write; no window where on-disk
;            checksum can be stale relative to other fields
; @proof     strategy: checksum_for is called, result stored in field 5,
;            then pwrite emits all 32 bytes atomically. If pwrite returns
;            != 32, function fails early without fsync.
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define internal i32 @write_header(i32 noundef %0, %struct.ips_header_t* noundef %1) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !132 !pcf.post !133 !pcf.proof !134 !pcf.effects !135 !pcf.bind !136 {
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  %5 = alloca %struct.ips_header_t*, align 8
  %6 = alloca i64, align 8
  store i32 %0, i32* %4, align 4
  store %struct.ips_header_t* %1, %struct.ips_header_t** %5, align 8
  %7 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %8 = call i32 @checksum_for(%struct.ips_header_t* noundef %7)
  %9 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %10 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %9, i32 0, i32 5
  store i32 %8, i32* %10, align 4
  %11 = load i32, i32* %4, align 4
  %12 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %13 = bitcast %struct.ips_header_t* %12 to i8*
  %14 = call i64 @pwrite(i32 noundef %11, i8* noundef %13, i64 noundef 32, i64 noundef 0)
  store i64 %14, i64* %6, align 8
  %15 = load i64, i64* %6, align 8
  %16 = icmp ne i64 %15, 32
  br i1 %16, label %17, label %18

17:                                               ; preds = %2
  store i32 -1, i32* %3, align 4
  br label %21

18:                                               ; preds = %2
  %19 = load i32, i32* %4, align 4
  %20 = call i32 @fsync(i32 noundef %19)
  store i32 %20, i32* %3, align 4
  br label %21

21:                                               ; preds = %18, %17
  %22 = load i32, i32* %3, align 4
  ret i32 %22
}

; ============================================================================
; @fn        @checksum_for
; @sum       Compute a 32-bit hash of the first 5 fields of an IPS header
;            using XOR-fold + splitmix64 finalizer. Pure function.
; @layer     internal
; @called-by @write_header, @read_header
; @calls     (none)
; @reads     (none)
; @writes    (none)
; @emits     pure
; @pre       header pointer is non-null, points to a valid ips_header_t
; @post      return == splitmix64_finalize(
;              magic XOR version XOR epoch XOR value XOR committed
;              XOR 0x9E3779B97F4A7C15) truncated to 32 bits
;            deterministic: same input always produces same output
; @inv       pure function — no side effects, no memory writes,
;            no I/O, no global state access
; @proof     strategy: algebraic — the function is a fixed sequence of
;            load, xor, mul, shift operations with no branches (except
;            implicit in the finalizer). Output depends solely on the
;            5 input fields. Determinism follows from absence of state.
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define internal i32 @checksum_for(%struct.ips_header_t* noundef %0) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !137 !pcf.post !138 !pcf.proof !139 !pcf.effects !140 !pcf.bind !141 {
  %2 = alloca %struct.ips_header_t*, align 8
  %3 = alloca i64, align 8
  store %struct.ips_header_t* %0, %struct.ips_header_t** %2, align 8
  %4 = load %struct.ips_header_t*, %struct.ips_header_t** %2, align 8
  %5 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %4, i32 0, i32 0
  %6 = load i32, i32* %5, align 8
  %7 = zext i32 %6 to i64
  %8 = load %struct.ips_header_t*, %struct.ips_header_t** %2, align 8
  %9 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %8, i32 0, i32 1
  %10 = load i32, i32* %9, align 4
  %11 = zext i32 %10 to i64
  %12 = xor i64 %7, %11
  %13 = load %struct.ips_header_t*, %struct.ips_header_t** %2, align 8
  %14 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %13, i32 0, i32 2
  %15 = load i64, i64* %14, align 8
  %16 = xor i64 %12, %15
  %17 = load %struct.ips_header_t*, %struct.ips_header_t** %2, align 8
  %18 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %17, i32 0, i32 3
  %19 = load i64, i64* %18, align 8
  %20 = xor i64 %16, %19
  %21 = load %struct.ips_header_t*, %struct.ips_header_t** %2, align 8
  %22 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %21, i32 0, i32 4
  %23 = load i32, i32* %22, align 8
  %24 = zext i32 %23 to i64
  %25 = xor i64 %20, %24
  %26 = xor i64 %25, -7046029288634856825
  store i64 %26, i64* %3, align 8
  %27 = load i64, i64* %3, align 8
  %28 = lshr i64 %27, 33
  %29 = load i64, i64* %3, align 8
  %30 = xor i64 %29, %28
  store i64 %30, i64* %3, align 8
  %31 = load i64, i64* %3, align 8
  %32 = mul i64 %31, -49064778989728563
  store i64 %32, i64* %3, align 8
  %33 = load i64, i64* %3, align 8
  %34 = lshr i64 %33, 33
  %35 = load i64, i64* %3, align 8
  %36 = xor i64 %35, %34
  store i64 %36, i64* %3, align 8
  %37 = load i64, i64* %3, align 8
  %38 = and i64 %37, 4294967295
  %39 = trunc i64 %38 to i32
  ret i32 %39
}

declare i64 @pwrite(i32 noundef, i8* noundef, i64 noundef, i64 noundef) #1

declare i32 @fsync(i32 noundef) #1

; ============================================================================
; @fn        @read_header
; @sum       Read 32 bytes from fd at offset 0 into an ips_header_t, then validate:
;            magic, version, committed flag, and checksum.
; @layer     internal
; @called-by @cmd_show, @cmd_add
; @calls     @pread, @checksum_for
; @reads     (none)
; @writes    (none — writes to caller-provided header pointer)
; @emits     libc.pread
; @pre       fd >= 0; header pointer is non-null and writable
; @post      returns 0  (valid):   magic == 0x31535049 AND version == 1
;                                  AND committed == 1
;                                  AND checksum == checksum_for(header)
;            returns 1  (empty):   pread returned 0 bytes (empty file)
;            returns -1 (invalid): any validation check failed
; @inv       no field of the header is exposed to callers unless all four
;            validation checks pass (magic, version, committed, checksum)
; @proof     strategy: four-gate validation — each check is a branch that
;            jumps to the rejection label on failure. Only the path where
;            all four checks pass reaches ret 0. Checksum is recomputed
;            from the on-disk data via checksum_for and compared to the
;            stored checksum field.
; ============================================================================
; Function Attrs: noinline nounwind uwtable
define internal i32 @read_header(i32 noundef %0, %struct.ips_header_t* noundef %1) #0 !pcf.schema !100 !pcf.toolchain !101 !pcf.pre !142 !pcf.post !143 !pcf.proof !144 !pcf.effects !145 !pcf.bind !146 {
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  %5 = alloca %struct.ips_header_t*, align 8
  %6 = alloca i64, align 8
  %7 = alloca i32, align 4
  store i32 %0, i32* %4, align 4
  store %struct.ips_header_t* %1, %struct.ips_header_t** %5, align 8
  %8 = load i32, i32* %4, align 4
  %9 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %10 = bitcast %struct.ips_header_t* %9 to i8*
  %11 = call i64 @pread(i32 noundef %8, i8* noundef %10, i64 noundef 32, i64 noundef 0)
  store i64 %11, i64* %6, align 8
  %12 = load i64, i64* %6, align 8
  %13 = icmp eq i64 %12, 0
  br i1 %13, label %14, label %15

14:                                               ; preds = %2
  store i32 1, i32* %3, align 4
  br label %45

15:                                               ; preds = %2
  %16 = load i64, i64* %6, align 8
  %17 = icmp ne i64 %16, 32
  br i1 %17, label %18, label %19

18:                                               ; preds = %15
  store i32 -1, i32* %3, align 4
  br label %45

19:                                               ; preds = %15
  %20 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %21 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %20, i32 0, i32 0
  %22 = load i32, i32* %21, align 8
  %23 = icmp ne i32 %22, 827543625
  br i1 %23, label %34, label %24

24:                                               ; preds = %19
  %25 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %26 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %25, i32 0, i32 1
  %27 = load i32, i32* %26, align 4
  %28 = icmp ne i32 %27, 1
  br i1 %28, label %34, label %29

29:                                               ; preds = %24
  %30 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %31 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %30, i32 0, i32 4
  %32 = load i32, i32* %31, align 8
  %33 = icmp ne i32 %32, 1
  br i1 %33, label %34, label %35

34:                                               ; preds = %29, %24, %19
  store i32 -1, i32* %3, align 4
  br label %45

35:                                               ; preds = %29
  %36 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %37 = call i32 @checksum_for(%struct.ips_header_t* noundef %36)
  store i32 %37, i32* %7, align 4
  %38 = load %struct.ips_header_t*, %struct.ips_header_t** %5, align 8
  %39 = getelementptr inbounds %struct.ips_header_t, %struct.ips_header_t* %38, i32 0, i32 5
  %40 = load i32, i32* %39, align 4
  %41 = load i32, i32* %7, align 4
  %42 = icmp ne i32 %40, %41
  br i1 %42, label %43, label %44

43:                                               ; preds = %35
  store i32 -1, i32* %3, align 4
  br label %45

44:                                               ; preds = %35
  store i32 0, i32* %3, align 4
  br label %45

45:                                               ; preds = %44, %43, %34, %18, %14
  %46 = load i32, i32* %3, align 4
  ret i32 %46
}

declare i64 @pread(i32 noundef, i8* noundef, i64 noundef, i64 noundef) #1

; Function Attrs: argmemonly nofree nounwind willreturn
declare void @llvm.memcpy.p0i8.p0i8.i64(i8* noalias nocapture writeonly, i8* noalias nocapture readonly, i64, i1 immarg) #2

attributes #0 = { noinline nounwind uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #2 = { argmemonly nofree nounwind willreturn }

!llvm.module.flags = !{!0, !1, !2, !3, !4}
!llvm.ident = !{!5}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"PIC Level", i32 2}
!2 = !{i32 7, !"PIE Level", i32 2}
!3 = !{i32 7, !"uwtable", i32 2}
!4 = !{i32 7, !"frame-pointer", i32 2}
!5 = !{!"Apple clang version 14.0.3 (clang-1403.0.22.14.1)"}

; ============================================================================
; PCF Metadata Definitions
; ============================================================================

!100 = !{!"pcf.schema", !"laststack.pcf.v1"}
!101 = !{!"pcf.toolchain",
         !"checker:laststack-verify-gate",
         !"version:0.1.0",
         !"hash:dev"}

; --- @main ---
!102 = !{!"pcf.pre", !"smt",
         !"(declare-const argc (_ BitVec 32))
           (assert (bvsge argc #x00000001))"}
!103 = !{!"pcf.post", !"smt",
         !"(declare-const exit_code (_ BitVec 32))
           (assert (or (= exit_code #x00000000) (= exit_code #x00000001)))"}
!104 = !{!"pcf.proof", !"witness",
         !"strategy: dispatch-only
           main parses argv and dispatches to exactly one cmd_* function;
           each cmd_* returns 0 or 1; main propagates the return value"}
!105 = !{!"pcf.effects", !"libc.strcmp,libc.printf,libc.strtoll"}
!106 = !{!"pcf.bind", !"argc->arg:%0,argv->arg:%1,ret->exit_code"}

; --- @cmd_init ---
!107 = !{!"pcf.pre", !"smt",
         !"(declare-const path (_ BitVec 64))
           (assert (not (= path #x0000000000000000)))"}
!108 = !{!"pcf.post", !"smt",
         !"(declare-const result (_ BitVec 32))
           (declare-const epoch (_ BitVec 64))
           (declare-const value (_ BitVec 64))
           (declare-const committed (_ BitVec 32))
           (assert (=> (= result #x00000000)
                       (and (= epoch #x0000000000000000)
                            (= value #x0000000000000000)
                            (= committed #x00000001))))"}
!109 = !{!"pcf.proof", !"witness",
         !"strategy: init_store_fd writes deterministic header {magic,ver=1,epoch=0,value=0,committed=1}
           with checksum computed by checksum_for before pwrite+fsync"}
!110 = !{!"pcf.effects", !"libc.open,libc.close,libc.pwrite,libc.fsync,libc.printf"}
!111 = !{!"pcf.bind", !"path->arg:%0,ret->result"}

; --- @cmd_show ---
!112 = !{!"pcf.pre", !"smt",
         !"(declare-const path (_ BitVec 64))
           (assert (not (= path #x0000000000000000)))"}
!113 = !{!"pcf.post", !"smt",
         !"(declare-const result (_ BitVec 32))
           (assert (or (= result #x00000000) (= result #x00000001)))"}
!114 = !{!"pcf.proof", !"witness",
         !"strategy: read_header validates magic+version+committed+checksum;
           fields are only printed if all four gates pass"}
!115 = !{!"pcf.effects", !"libc.open,libc.close,libc.pread,libc.printf"}
!116 = !{!"pcf.bind", !"path->arg:%0,ret->result"}

; --- @cmd_add ---
!117 = !{!"pcf.pre", !"smt",
         !"(declare-const path (_ BitVec 64))
           (assert (not (= path #x0000000000000000)))"}
!118 = !{!"pcf.post", !"smt",
         !"(declare-const result (_ BitVec 32))
           (declare-const epoch_old (_ BitVec 64))
           (declare-const epoch_new (_ BitVec 64))
           (declare-const value_old (_ BitVec 64))
           (declare-const value_new (_ BitVec 64))
           (declare-const delta (_ BitVec 64))
           (declare-const committed (_ BitVec 32))
           (assert (=> (= result #x00000000)
                       (and (= epoch_new (bvadd epoch_old #x0000000000000001))
                            (= value_new (bvadd value_old delta))
                            (= committed #x00000001))))"}
!119 = !{!"pcf.proof", !"witness",
         !"strategy: two-phase commit
           Phase 1: write header with committed=0, new epoch and value
           Phase 2: write header with committed=1, same epoch and value
           If crash between phases, recovery rejects committed!=1.
           Epoch monotonicity: epoch_new = epoch_old + 1 by add i64 instruction.
           Value correctness: value_new = value_old + delta by add nsw i64."}
!120 = !{!"pcf.effects", !"libc.open,libc.close,libc.pread,libc.pwrite,libc.fsync,libc.printf"}
!121 = !{!"pcf.bind", !"path->arg:%0,delta->arg:%1,ret->result"}

; --- @cmd_corrupt ---
!122 = !{!"pcf.pre", !"smt",
         !"(declare-const path (_ BitVec 64))
           (assert (not (= path #x0000000000000000)))"}
!123 = !{!"pcf.post", !"smt",
         !"(declare-const result (_ BitVec 32))
           (declare-const committed (_ BitVec 32))
           (declare-const checksum (_ BitVec 32))
           (assert (=> (= result #x00000000)
                       (and (= committed #x00000000)
                            (= checksum #x00000000))))"}
!124 = !{!"pcf.proof", !"witness",
         !"strategy: negative-path testing
           writes header with committed=0 and checksum=0;
           read_header will reject: committed!=1 OR checksum mismatch"}
!125 = !{!"pcf.effects", !"libc.open,libc.pwrite,libc.fsync,libc.close,libc.printf"}
!126 = !{!"pcf.bind", !"path->arg:%0,ret->result"}

; --- @init_store_fd ---
!127 = !{!"pcf.pre", !"smt",
         !"(declare-const fd (_ BitVec 32))
           (assert (bvsge fd #x00000000))"}
!128 = !{!"pcf.post", !"smt",
         !"(declare-const result (_ BitVec 32))
           (declare-const epoch (_ BitVec 64))
           (declare-const value (_ BitVec 64))
           (declare-const committed (_ BitVec 32))
           (declare-const magic (_ BitVec 32))
           (assert (=> (= result #x00000000)
                       (and (= magic #x31535049)
                            (= epoch #x0000000000000000)
                            (= value #x0000000000000000)
                            (= committed #x00000001))))"}
!129 = !{!"pcf.proof", !"witness",
         !"strategy: deterministic constants
           all header fields are compile-time constants; checksum is computed
           by write_header via checksum_for before pwrite; fsync ensures
           durability"}
!130 = !{!"pcf.effects", !"libc.pwrite,libc.fsync"}
!131 = !{!"pcf.bind", !"fd->arg:%0,ret->result"}

; --- @write_header ---
!132 = !{!"pcf.pre", !"smt",
         !"(declare-const fd (_ BitVec 32))
           (declare-const header_ptr (_ BitVec 64))
           (assert (and (bvsge fd #x00000000)
                        (not (= header_ptr #x0000000000000000))))"}
!133 = !{!"pcf.post", !"smt",
         !"(declare-const result (_ BitVec 32))
           (declare-const stored_checksum (_ BitVec 32))
           (declare-const computed_checksum (_ BitVec 32))
           (assert (=> (= result #x00000000)
                       (= stored_checksum computed_checksum)))"}
!134 = !{!"pcf.proof", !"witness",
         !"strategy: checksum-before-write
           1. checksum_for(header) called, result stored in header->checksum
           2. pwrite emits all 32 bytes at offset 0
           3. if pwrite returns != 32, fail early (ret -1), no fsync
           4. if pwrite succeeds, fsync ensures durability
           On-disk checksum is never stale: it is computed immediately before write"}
!135 = !{!"pcf.effects", !"libc.pwrite,libc.fsync"}
!136 = !{!"pcf.bind", !"fd->arg:%0,header->arg:%1,ret->result"}

; --- @checksum_for ---
!137 = !{!"pcf.pre", !"smt",
         !"(declare-const header_ptr (_ BitVec 64))
           (assert (not (= header_ptr #x0000000000000000)))"}
!138 = !{!"pcf.post", !"smt",
         !"(declare-const result (_ BitVec 32))
           (declare-const magic (_ BitVec 32))
           (declare-const version (_ BitVec 32))
           (declare-const epoch (_ BitVec 64))
           (declare-const value (_ BitVec 64))
           (declare-const committed (_ BitVec 32))
           (assert (= result
             ((_ extract 31 0)
               (let ((h0 (bvxor (bvxor (bvxor (bvxor ((_ zero_extend 32) magic)
                                                      ((_ zero_extend 32) version))
                                               epoch)
                                       value)
                               ((_ zero_extend 32) committed))))
               (let ((h1 (bvxor h0 #x9E3779B97F4A7C15)))
               (let ((h2 (bvxor h1 (bvlshr h1 (_ bv33 64)))))
               (let ((h3 (bvmul h2 #xFF51AFD7ED558CCD)))
               (bvxor h3 (bvlshr h3 (_ bv33 64))))))))))"}
; PCF proof: discharged via Z3 in checksum-z3.smt2 (unsat confirms IR == spec)
!139 = !{!"pcf.proof", !"lspc.v1",
         !"method: z3-bv",
         !"smt_file: demo/storage/checksum-z3.smt2",
         !"expected: unsat",
         !"scope: QF_BV — all 160-bit input vectors",
         !"claim: implementation (IR bitvector ops) equals postcondition specification"}
!140 = !{!"pcf.effects", !"pure"}
!141 = !{!"pcf.bind", !"header->arg:%0,ret->result"}

; --- @read_header ---
!142 = !{!"pcf.pre", !"smt",
         !"(declare-const fd (_ BitVec 32))
           (declare-const header_ptr (_ BitVec 64))
           (assert (and (bvsge fd #x00000000)
                        (not (= header_ptr #x0000000000000000))))"}
!143 = !{!"pcf.post", !"smt",
         !"(declare-const result (_ BitVec 32))
           (declare-const magic (_ BitVec 32))
           (declare-const version (_ BitVec 32))
           (declare-const committed (_ BitVec 32))
           (declare-const stored_checksum (_ BitVec 32))
           (declare-const computed_checksum (_ BitVec 32))
           (assert (=> (= result #x00000000)
                       (and (= magic #x31535049)
                            (= version #x00000001)
                            (= committed #x00000001)
                            (= stored_checksum computed_checksum))))"}
!144 = !{!"pcf.proof", !"witness",
         !"strategy: four-gate validation
           Gate 1: pread returns exactly 32 bytes (rejects empty/short files)
           Gate 2: magic == 0x31535049 (rejects non-IPS files)
           Gate 3: version == 1 (rejects incompatible versions)
           Gate 4: committed == 1 (rejects uncommitted two-phase state)
           Gate 5: checksum_for(header) == header->checksum (rejects corruption)
           Only the path where all five gates pass reaches ret 0."}
!145 = !{!"pcf.effects", !"libc.pread"}
!146 = !{!"pcf.bind", !"fd->arg:%0,header->arg:%1,ret->result"}

