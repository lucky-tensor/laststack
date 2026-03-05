; ModuleID = 'components'
source_filename = "components.ll"
target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
target triple = "wasm32-unknown-unknown"

declare i32 @create_element(i32 %tag_ptr, i32 %tag_len)
declare void @append_child(i32 %parent, i32 %child)
declare void @set_text(i32 %node, i32 %text_ptr, i32 %text_len)
declare void @set_attr(i32 %node, i32 %k_ptr, i32 %k_len, i32 %v_ptr, i32 %v_len)
declare void @listen(i32 %node, i32 %event_id)

; Element Tags
@tag_div = private unnamed_addr constant [3 x i8] c"div"
@tag_button = private unnamed_addr constant [6 x i8] c"button"
@tag_input = private unnamed_addr constant [5 x i8] c"input"

; Attribute Keys
@attr_class = private unnamed_addr constant [5 x i8] c"class"
@attr_placeholder = private unnamed_addr constant [11 x i8] c"placeholder"
@attr_type = private unnamed_addr constant [4 x i8] c"type"

; Attribute Values
@type_text = private unnamed_addr constant [4 x i8] c"text"

; Tailwind Class Strings (Pixel Perfect Mappings)

; Card length: 66
@class_card = private unnamed_addr constant [66 x i8] c"bg-white shadow-lg rounded-xl p-8 max-w-md w-full mx-auto border\00"

; Button classes
; Normal length: 83
@class_btn_normal = private unnamed_addr constant [83 x i8] c"w-full bg-blue-600 text-white font-semibold py-3 px-4 rounded-lg shadow-sm mt-4\00"
; Hover length: 83
@class_btn_hover = private unnamed_addr constant [83 x i8] c"w-full bg-blue-700 text-white font-semibold py-3 px-4 rounded-lg shadow-md mt-4\00"

; Input classes
; Normal length: 85
@class_input_normal = private unnamed_addr constant [85 x i8] c"w-full border border-gray-300 rounded-lg px-4 py-3 text-gray-900 focus:outline-none\00"
; Focus length: 90
@class_input_focus = private unnamed_addr constant [90 x i8] c"w-full border border-blue-500 ring-2 ring-blue-500 rounded-lg px-4 py-3 focus:outline-none\00"

; Title class
; Length: 39
@class_title = private unnamed_addr constant [39 x i8] c"text-2xl font-bold text-gray-900 mb-6\00"

; Text classes
; Length: 40
@class_label = private unnamed_addr constant [40 x i8] c"block text-sm font-medium text-gray-700\00"

; @fn create_card
define i32 @create_card() {
entry:
  %tag_ptr = ptrtoint ptr @tag_div to i32
  %node = call i32 @create_element(i32 %tag_ptr, i32 3)
  
  %k_ptr = ptrtoint ptr @attr_class to i32
  %v_ptr = ptrtoint ptr @class_card to i32
  call void @set_attr(i32 %node, i32 %k_ptr, i32 5, i32 %v_ptr, i32 65)
  ret i32 %node
}

; @fn create_button
define i32 @create_button(i32 %text_ptr, i32 %text_len) {
entry:
  %tag_ptr = ptrtoint ptr @tag_button to i32
  %node = call i32 @create_element(i32 %tag_ptr, i32 6)
  
  %k_ptr = ptrtoint ptr @attr_class to i32
  %v_ptr = ptrtoint ptr @class_btn_normal to i32
  call void @set_attr(i32 %node, i32 %k_ptr, i32 5, i32 %v_ptr, i32 82)
  
  call void @set_text(i32 %node, i32 %text_ptr, i32 %text_len)
  
  ; Listen: 3=mouseenter, 4=mouseleave, 1=click
  call void @listen(i32 %node, i32 3)
  call void @listen(i32 %node, i32 4)
  call void @listen(i32 %node, i32 1)
  
  ret i32 %node
}

; @fn create_input
define i32 @create_input(i32 %placeholder_ptr, i32 %placeholder_len) {
entry:
  %tag_ptr = ptrtoint ptr @tag_input to i32
  %node = call i32 @create_element(i32 %tag_ptr, i32 5)
  
  ; Type text
  %k_type_ptr = ptrtoint ptr @attr_type to i32
  %v_type_ptr = ptrtoint ptr @type_text to i32
  call void @set_attr(i32 %node, i32 %k_type_ptr, i32 4, i32 %v_type_ptr, i32 4)

  ; Class
  %k_class_ptr = ptrtoint ptr @attr_class to i32
  %v_class_ptr = ptrtoint ptr @class_input_normal to i32
  call void @set_attr(i32 %node, i32 %k_class_ptr, i32 5, i32 %v_class_ptr, i32 84)
  
  ; Placeholder
  %k_ph_ptr = ptrtoint ptr @attr_placeholder to i32
  call void @set_attr(i32 %node, i32 %k_ph_ptr, i32 11, i32 %placeholder_ptr, i32 %placeholder_len)
  
  ; Listen: 5=focus, 6=blur, 2=input
  call void @listen(i32 %node, i32 5)
  call void @listen(i32 %node, i32 6)
  call void @listen(i32 %node, i32 2)
  
  ret i32 %node
}

; @fn apply_title_class
define void @apply_title_class(i32 %node) {
entry:
  %k_ptr = ptrtoint ptr @attr_class to i32
  %v_ptr = ptrtoint ptr @class_title to i32
  call void @set_attr(i32 %node, i32 %k_ptr, i32 5, i32 %v_ptr, i32 38)
  ret void
}

; @fn apply_label_class
define void @apply_label_class(i32 %node) {
entry:
  %k_ptr = ptrtoint ptr @attr_class to i32
  %v_ptr = ptrtoint ptr @class_label to i32
  call void @set_attr(i32 %node, i32 %k_ptr, i32 5, i32 %v_ptr, i32 39)
  ret void
}

; === Event Handlers for Re-styling ===

; @fn handle_mouseenter
define void @handle_mouseenter(i32 %node) {
entry:
  %k_ptr = ptrtoint ptr @attr_class to i32
  %v_ptr = ptrtoint ptr @class_btn_hover to i32
  call void @set_attr(i32 %node, i32 %k_ptr, i32 5, i32 %v_ptr, i32 82)
  ret void
}

; @fn handle_mouseleave
define void @handle_mouseleave(i32 %node) {
entry:
  %k_ptr = ptrtoint ptr @attr_class to i32
  %v_ptr = ptrtoint ptr @class_btn_normal to i32
  call void @set_attr(i32 %node, i32 %k_ptr, i32 5, i32 %v_ptr, i32 82)
  ret void
}

; @fn handle_focus
define void @handle_focus(i32 %node) {
entry:
  %k_ptr = ptrtoint ptr @attr_class to i32
  %v_ptr = ptrtoint ptr @class_input_focus to i32
  call void @set_attr(i32 %node, i32 %k_ptr, i32 5, i32 %v_ptr, i32 89)
  ret void
}

; @fn handle_blur
define void @handle_blur(i32 %node) {
entry:
  %k_ptr = ptrtoint ptr @attr_class to i32
  %v_ptr = ptrtoint ptr @class_input_normal to i32
  call void @set_attr(i32 %node, i32 %k_ptr, i32 5, i32 %v_ptr, i32 84)
  ret void
}
