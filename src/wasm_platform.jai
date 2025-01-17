prepare_text_wasm :: (data: *u8, count: s64) -> (width: s64) #foreign "prepare_text_wasm";

prepare_text :: (text: string) -> (width: s64) {
    return prepare_text_wasm(text.data, text.count); 
}

draw_prepared_text_wasm :: (x: s64, y: s64, r: float, g: float, b: float, a: float) #foreign "draw_prepared_text_wasm";

draw_prepared_text :: (x: s64, y: s64, color: Vector4) {
    draw_prepared_text_wasm(x, y, color.x, color.y, color.z, color.w);
}

random_get_zero_to_one :: () -> float #foreign "random_get_zero_to_one";
random_get_within_range :: (x: float32, y: float32) -> float #foreign "random_get_within_range";

fill_rect_wasm :: (x: float32, y: float32, w: float32, h: float32,
                   r: float32, g: float32, b: float32, a: float32) #foreign "fill_rect_wasm";

fill_rect :: (rect: Rect, color: Vector4) {
    fill_rect_wasm(rect.x, rect.y, rect.w, rect.h,
                   color.x, color.y, color.z, color.w);
}

main :: () {
    init();
}
