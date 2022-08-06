prepare_text_wasm :: (data: *u8, count: s64) -> (width: s64) #foreign wasmstub;

prepare_text :: (text: string) -> (width: s64) {
    return prepare_text_wasm(text.data, text.count); 
}

draw_prepared_text_wasm :: (x: s64, y: s64, r: float, g: float, b: float, a: float) #foreign wasmstub;

draw_prepared_text :: (x: s64, y: s64, color: Vector4) {
    draw_prepared_text_wasm(x, y, color.x, color.y, color.z, color.w);
}

wasmstub :: #foreign_library "libwasmstub";

random_get_zero_to_one :: () -> float #foreign wasmstub;
random_get_within_range :: (x: float32, y: float32) -> float #foreign wasmstub;

fill_rect_wasm :: (x: float32, y: float32, w: float32, h: float32,
                   r: float32, g: float32, b: float32, a: float32) #foreign wasmstub;

fill_rect :: (rect: Rect, color: Vector4) {
    fill_rect_wasm(rect.x, rect.y, rect.w, rect.h,
                   color.x, color.y, color.z, color.w);
}

set_context :: (c: *Context) #foreign wasmstub;

__heap_base : *void = null;
heap_size := 0;

set_heap_base :: (heap_base_from_js: *void) #no_context {
    __heap_base = heap_base_from_js;
}

// TODO: heap_base_alloc is really dumb
// It would be interesting to implement a proper malloc on __heap_base
heap_base_alloc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    if mode == {
        case .RESIZE; #through;
        case .ALLOCATE; if (old_size < size) {
            assert(__heap_base != null);
            new_memory := __heap_base + heap_size;
            heap_size += size;
            memcpy(new_memory, old_memory, old_size);
            return new_memory;
        } else {
            return old_memory;
        }
        case .FREE; {
            return null;
        }
    }
}

main :: () {
    set_context(*context);
    context.allocator = .{heap_base_alloc, null};
    init();
}
