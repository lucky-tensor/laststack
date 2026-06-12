; =============================================================================
; Alien Stack UI Kit Demo: Button Component (wasm32)
; =============================================================================
; One interactive component rendered and driven entirely from Wasm:
;   init()      — styles the root, creates the button, subscribes to click
;   on_event()  — toggles button state (label + color) on each click
; All interaction state lives in Wasm linear memory (@btn_handle, @clicked).
; The JS shim provides raw DOM syscalls only (alien-stack.client.abi.v1).
;
; @fn        @init        @calls @get_ptr,@dom_create,@dom_set_text,@dom_set_style,@dom_listen,@dom_append
; @fn        @on_event    @calls @get_ptr,@dom_set_text,@dom_set_style
; @fn        @get_ptr     @called-by @init,@on_event
; =============================================================================

; ModuleID = 'button'
source_filename = "button.ll"
target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
target triple = "wasm32-unknown-unknown"

declare i32 @dom_create(i32 %tag_ptr, i32 %tag_len)
declare void @dom_append(i32 %parent, i32 %child)
declare void @dom_set_text(i32 %node, i32 %ptr, i32 %len)
declare void @dom_set_attr(i32 %node, i32 %k_ptr, i32 %k_len, i32 %v_ptr, i32 %v_len)
declare void @dom_set_style(i32 %node, i32 %k_ptr, i32 %k_len, i32 %v_ptr, i32 %v_len)
declare void @dom_listen(i32 %node, i32 %event_id)

; Component state — lives in Wasm linear memory, never in JS
@btn_handle = internal global i32 0
@clicked = internal global i32 0

@tag_button = private unnamed_addr constant [6 x i8] c"button"
@text_submit = private unnamed_addr constant [6 x i8] c"Submit"
@text_clicked = private unnamed_addr constant [8 x i8] c"Clicked!"

; Style property names (CSS kebab-case, applied via dom_set_style)
@attr_color = private unnamed_addr constant [5 x i8] c"color"
@attr_padding = private unnamed_addr constant [7 x i8] c"padding"
@attr_borderRadius = private unnamed_addr constant [13 x i8] c"border-radius"
@attr_border = private unnamed_addr constant [6 x i8] c"border"
@attr_cursor = private unnamed_addr constant [6 x i8] c"cursor"
@attr_display = private unnamed_addr constant [7 x i8] c"display"
@attr_alignItems = private unnamed_addr constant [11 x i8] c"align-items"
@attr_justifyContent = private unnamed_addr constant [15 x i8] c"justify-content"
@attr_minHeight = private unnamed_addr constant [10 x i8] c"min-height"
@attr_margin = private unnamed_addr constant [6 x i8] c"margin"
@attr_backgroundColor = private unnamed_addr constant [16 x i8] c"background-color"

; Style values
@val_bg_blue = private unnamed_addr constant [7 x i8] c"#2563eb"
@val_bg_green = private unnamed_addr constant [7 x i8] c"#16a34a"
@val_white = private unnamed_addr constant [4 x i8] c"#fff"
@val_flex = private unnamed_addr constant [4 x i8] c"flex"
@val_center = private unnamed_addr constant [6 x i8] c"center"
@val_100vh = private unnamed_addr constant [5 x i8] c"100vh"
@val_0 = private unnamed_addr constant [1 x i8] c"0"
@val_none = private unnamed_addr constant [4 x i8] c"none"
@val_py_px = private unnamed_addr constant [11 x i8] c"0.5rem 1rem"
@val_rounded = private unnamed_addr constant [7 x i8] c"0.25rem"
@val_pointer = private unnamed_addr constant [7 x i8] c"pointer"
@val_bg_gray = private unnamed_addr constant [7 x i8] c"#f9fafb"

define i32 @get_ptr(i8* %str) !pcf.schema !1 !pcf.toolchain !2 !pcf.pre !10 !pcf.post !11 !pcf.proof !12 !pcf.effects !13 !pcf.bind !14 {
  %ptr = ptrtoint i8* %str to i32
  ret i32 %ptr
}

define void @init() !pcf.schema !1 !pcf.toolchain !2 !pcf.pre !20 !pcf.post !21 !pcf.proof !22 !pcf.effects !23 !pcf.bind !24 {
entry:
  ; Root (handle 1) is the <body> element

  ; body.background-color = #f9fafb
  %bg_ptr = call i32 @get_ptr(i8* getelementptr ([16 x i8], [16 x i8]* @attr_backgroundColor, i32 0, i32 0))
  %bg_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_bg_gray, i32 0, i32 0))
  call void @dom_set_style(i32 1, i32 %bg_ptr, i32 16, i32 %bg_val, i32 7)

  ; body.display = flex
  %disp_ptr = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @attr_display, i32 0, i32 0))
  %disp_val = call i32 @get_ptr(i8* getelementptr ([4 x i8], [4 x i8]* @val_flex, i32 0, i32 0))
  call void @dom_set_style(i32 1, i32 %disp_ptr, i32 7, i32 %disp_val, i32 4)

  ; body.align-items = center
  %align_ptr = call i32 @get_ptr(i8* getelementptr ([11 x i8], [11 x i8]* @attr_alignItems, i32 0, i32 0))
  %align_val = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @val_center, i32 0, i32 0))
  call void @dom_set_style(i32 1, i32 %align_ptr, i32 11, i32 %align_val, i32 6)

  ; body.justify-content = center
  %just_ptr = call i32 @get_ptr(i8* getelementptr ([15 x i8], [15 x i8]* @attr_justifyContent, i32 0, i32 0))
  %just_val = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @val_center, i32 0, i32 0))
  call void @dom_set_style(i32 1, i32 %just_ptr, i32 15, i32 %just_val, i32 6)

  ; body.min-height = 100vh
  %minh_ptr = call i32 @get_ptr(i8* getelementptr ([10 x i8], [10 x i8]* @attr_minHeight, i32 0, i32 0))
  %minh_val = call i32 @get_ptr(i8* getelementptr ([5 x i8], [5 x i8]* @val_100vh, i32 0, i32 0))
  call void @dom_set_style(i32 1, i32 %minh_ptr, i32 10, i32 %minh_val, i32 5)

  ; body.margin = 0
  %marg_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @attr_margin, i32 0, i32 0))
  %marg_val = call i32 @get_ptr(i8* getelementptr ([1 x i8], [1 x i8]* @val_0, i32 0, i32 0))
  call void @dom_set_style(i32 1, i32 %marg_ptr, i32 6, i32 %marg_val, i32 1)

  ; Create button
  %btn_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @tag_button, i32 0, i32 0))
  %button = call i32 @dom_create(i32 %btn_ptr, i32 6)
  store i32 %button, i32* @btn_handle

  ; button.textContent = Submit
  %txt_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @text_submit, i32 0, i32 0))
  call void @dom_set_text(i32 %button, i32 %txt_ptr, i32 6)

  ; button.background-color = #2563eb
  %btn_bg_ptr = call i32 @get_ptr(i8* getelementptr ([16 x i8], [16 x i8]* @attr_backgroundColor, i32 0, i32 0))
  %btn_bg_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_bg_blue, i32 0, i32 0))
  call void @dom_set_style(i32 %button, i32 %btn_bg_ptr, i32 16, i32 %btn_bg_val, i32 7)

  ; button.color = #fff
  %btn_col_ptr = call i32 @get_ptr(i8* getelementptr ([5 x i8], [5 x i8]* @attr_color, i32 0, i32 0))
  %btn_col_val = call i32 @get_ptr(i8* getelementptr ([4 x i8], [4 x i8]* @val_white, i32 0, i32 0))
  call void @dom_set_style(i32 %button, i32 %btn_col_ptr, i32 5, i32 %btn_col_val, i32 4)

  ; button.padding = 0.5rem 1rem
  %btn_pad_ptr = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @attr_padding, i32 0, i32 0))
  %btn_pad_val = call i32 @get_ptr(i8* getelementptr ([11 x i8], [11 x i8]* @val_py_px, i32 0, i32 0))
  call void @dom_set_style(i32 %button, i32 %btn_pad_ptr, i32 7, i32 %btn_pad_val, i32 11)

  ; button.border-radius = 0.25rem
  %btn_rad_ptr = call i32 @get_ptr(i8* getelementptr ([13 x i8], [13 x i8]* @attr_borderRadius, i32 0, i32 0))
  %btn_rad_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_rounded, i32 0, i32 0))
  call void @dom_set_style(i32 %button, i32 %btn_rad_ptr, i32 13, i32 %btn_rad_val, i32 7)

  ; button.border = none
  %btn_bor_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @attr_border, i32 0, i32 0))
  %btn_bor_val = call i32 @get_ptr(i8* getelementptr ([4 x i8], [4 x i8]* @val_none, i32 0, i32 0))
  call void @dom_set_style(i32 %button, i32 %btn_bor_ptr, i32 6, i32 %btn_bor_val, i32 4)

  ; button.cursor = pointer
  %btn_cur_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @attr_cursor, i32 0, i32 0))
  %btn_cur_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_pointer, i32 0, i32 0))
  call void @dom_set_style(i32 %button, i32 %btn_cur_ptr, i32 6, i32 %btn_cur_val, i32 7)

  ; Subscribe to click (event_id 1) — shim routes back to @on_event
  call void @dom_listen(i32 %button, i32 1)

  ; Append button to body
  call void @dom_append(i32 1, i32 %button)

  ret void
}

define void @on_event(i32 %node, i32 %event_id) !pcf.schema !1 !pcf.toolchain !2 !pcf.pre !30 !pcf.post !31 !pcf.proof !32 !pcf.effects !33 !pcf.bind !34 {
entry:
  ; Only handle click (event_id 1) on the button node
  %is_click = icmp eq i32 %event_id, 1
  br i1 %is_click, label %check_node, label %ignore

check_node:
  %btn = load i32, i32* @btn_handle
  %is_btn = icmp eq i32 %node, %btn
  br i1 %is_btn, label %toggle, label %ignore

toggle:
  %state = load i32, i32* @clicked
  %new_state = xor i32 %state, 1
  store i32 %new_state, i32* @clicked
  %now_clicked = icmp ne i32 %new_state, 0
  br i1 %now_clicked, label %set_clicked, label %set_submit

set_clicked:
  %ctxt_ptr = call i32 @get_ptr(i8* getelementptr ([8 x i8], [8 x i8]* @text_clicked, i32 0, i32 0))
  call void @dom_set_text(i32 %btn, i32 %ctxt_ptr, i32 8)
  %cbg_ptr = call i32 @get_ptr(i8* getelementptr ([16 x i8], [16 x i8]* @attr_backgroundColor, i32 0, i32 0))
  %cbg_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_bg_green, i32 0, i32 0))
  call void @dom_set_style(i32 %btn, i32 %cbg_ptr, i32 16, i32 %cbg_val, i32 7)
  ret void

set_submit:
  %stxt_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @text_submit, i32 0, i32 0))
  call void @dom_set_text(i32 %btn, i32 %stxt_ptr, i32 6)
  %sbg_ptr = call i32 @get_ptr(i8* getelementptr ([16 x i8], [16 x i8]* @attr_backgroundColor, i32 0, i32 0))
  %sbg_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_bg_blue, i32 0, i32 0))
  call void @dom_set_style(i32 %btn, i32 %sbg_ptr, i32 16, i32 %sbg_val, i32 7)
  ret void

ignore:
  ret void
}

; PCF metadata definitions (alienstack.pcf.v1, L1: structural annotation)

!1 = !{!"pcf.schema", !"alienstack.pcf.v1"}
!2 = !{!"pcf.toolchain", !"checker:ui-kit"}

!10 = !{!"pcf.pre", !"smt", !"(assert true)"}
!11 = !{!"pcf.post", !"smt", !"(assert true)"}
!12 = !{!"pcf.proof", !"witness", !"strategy: identity pointer-to-int cast for wasm32 linear-memory addressing"}
!13 = !{!"pcf.effects", !"pure"}
!14 = !{!"pcf.bind", !"str->arg:%str,ret->result"}

!20 = !{!"pcf.pre", !"smt", !"(assert true)"}
!21 = !{!"pcf.post", !"smt", !"(assert true)"}
!22 = !{!"pcf.proof", !"witness", !"strategy: straight-line DOM construction — style root, create button, register click listener, append; stores button handle and initial state (clicked=0) in linear memory"}
!23 = !{!"pcf.effects", !"dom.create,dom.set_text,dom.set_style,dom.listen,dom.append,global.write:@btn_handle,global.read:@tag_button,@text_submit,@attr_backgroundColor,@attr_display,@attr_alignItems,@attr_justifyContent,@attr_minHeight,@attr_margin,@attr_color,@attr_padding,@attr_borderRadius,@attr_border,@attr_cursor,@val_bg_gray,@val_flex,@val_center,@val_100vh,@val_0,@val_bg_blue,@val_white,@val_py_px,@val_rounded,@val_none,@val_pointer"}
!24 = !{!"pcf.bind", !""}

!30 = !{!"pcf.pre", !"smt", !"(assert true)"}
!31 = !{!"pcf.post", !"smt", !"(assert true)"}
!32 = !{!"pcf.proof", !"witness", !"strategy: guarded toggle — non-click events and foreign nodes are ignored; click on the button flips @clicked and rewrites label/background from constants (Submit/#2563eb vs Clicked!/#16a34a)"}
!33 = !{!"pcf.effects", !"dom.set_text,dom.set_style,global.write:@clicked,global.read:@btn_handle,@clicked,@text_submit,@text_clicked,@attr_backgroundColor,@val_bg_blue,@val_bg_green"}
!34 = !{!"pcf.bind", !"node->arg:%node,event_id->arg:%event_id"}
