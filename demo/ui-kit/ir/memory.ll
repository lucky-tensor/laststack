; ModuleID = 'memory'
source_filename = "memory.ll"
target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
target triple = "wasm32-unknown-unknown"

; Simple bump allocator for the Wasm module.
; We reserve the first 1024 bytes for static globals arbitrarily, 
; and start our dynamic heap at 1024.

@heap_ptr = global i32 1024

; @fn alloc
; @post "returns a pointer to 'size' bytes of zeroed linear memory"
; @effects "memory.write"
define i32 @alloc(i32 %size) {
entry:
  %curr = load i32, ptr @heap_ptr, align 4
  %next = add i32 %curr, %size
  store i32 %next, ptr @heap_ptr, align 4

  ; Zero out the allocated memory
  %curr_ptr = inttoptr i32 %curr to ptr
  call void @llvm.memset.p0.i32(ptr %curr_ptr, i8 0, i32 %size, i1 false)
  
  ret i32 %curr
}

; @fn reset_heap
; @post "resets the bump allocator, freeing all dynamic memory"
define void @reset_heap() {
entry:
  store i32 1024, ptr @heap_ptr, align 4
  ret void
}

; Intrinsic for memset
declare void @llvm.memset.p0.i32(ptr nocapture writeonly, i8, i32, i1 immarg)
