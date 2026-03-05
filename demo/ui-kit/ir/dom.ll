; ModuleID = 'dom'
source_filename = "dom.ll"
target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
target triple = "wasm32-unknown-unknown"

; --- External host ABI syscalls ---

declare i32 @dom_create(i32 %tag_ptr, i32 %tag_len)
declare void @dom_append(i32 %parent, i32 %child)
declare void @dom_set_text(i32 %node, i32 %ptr, i32 %len)
declare void @dom_set_attr(i32 %node, i32 %k_ptr, i32 %k_len, i32 %v_ptr, i32 %v_len)
declare void @dom_listen(i32 %node, i32 %event_id)
declare void @dom_remove(i32 %node)
declare double @perf_now()
declare void @raf_request(i32 %cb_id)

; --- Ergonomic Wrappers ---

; @fn create_element
; @pre "tag is a valid string ptr and len > 0"
; @post "returns an opaque DOM handle"
; @effects "dom.create"
define i32 @create_element(i32 %tag_ptr, i32 %tag_len) {
entry:
  %handle = call i32 @dom_create(i32 %tag_ptr, i32 %tag_len)
  ret i32 %handle
}

; @fn append_child
; @effects "dom.mutate"
define void @append_child(i32 %parent, i32 %child) {
entry:
  call void @dom_append(i32 %parent, i32 %child)
  ret void
}

; @fn set_text
; @effects "dom.mutate"
define void @set_text(i32 %node, i32 %text_ptr, i32 %text_len) {
entry:
  call void @dom_set_text(i32 %node, i32 %text_ptr, i32 %text_len)
  ret void
}

; @fn set_attr
; @effects "dom.mutate"
define void @set_attr(i32 %node, i32 %k_ptr, i32 %k_len, i32 %v_ptr, i32 %v_len) {
entry:
  call void @dom_set_attr(i32 %node, i32 %k_ptr, i32 %k_len, i32 %v_ptr, i32 %v_len)
  ret void
}

; @fn listen
; @effects "dom.listen"
define void @listen(i32 %node, i32 %event_id) {
entry:
  call void @dom_listen(i32 %node, i32 %event_id)
  ret void
}
