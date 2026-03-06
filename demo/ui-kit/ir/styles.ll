; ModuleID = 'tailwind'
source_filename = "tailwind.ll"
target datalayout = "e-m:e-p:32:32-i64:64-n32:64-S128"
target triple = "wasm32-unknown-unknown"

declare i32 @create_element(i32 %tag_ptr, i32 %tag_len)
declare void @append_child(i32 %parent, i32 %child)
declare void @set_text(i32 %node, i32 %text_ptr, i32 %text_len)

@tag_style = private unnamed_addr constant [5 x i8] c"style"

; The raw CSS definitions that exactly match the classes used in components.ll
; This keeps the styling isomorphically derived from the Wasm module.
@css_payload = private unnamed_addr constant [738 x i8] c"
/* Base/Reset */
body { background-color: #f9fafb; color: #0f172a; font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, \22Segoe UI\22, Roboto, \22Helvetica Neue\22, Arial, sans-serif; display: flex; align-items: center; justify-content: center; padding: 2rem; min-height: 100vh; margin: 0; }
* { box-sizing: border-box; }
/* Card */
.bg-white { background-color: #fff; }
.shadow-lg { box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05); }
.rounded-xl { border-radius: 0.75rem; }
.p-8 { padding: 2rem; }
.max-w-md { max-width: 28rem; }
.w-full { width: 100%; }
.mx-auto { margin-left: auto; margin-right: auto; }
.border { border-width: 1px; border-color: #e5e7eb; border-style: solid; }
/* Typography */
.text-2xl { font-size: 1.5rem; line-height: 2rem; }
.font-bold { font-weight: 700; }
.text-gray-900 { color: #111827; }
.mb-6 { margin-bottom: 1.5rem; }
.block { display: block; }
.text-sm { font-size: 0.875rem; line-height: 1.25rem; }
.font-medium { font-weight: 500; }
.text-gray-700 { color: #374151; }
/* Input */
.border-gray-300 { border-color: #d1d5db; }
.rounded-lg { border-radius: 0.5rem; }
.px-4 { padding-left: 1rem; padding-right: 1rem; }
.py-3 { padding-top: 0.75rem; padding-bottom: 0.75rem; }
.focus\\:outline-none:focus { outline: 2px solid transparent; outline-offset: 2px; }
.border-blue-500 { border-color: #3b82f6; }
.ring-2 { box-shadow: 0 0 0 2px #3b82f6; }
.ring-blue-500 { --tw-ring-color: #3b82f6; }
/* Button */
.bg-blue-600 { background-color: #2563eb; }
.bg-blue-700 { background-color: #1d4ed8; }
.text-white { color: #fff; }
.font-semibold { font-weight: 600; }
.shadow-sm { box-shadow: 0 1px 2px 0 rgba(0, 0, 0, 0.05); }
.shadow-md { box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06); }
.mt-4 { margin-top: 1rem; }
button { cursor: pointer; border: none; }
input { outline: none; }
"

; @fn inject_ui_css
; @post "appends a <style> block to root containing all required css class definitions"
define void @inject_ui_css() {
entry:
  %tag_ptr = ptrtoint ptr @tag_style to i32
  %style_node = call i32 @create_element(i32 %tag_ptr, i32 5)
  
  %css_ptr = ptrtoint ptr @css_payload to i32
  call void @set_text(i32 %style_node, i32 %css_ptr, i32 738)
  
  ; Attach to root (handle 1)
  call void @append_child(i32 1, i32 %style_node)
  
  ret void
}
