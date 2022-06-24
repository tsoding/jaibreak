#import "Basic";
#import "Math";
#import "Window_Creation";
#import "Input";
#import "Random";
Simp :: #import "Simp";

// TODO: introduce logical size of the device (similar to SDL's one)
TEXT_FONT_FILE_NAME :: "Alegreya-Regular.ttf";

font: *Simp.Dynamic_Font;

fill_rect :: (using rect: Rect, color: Vector4) {
    Simp.set_shader_for_color(enable_blend = true);
    Simp.immediate_quad(x, WINDOW_HEIGHT - y, x + w, WINDOW_HEIGHT - y - h, color);
}

main :: () {
    init_state();

    font = Simp.get_font_at_size("fonts", TEXT_FONT_FILE_NAME, xx (TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT));
    if !font {
        print("[ERROR] could not load font %\n", TEXT_FONT_FILE_NAME);
        exit(1);
    }
    print("[INFO] loaded font %\n", TEXT_FONT_FILE_NAME);

    window := create_window(window_name="Jaibreak", width=WINDOW_WIDTH, height=WINDOW_HEIGHT);
    Simp.set_render_target(window);

    last_time := get_time();
    while !quit {
        now := get_time();
        delta : float64 = now - last_time;
        current_dt := cast(float) delta;
        last_time = now;

        update_window_events();

        KEY_A :: #run get_key_code(#char "a");
        KEY_D :: #run get_key_code(#char "d");
        KEY_SPACE :: #run get_key_code(#char " ");

        for event : events_this_frame {
            if event.type == {
                case .QUIT; {
                    quit = true;
                    break;
                }

                case .KEYBOARD; if input_application_has_focus {
                    if event.key_code == {
                        case .ARROW_LEFT; #through; case KEY_A; left  = event.key_pressed != 0;
                        case .ARROW_RIGHT; #through; case KEY_D; right = event.key_pressed != 0;
                        case KEY_SPACE; if !pause && state == .READY && event.key_pressed {
                            state = .PLAY;
                            proj_dy = -PROJ_SPEED;
                            proj_dx = PROJ_SPEED*ANGLE_FACTOR;
                            if left  then proj_dx = -PROJ_SPEED;
                            if right then proj_dx = PROJ_SPEED;
                        }
                        case .ESCAPE; if event.key_pressed then pause = !pause;
                        case .F5; #if DEBUG {
                            if event.key_pressed {
                                sync_param_vars();
                                Simp.release_font(font);
                                font = Simp.get_font_at_size("fonts", TEXT_FONT_FILE_NAME, xx (TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT));
                            }
                        }
                    }
                }
            }
        }

        update(current_dt);
        Simp.clear_render_target(BACKGROUND_COLOR.x, BACKGROUND_COLOR.y, BACKGROUND_COLOR.z, BACKGROUND_COLOR.w);
        render();

        Simp.swap_buffers(window);

        reset_temporary_storage();
    }
}
