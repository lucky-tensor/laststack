// laststack.client.abi.v1 shim
// A STRICT ≤50-line microkernel device driver for the browser.

const handles = new Map();
let next_handle = 1;
// Handle 1 is universally mapped to the root mount point.
handles.set(1, document.getElementById('root'));

let wasmExports = null;
let memory = null;
const getStr = (ptr, len) => new TextDecoder('utf-8').decode(new Uint8Array(memory.buffer, ptr, len));
const events = { 1: 'click', 2: 'input', 3: 'mouseenter', 4: 'mouseleave', 5: 'focus', 6: 'blur' };

const env = {
    dom_create: (t_ptr, t_len) => {
        const node = document.createElement(getStr(t_ptr, t_len));
        const handle = ++next_handle;
        handles.set(handle, node);
        return handle;
    },
    dom_append: (parent, child) => handles.get(parent).appendChild(handles.get(child)),
    dom_set_text: (node, p, len) => { handles.get(node).textContent = getStr(p, len); },
    dom_set_attr: (node, k_p, k_l, v_p, v_l) => {
        const key = getStr(k_p, k_l);
        const val = getStr(v_p, v_l);
        if (key === 'value') handles.get(node).value = val; // handle input values
        else handles.get(node).setAttribute(key, val);
    },
    dom_listen: (node_handle, event_id) => {
        const node = handles.get(node_handle);
        node.addEventListener(events[event_id], () => wasmExports.on_event(node_handle, event_id));
    },
    dom_remove: (n) => { handles.get(n).remove(); handles.delete(n); },
    perf_now: () => performance.now(),
    raf_request: (cb_id) => requestAnimationFrame((t) => wasmExports.on_frame(t))
};

// Instantiate and initialize the AI-generated Wasm policy module
WebAssembly.instantiateStreaming(fetch('app.wasm'), { env }).then(res => {
    wasmExports = res.instance.exports;
    memory = wasmExports.memory;
    wasmExports.init();
});
