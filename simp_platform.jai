#import "Basic";
#import "Math";
#import "Window_Creation";
#import "Input";
#import "Random";
#import "File";
Simp :: #import "Simp";

font: *Simp.Dynamic_Font;

#if DEBUG {
    Colored_Rect :: struct {
        rect: Rect;
        color: Vector4;
    };

    make_colored_rect :: (rect: Rect, color: Vector4) -> Colored_Rect {
        result : Colored_Rect = ---;
        result.rect = rect;
        result.color = color;
        return result;
    }

    rect_buffer: [..]Colored_Rect;

    clear_rect_buffer :: () {
        array_reset_keeping_memory(*rect_buffer);
    }

    write_svg_header :: (file: *File, width: int, height: int) {
        file_write(file, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
        file_write(file, "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n");
        file_write(file, tprint("<svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" x=\"0px\" y=\"0px\" viewBox=\"0 0 % %\" xml:space=\"preserve\">\n", width, height));
    }

    tvector4_as_svg_style :: (color: Vector4) -> string {
        hex : u32 = 0;
        hex |= (cast(u32)(color.x*255.0))<<16;
        hex |= (cast(u32)(color.y*255.0))<<8;
        hex |= (cast(u32)(color.z*255.0));
        return tprint("fill:#%;fill-opacity:%", formatInt(hex, base=16, minimum_digits=6), color.w);
    }

    write_svg_rect :: (file: *File, using colored_rect: Colored_Rect) {
        line := tprint("<rect x=\"%\" y=\"%\" width=\"%\" height=\"%\" style=\"%\"/>\n",
                       rect.x, rect.y, rect.w, rect.h,
                       tvector4_as_svg_style(color));
        file_write(file, line);
    }

    write_svg_footer :: (file: *File) {
        file_write(file, "</svg>\n");
    }

    save_rect_buffer_as_svg :: () {
        now, now_ok := to_nanoseconds(current_time_consensus());
        if !now_ok {
            print("ERROR: could not convert current time to nanoseconds");
            return;
        }
        file_path := tprint("screenshot-%.svg", now);
        file, file_ok := file_open(file_path, for_writing = true);
        if !file_ok {
            print("ERROR: could not open file % for writing", file_path);
            return;
        }
        defer file_close(*file);

        write_svg_header(*file, WINDOW_WIDTH, WINDOW_HEIGHT);
        background :: #run make_colored_rect(make_rect(0, 0, xx WINDOW_WIDTH, xx WINDOW_HEIGHT), BACKGROUND_COLOR);
        write_svg_rect(*file, background);
        for * rect_buffer {
            write_svg_rect(*file, it);
        }
        write_svg_footer(*file);

        print("Saved file %\n", file_path);
    }
}

actual_window_width: int;
actual_window_height: int;
actual_window_offset_x: int;
actual_window_offset_y: int;

fill_rect :: (rect: Rect, color: Vector4) {
    #if DEBUG {
        colored_rect : Colored_Rect = ---;
        colored_rect.rect = rect;
        colored_rect.color = color;
        array_add(*rect_buffer, colored_rect);
    }
    using nrect := rect;
    x = x/WINDOW_WIDTH*actual_window_width + actual_window_offset_x;
    y = y/WINDOW_HEIGHT*actual_window_height + actual_window_offset_y;
    w = w/WINDOW_WIDTH*actual_window_width;
    h = h/WINDOW_HEIGHT*actual_window_height;
    Simp.set_shader_for_color(enable_blend = true);
    Simp.immediate_quad(x, actual_window_height - y, x + w, actual_window_height - y - h, color);
}

prepare_text :: (text: string) -> (width: s64) {
    return Simp.prepare_text(font, text) * WINDOW_WIDTH / actual_window_width;
}

draw_prepared_text :: (x: s64, y: s64, color := Vector4.{1, 1, 1, 1}) {
    x = x*actual_window_width/WINDOW_WIDTH + actual_window_offset_x;
    y = y*actual_window_height/WINDOW_HEIGHT + actual_window_offset_y;
    Simp.draw_prepared_text(font, x, actual_window_height - y, color);
}

main :: () {
    init();

    window := create_window(window_name="Jaibreak", width=WINDOW_WIDTH, height=WINDOW_HEIGHT);
    actual_window_width = WINDOW_WIDTH;
    actual_window_height = WINDOW_HEIGHT;
    actual_window_offset_x = 0;
    actual_window_offset_y = 0;
    Simp.set_render_target(window);

    font = Simp.get_font_at_size("fonts", TEXT_FONT_FILE_NAME, xx (TEXT_PIXEL_HEIGHT_FACTOR*actual_window_height));
    if !font {
        print("[ERROR] could not load font %\n", TEXT_FONT_FILE_NAME);
        exit(1);
    }

    last_time := get_time();
    quit := false;
    while !quit {
        now := get_time();
        delta : float64 = now - last_time;
        current_dt := cast(float) delta;
        last_time = now;

        update_window_events();

        for get_window_resizes() {
            Simp.update_window(it.window);
            if it.window == window {
                actual_window_width  = it.width;
                actual_window_height = it.width*WINDOW_HEIGHT/WINDOW_WIDTH;
                if actual_window_height > it.height {
                    actual_window_width  = it.height*WINDOW_WIDTH/WINDOW_HEIGHT;
                    actual_window_height = it.height;
                    actual_window_offset_x = (it.width - actual_window_width)/2;
                    actual_window_offset_y = 0;
                } else {
                    actual_window_offset_x = 0;
                    actual_window_offset_y = -(it.height - actual_window_height)/2;
                }

                Simp.release_font(font);
                font = Simp.get_font_at_size("fonts", TEXT_FONT_FILE_NAME, xx (TEXT_PIXEL_HEIGHT_FACTOR*actual_window_height));
                if !font {
                    print("[ERROR] could not reload font %\n", TEXT_FONT_FILE_NAME);
                    exit(1);
                }
            }
        }

        for event : events_this_frame {
            if event.type == {
                case .QUIT; {
                    quit = true;
                    break;
                }

                case .KEYBOARD; if input_application_has_focus {
                    #if DEBUG {
                        if event.key_code == {
                            case .F5; if event.key_pressed {
                                sync_param_vars();
                                Simp.release_font(font);
                                font = Simp.get_font_at_size("fonts", TEXT_FONT_FILE_NAME, xx (TEXT_PIXEL_HEIGHT_FACTOR*actual_window_height));
                                if !font {
                                    print("[ERROR] could not reload font %\n", TEXT_FONT_FILE_NAME);
                                    exit(1);
                                }
                            }

                            case .F3; if event.key_pressed {
                                save_rect_buffer_as_svg();
                            }
                        }
                    }

                    if event.key_pressed {
                        key_press(cast(u32) event.key_code);
                    } else {
                        key_release(cast(u32) event.key_code);
                    }
                }
            }
        }

        #if DEBUG then clear_rect_buffer();
        Simp.clear_render_target(0, 0, 0, 0);
        update(current_dt);
        Simp.swap_buffers(window);
    }
}
