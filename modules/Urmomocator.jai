heap_size := 0;
get_heap_base :: () -> *void #foreign "get_heap_base";

// TODO: heap_base_alloc is really dumb
// It would be interesting to implement a proper malloc on __heap_base
allocator_proc :: (mode: Allocator_Mode, requested_size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    if mode == {
        case .RESIZE; #through;
        case .ALLOCATE; if (old_size < requested_size) {
            // assert(__heap_base != null);
            new_memory := get_heap_base() + heap_size;
            heap_size += requested_size;
            memcpy(new_memory, old_memory, old_size);
            return new_memory;
        } else {
            return old_memory;
        }
        case; return null;
    }
}
