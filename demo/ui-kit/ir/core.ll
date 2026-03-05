; ModuleID = 'core'
source_filename = "core.ll"
target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
target triple = "wasm32-unknown-unknown"

; PCF Metadata Block
; pcf.schema: laststack.pcf.v1
; pcf.toolchain: clang-wasm32

; External declarations
declare i32 @create_element(i32 %tag_ptr, i32 %tag_len)
declare void @append_child(i32 %parent, i32 %child)
declare void @set_text(i32 %node, i32 %text_ptr, i32 %text_len)
declare void @set_attr(i32 %node, i32 %k_ptr, i32 %k_len, i32 %v_ptr, i32 %v_len)
declare void @listen(i32 %node, i32 %event_id)

; Constants
@tag_div = private unnamed_addr constant [3 x i8] c"div"
@tag_h1 = private unnamed_addr constant [2 x i8] c"h1"
@text_title = private unnamed_addr constant [27 x i8] c"Homomorphic UI Kit Demo     "

declare i32 @create_card()
declare i32 @create_button(i32 %text_ptr, i32 %text_len)
declare i32 @create_input(i32 %placeholder_ptr, i32 %placeholder_len)
declare void @apply_title_class(i32 %node)
declare void @apply_label_class(i32 %node)
declare void @handle_mouseenter(i32 %node)
declare void @handle_mouseleave(i32 %node)
declare void @handle_focus(i32 %node)
declare void @handle_blur(i32 %node)

@text_btn = private unnamed_addr constant [13 x i8] c"Submit Action"
@text_ph = private unnamed_addr constant [18 x i8] c"Enter your email..."
@text_lbl = private unnamed_addr constant [14 x i8] c"Email Address"
@tag_label = private unnamed_addr constant [5 x i8] c"label"

declare void @inject_ui_css()

; @fn init
; @pre "DOM and Wasm instantiated"
; @post "initial application state and DOM tree is built"
; @effects "dom.create dom.mutate dom.listen"
; @export
define void @init() {
entry:
  ; Root node is implicitly handle 1.

  ; Inject Wasm-generated CSS directly into the DOM
  call void @inject_ui_css()

  ; Create the main Card container
  %card = call i32 @create_card()
  call void @append_child(i32 1, i32 %card)

  ; Create and append Title
  %h1_ptr = ptrtoint ptr @tag_h1 to i32
  %title = call i32 @create_element(i32 %h1_ptr, i32 2)
  %title_txt_ptr = ptrtoint ptr @text_title to i32
  call void @set_text(i32 %title, i32 %title_txt_ptr, i32 27)
  call void @apply_title_class(i32 %title)
  call void @append_child(i32 %card, i32 %title)
  
  ; Create and append Label
  %lbl_tag_ptr = ptrtoint ptr @tag_label to i32
  %lbl = call i32 @create_element(i32 %lbl_tag_ptr, i32 5)
  %lbl_txt_ptr = ptrtoint ptr @text_lbl to i32
  call void @set_text(i32 %lbl, i32 %lbl_txt_ptr, i32 13)
  call void @apply_label_class(i32 %lbl)
  call void @append_child(i32 %card, i32 %lbl)

  ; Create margin wrapper for input
  %div_ptr = ptrtoint ptr @tag_div to i32
  %input_wrap = call i32 @create_element(i32 %div_ptr, i32 3)
  call void @append_child(i32 %card, i32 %input_wrap)

  ; Create and append Input
  %ph_txt_ptr = ptrtoint ptr @text_ph to i32
  %input = call i32 @create_input(i32 %ph_txt_ptr, i32 18)
  call void @append_child(i32 %input_wrap, i32 %input)

  ; Create and append Button
  %btn_txt_ptr = ptrtoint ptr @text_btn to i32
  %btn = call i32 @create_button(i32 %btn_txt_ptr, i32 13)
  call void @append_child(i32 %card, i32 %btn)

  ret void
}

; @fn on_event
; @pre "node handle is valid, event_id matches ABI mapping"
; @post "internal state updated, DOM conditionally mutated"
; @effects "dom.mutate"
; @export
define void @on_event(i32 %node, i32 %event_id) {
entry:
  ; 3 = mouseenter
  %is_mouseenter = icmp eq i32 %event_id, 3
  br i1 %is_mouseenter, label %do_mouseenter, label %chk_mouseleave
  
do_mouseenter:
  call void @handle_mouseenter(i32 %node)
  ret void
  
chk_mouseleave:
  ; 4 = mouseleave
  %is_mouseleave = icmp eq i32 %event_id, 4
  br i1 %is_mouseleave, label %do_mouseleave, label %chk_focus
  
do_mouseleave:
  call void @handle_mouseleave(i32 %node)
  ret void
  
chk_focus:
  ; 5 = focus
  %is_focus = icmp eq i32 %event_id, 5
  br i1 %is_focus, label %do_focus, label %chk_blur
  
do_focus:
  call void @handle_focus(i32 %node)
  ret void
  
chk_blur:
  ; 6 = blur
  %is_blur = icmp eq i32 %event_id, 6
  br i1 %is_blur, label %do_blur, label %done
  
do_blur:
  call void @handle_blur(i32 %node)
  ret void

done:
  ret void
}
