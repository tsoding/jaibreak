platform_prepare_text :: (data: *u8, count: s64) -> (width: s64) #foreign wasmstub;

prepare_text :: (text: string) -> (width: s64) {
    return platform_prepare_text(text.data, text.count); //platform_prepare_text(text.data, text.count);
}

platform_draw_prepared_text :: (x: s64, y: s64, r: float, g: float, b: float, a: float) #foreign wasmstub;

draw_prepared_text :: (x: s64, y: s64, color: Vector4) {
    platform_draw_prepared_text(x, y, color.x, color.y, color.z, color.w);
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

main :: () {
    set_context(*context);
    init_state();
    // NOTE: we call this function in here so it does not get DCE-ed, because we call it from JavaScript from time to time.
    // TODO: maybe reset_temporary_storage() should not be concern of the platform so we don't have to care whether it gets DCE-ed or not?
    reset_temporary_storage();
}
