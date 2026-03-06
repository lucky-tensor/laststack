; ModuleID = 'button'
source_filename = "button.ll"
target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
target triple = "wasm32-unknown-unknown"

declare i32 @dom_create(i32 %tag_ptr, i32 %tag_len)
declare void @dom_append(i32 %parent, i32 %child)
declare void @dom_set_text(i32 %node, i32 %ptr, i32 %len)
declare void @dom_set_attr(i32 %node, i32 %k_ptr, i32 %k_len, i32 %v_ptr, i32 %v_len)

@tag_button = private unnamed_addr constant [6 x i8] c"button"
@text_submit = private unnamed_addr constant [6 x i8] c"Submit"

; Attribute names
@attr_bg = private unnamed_addr constant [10 x i8] c"background"
@attr_color = private unnamed_addr constant [5 x i8] c"color"
@attr_padding = private unnamed_addr constant [7 x i8] c"padding"
@attr_borderRadius = private unnamed_addr constant [12 x i8] c"borderRadius"
@attr_cursor = private unnamed_addr constant [6 x i8] c"cursor"
@attr_display = private unnamed_addr constant [7 x i8] c"display"
@attr_alignItems = private unnamed_addr constant [10 x i8] c"alignItems"
@attr_justifyContent = private unnamed_addr constant [14 x i8] c"justifyContent"
@attr_minHeight = private unnamed_addr constant [9 x i8] c"minHeight"
@attr_margin = private unnamed_addr constant [6 x i8] c"margin"
@attr_backgroundColor = private unnamed_addr constant [16 x i8] c"background-color"

; Attribute values
@val_bg_blue = private unnamed_addr constant [7 x i8] c"#2563eb"
@val_white = private unnamed_addr constant [4 x i8] c"#fff"
@val_flex = private unnamed_addr constant [4 x i8] c"flex"
@val_center = private unnamed_addr constant [6 x i8] c"center"
@val_100vh = private unnamed_addr constant [5 x i8] c"100vh"
@val_0 = private unnamed_addr constant [1 x i8] c"0"
@val_py_px = private unnamed_addr constant [11 x i8] c"0.5rem 1rem"
@val_rounded = private unnamed_addr constant [7 x i8] c"0.25rem"
@val_pointer = private unnamed_addr constant [7 x i8] c"pointer"
@val_bg_gray = private unnamed_addr constant [7 x i8] c"#f9fafb"

define i32 @get_ptr(i8* %str) {
  %ptr = ptrtoint i8* %str to i32
  ret i32 %ptr
}

define void @init() {
entry:
  ; Root (handle 1) is the <body> element
  
  ; body.backgroundColor = #f9fafb
  %bg_ptr = call i32 @get_ptr(i8* getelementptr ([16 x i8], [16 x i8]* @attr_backgroundColor, i32 0, i32 0))
  %bg_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_bg_gray, i32 0, i32 0))
  call void @dom_set_attr(i32 1, i32 %bg_ptr, i32 16, i32 %bg_val, i32 7)
  
  ; body.display = flex
  %disp_ptr = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @attr_display, i32 0, i32 0))
  %disp_val = call i32 @get_ptr(i8* getelementptr ([4 x i8], [4 x i8]* @val_flex, i32 0, i32 0))
  call void @dom_set_attr(i32 1, i32 %disp_ptr, i32 7, i32 %disp_val, i32 4)
  
  ; body.alignItems = center
  %align_ptr = call i32 @get_ptr(i8* getelementptr ([10 x i8], [10 x i8]* @attr_alignItems, i32 0, i32 0))
  %align_val = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @val_center, i32 0, i32 0))
  call void @dom_set_attr(i32 1, i32 %align_ptr, i32 10, i32 %align_val, i32 6)
  
  ; body.justifyContent = center
  %just_ptr = call i32 @get_ptr(i8* getelementptr ([14 x i8], [14 x i8]* @attr_justifyContent, i32 0, i32 0))
  %just_val = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @val_center, i32 0, i32 0))
  call void @dom_set_attr(i32 1, i32 %just_ptr, i32 14, i32 %just_val, i32 6)
  
  ; body.minHeight = 100vh
  %minh_ptr = call i32 @get_ptr(i8* getelementptr ([9 x i8], [9 x i8]* @attr_minHeight, i32 0, i32 0))
  %minh_val = call i32 @get_ptr(i8* getelementptr ([5 x i8], [5 x i8]* @val_100vh, i32 0, i32 0))
  call void @dom_set_attr(i32 1, i32 %minh_ptr, i32 9, i32 %minh_val, i32 5)
  
  ; body.margin = 0
  %marg_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @attr_margin, i32 0, i32 0))
  %marg_val = call i32 @get_ptr(i8* getelementptr ([1 x i8], [1 x i8]* @val_0, i32 0, i32 0))
  call void @dom_set_attr(i32 1, i32 %marg_ptr, i32 6, i32 %marg_val, i32 1)
  
  ; Create button
  %btn_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @tag_button, i32 0, i32 0))
  %button = call i32 @dom_create(i32 %btn_ptr, i32 6)
  
  ; button.textContent = Submit
  %txt_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @text_submit, i32 0, i32 0))
  call void @dom_set_text(i32 %button, i32 %txt_ptr, i32 6)
  
  ; button.backgroundColor = #2563eb
  %btn_bg_ptr = call i32 @get_ptr(i8* getelementptr ([16 x i8], [16 x i8]* @attr_backgroundColor, i32 0, i32 0))
  %btn_bg_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_bg_blue, i32 0, i32 0))
  call void @dom_set_attr(i32 %button, i32 %btn_bg_ptr, i32 16, i32 %btn_bg_val, i32 7)
  
  ; button.color = #fff
  %btn_col_ptr = call i32 @get_ptr(i8* getelementptr ([5 x i8], [5 x i8]* @attr_color, i32 0, i32 0))
  %btn_col_val = call i32 @get_ptr(i8* getelementptr ([4 x i8], [4 x i8]* @val_white, i32 0, i32 0))
  call void @dom_set_attr(i32 %button, i32 %btn_col_ptr, i32 5, i32 %btn_col_val, i32 4)
  
  ; button.padding = 0.5rem 1rem
  %btn_pad_ptr = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @attr_padding, i32 0, i32 0))
  %btn_pad_val = call i32 @get_ptr(i8* getelementptr ([11 x i8], [11 x i8]* @val_py_px, i32 0, i32 0))
  call void @dom_set_attr(i32 %button, i32 %btn_pad_ptr, i32 7, i32 %btn_pad_val, i32 11)
  
  ; button.borderRadius = 0.25rem
  %btn_rad_ptr = call i32 @get_ptr(i8* getelementptr ([12 x i8], [12 x i8]* @attr_borderRadius, i32 0, i32 0))
  %btn_rad_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_rounded, i32 0, i32 0))
  call void @dom_set_attr(i32 %button, i32 %btn_rad_ptr, i32 12, i32 %btn_rad_val, i32 7)
  
  ; button.cursor = pointer
  %btn_cur_ptr = call i32 @get_ptr(i8* getelementptr ([6 x i8], [6 x i8]* @attr_cursor, i32 0, i32 0))
  %btn_cur_val = call i32 @get_ptr(i8* getelementptr ([7 x i8], [7 x i8]* @val_pointer, i32 0, i32 0))
  call void @dom_set_attr(i32 %button, i32 %btn_cur_ptr, i32 6, i32 %btn_cur_val, i32 7)
  
  ; Append button to body
  call void @dom_append(i32 1, i32 %button)
  
  ret void
}

define void @on_event(i32 %node, i32 %event_id) {
entry:
  ret void
}
