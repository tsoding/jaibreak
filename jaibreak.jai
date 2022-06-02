#import "Basic";
#import "Math";
#import "Window_Creation";
#import "Input";
#import "Random";
Simp :: #import "Simp";

// Configuration
WINDOW_FACTOR :: 100;
// TODO: introduce logical size of the device (similar to SDL's one)
WINDOW_WIDTH :: 16*WINDOW_FACTOR;
WINDOW_HEIGHT :: 9*WINDOW_FACTOR;
TEXT_FONT_FILE_NAME :: "Alegreya-Regular.ttf";

Target :: struct {
    x: float32;
    y: float32;
    color: Vector4;
    dead: bool;
}

Particle :: struct {
    x: float32;
    y: float32;
    dx: float32;
    dy: float32;
    size: float32 = 1.0;
    lifetime: float32;
    color: Vector4 = .{.9, 0, 0, 1};
}

State :: enum {
    READY;
    PLAY;
    DEATH;
    GAMEOVER;
}

particles : [128]Particle;
targets_pool : [..]Target;
bar_x:   float32;
bar_dx:  float32;
proj_x:  float32;
proj_y:  float32;
proj_dx: float32;
proj_dy: float32;
quit: bool;
pause: bool;
state: State;
score: int;
// TODO: restart animation
death_cooldown: float;
// TODO: victory
// TODO: game over

particle_burst :: (x: float32, y: float32, color: Vector4, count: int) {
    for 0..count-1 particle_emit(x, y, color);
}

particle_emit :: (x: float32, y: float32, color: Vector4) {
    for * particles {
        if it.lifetime <= 0 {
            it.x = x;
            it.y = y;
            angle := random_get_zero_to_one()*2*PI;
            t := random_get_within_range(0.5, 1.5);
            it.dx = cos(angle)*PARTICLE_BASE_VELOCITY*t;
            it.dy = sin(angle)*PARTICLE_BASE_VELOCITY*t;
            it.size = random_get_within_range(0.5, 1.5);
            it.color = color;
            it.lifetime = PARTICLE_LIFETIME;
            return;
        }
    }
}

init_state :: () {
    target_grid_width := (TARGET_COLS*TARGET_WIDTH + (TARGET_COLS - 1)*TARGET_PADDING_X);
    target_grid_x := WINDOW_WIDTH/2 - target_grid_width/2;

    array_reset_keeping_memory(*targets_pool);
    for row: 0..TARGET_ROWS-1 {
        for col: 0..TARGET_COLS-1 {
            target: Target = ---;
            target.x     = xx (target_grid_x + (TARGET_WIDTH + TARGET_PADDING_X)*col);
            target.y     = xx (TARGET_GRID_Y + (TARGET_HEIGHT + TARGET_PADDING_Y)*row);
            target.dead  = false;

            red   := srgb_to_linear(Vector4.{1, .18, .18, 1});
            green := srgb_to_linear(Vector4.{.18, 1, .18, 1});
            blue  := srgb_to_linear(Vector4.{.18, .18, 1, 1});
            level := .5;
            t     := cast(float) row/TARGET_COLS;
            c     := cast(float) (t < level);
            g1    := lerp(red, green, t/level);
            g2    := lerp(green, blue, (t - level)/(1 - level));
            target.color = linear_to_srgb(c*g1 + (1 - c)*g2);

            array_add(*targets_pool, target);
        }
    }

    bar_x = WINDOW_WIDTH/2 - BAR_LEN/2;
    bar_dx = 0;
    proj_x = WINDOW_WIDTH/2 - PROJ_SIZE/2;
    proj_y = (WINDOW_HEIGHT - PROJ_SIZE - BAR_PADDING_Y_BOTTOM) - BAR_THICCNESS/2 - PROJ_SIZE - 1.0;
    proj_dx = 0;
    proj_dy = 0;
    quit = false;
    pause = false;
    state = .READY;
    score = 0;
}

Rect :: struct {
    x: float32;
    y: float32;
    w: float32;
    h: float32;
}

rect :: (x: float32, y: float32, w: float32, h: float32) -> Rect {
    result : Rect = ---;
    result.x = x;
    result.y = y;
    result.w = w;
    result.h = h;
    return result;
}

target_rect :: (target: Target) -> Rect {
    result : Rect = ---;
    result.x = target.x;
    result.y = target.y;
    result.w = TARGET_WIDTH;
    result.h = TARGET_HEIGHT;
    return result;
}

proj_rect :: (x: float32, y: float32) -> Rect {
    result : Rect = ---;
    result.x = x;
    result.y = y;
    result.w = PROJ_SIZE;
    result.h = PROJ_SIZE;
    return result;
}

bar_rect :: (x: float32) -> Rect {
    result : Rect = ---;
    result.x = x;
    result.y = (WINDOW_HEIGHT - PROJ_SIZE - BAR_PADDING_Y_BOTTOM) - BAR_THICCNESS/2;
    result.w = BAR_LEN;
    result.h = BAR_THICCNESS;
    return result;
}

sides :: (using rect: Rect) -> float32, float32, float32, float32 {
    return x, x + w, y, y + h;
}

overlaps :: (a: Rect, b: Rect) -> bool {
    La, Ra, Ta, Ba := sides(a);
    Lb, Rb, Tb, Bb := sides(b);
    return !(Ra < Lb || Rb < La || Ba < Tb || Bb < Ta);
}

target_hit :: (target: *Target) {
    particle_burst(proj_x + PROJ_SIZE/2, proj_y + PROJ_SIZE/2, target.color, PARTICLE_BURST_HIT_COUNT);
    target.dead = true;
    score += 1;
}

Collision :: enum s64 {
    NO :: 0;
    BORDER_LEFT;
    BORDER_RIGHT;
    BORDER_TOP;
    BORDER_BOTTOM;
    BAR;
    TARGET;
}

horz_collision :: (x: *float32, y: *float32, dx: *float32, dy: *float32, w: float32, h: float32, dt: float32) -> Collision {
    nx := <<x + <<dx*dt;
    if nx < 0 {
        <<dx *= -1;
        return .BORDER_LEFT;
    }
    if nx + w > WINDOW_WIDTH {
        <<dx *= -1;
        return .BORDER_RIGHT;
    }
    if overlaps(rect(nx, <<y, w, h), bar_rect(bar_x)) {
        <<dx *= -1;
        return .BAR;
    }
    for * targets_pool {
        if !it.dead && overlaps(rect(nx, <<y, w, h), target_rect(it)) {
            <<dx *= -1;
            return xx (xx Collision.TARGET + it_index);
        }
    }
    <<x = nx;
    return .NO;
}

vert_collision :: (x: *float32, y: *float32, dx: *float32, dy: *float32, w: float32, h: float32, dt: float32) -> Collision {
    ny := <<y + <<dy*dt;
    if ny < 0 {
        <<dy *= -1;
        return .BORDER_TOP;
    }
    if ny + w > WINDOW_HEIGHT {
        <<dy *= -1;
        return .BORDER_BOTTOM;
    }
    if overlaps(rect(<<x, ny, w, h), bar_rect(bar_x)) {
        if bar_dx != 0 then <<dx = bar_dx*abs(<<dx);
        <<dy *= -1;
        return .BAR;
    }
    for *targets_pool {
        if !it.dead && overlaps(rect(<<x, ny, w, h), target_rect(it)) {
            <<dy *= -1;
            return xx (xx Collision.TARGET + it_index);
        }
    }
    <<y = ny;
    return .NO;
}

bar_collision :: (dt: float32, obstacle: Rect) {
    bar_nx := clamp(bar_x + bar_dx*BAR_SPEED*dt, 0, WINDOW_WIDTH - BAR_LEN);
    if overlaps(obstacle, bar_rect(bar_nx)) return;
    bar_x = bar_nx;
}

handle_proj_collision :: (c: Collision) {
    if c == {
        case .BAR; particle_burst(proj_x + PROJ_SIZE/2, proj_y + PROJ_SIZE/2, BAR_COLOR, PARTICLE_BURST_HIT_COUNT);
        case; if c >= .TARGET {
            target_hit(*targets_pool[c - .TARGET]);
        }

        case .BORDER_BOTTOM; {
            particle_burst(proj_x + PROJ_SIZE/2, proj_y + PROJ_SIZE/2, PROJ_COLOR, PARTICLE_BURST_DEATH_COUNT);
            state = .DEATH;
            death_cooldown = DEATH_COOLDOWN;
        }
    }
}

update :: (dt: float32) {
    if !pause {
        if state == {
            case .PLAY; {
                if (overlaps(proj_rect(proj_x, proj_y), bar_rect(bar_x))) {
                    proj_y = (WINDOW_HEIGHT - PROJ_SIZE - BAR_PADDING_Y_BOTTOM) - BAR_THICCNESS/2 - PROJ_SIZE - 1.0;
                    return;
                }
                bar_collision(dt, proj_rect(proj_x, proj_y));
                handle_proj_collision(horz_collision(*proj_x, *proj_y, *proj_dx, *proj_dy, PROJ_SIZE, PROJ_SIZE, dt));
                handle_proj_collision(vert_collision(*proj_x, *proj_y, *proj_dx, *proj_dy, PROJ_SIZE, PROJ_SIZE, dt));
            }
            case .DEATH; {
                death_cooldown -= dt;
                if death_cooldown <= 0 {
                    bar_x = WINDOW_WIDTH/2 - BAR_LEN/2;
                    bar_dx = 0;
                    proj_x = WINDOW_WIDTH/2 - PROJ_SIZE/2;
                    proj_y = (WINDOW_HEIGHT - PROJ_SIZE - BAR_PADDING_Y_BOTTOM) - BAR_THICCNESS/2 - PROJ_SIZE - 1.0;
                    proj_dx = 0;
                    proj_dy = 0;
                    state = .READY;
                }
            }
            case;
        }

        for * particles {
            if it.lifetime > 0 {
                size := it.size*PARTICLE_BASE_SIZE;
                horz_collision(*it.x, *it.y, *it.dx, *it.dy, size, size, dt);
                vert_collision(*it.x, *it.y, *it.dx, *it.dy, size, size, dt);
                it.lifetime -= dt;
            }
        }
    }
}

fill_rect :: (using rect: Rect, color: Vector4) {
    Simp.immediate_quad(x, WINDOW_HEIGHT - y, x + w, WINDOW_HEIGHT - y - h, color);
}

render :: () {
    Simp.set_shader_for_color(enable_blend = true);
    if state == {
        case .READY; #through;
        case .PLAY; {
            fill_rect(proj_rect(proj_x, proj_y), PROJ_COLOR);
        }
        case;
    }
    fill_rect(bar_rect(bar_x), BAR_COLOR);
    for targets_pool if !it.dead fill_rect(target_rect(it), it.color);
    for particles {
        if it.lifetime > 0 {
            size := it.size*PARTICLE_BASE_SIZE;
            particle_rect : Rect = ---;
            particle_rect.x = it.x;
            particle_rect.y = it.y;
            particle_rect.w = size;
            particle_rect.h = size;
            color := it.color;
            color.w = it.lifetime/PARTICLE_LIFETIME;
            fill_rect(particle_rect, color);
        }
    }
}

main :: () {
    init_state();

    font := Simp.get_font_at_size("fonts", TEXT_FONT_FILE_NAME, xx (TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT));
    if !font {
        print("[ERROR] could not load font %\n", TEXT_FONT_FILE_NAME);
        exit(1);
    }
    print("[INFO] loaded font %\n", TEXT_FONT_FILE_NAME);

    window := create_window(window_name="Jaibreak", width=WINDOW_WIDTH, height=WINDOW_HEIGHT);
    Simp.set_render_target(window);

    last_time := get_time();
    left := false;
    right := false;
    while !quit {
        now := get_time();
        delta : float64 = now - last_time;
        current_dt := cast(float) delta;
        last_time = now;

        update_window_events();

        KEY_A :: #run get_key_code(#char "a");
        KEY_D :: #run get_key_code(#char "d");

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
                        case .ESCAPE; if event.key_pressed pause = !pause;
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

        // TODO: slight ease in/out of the bar movement
        bar_dx = 0;
        if state == {
            case .READY; {
                if left {
                    bar_dx += -1;
                    state = .PLAY;
                    proj_dx = -PROJ_SPEED;
                    proj_dy = -PROJ_SPEED;
                }
                if right {
                    bar_dx += 1;
                    state = .PLAY;
                    proj_dx = PROJ_SPEED;
                    proj_dy = -PROJ_SPEED;
                }
            }
            case .PLAY; {
                if left bar_dx += -1;
                if right bar_dx += 1;
            }
            case;
        }

        update(current_dt);

        {
            using BACKGROUND_COLOR;
            Simp.clear_render_target(x, y, z, w);
        }

        render();
        score_text_width := Simp.prepare_text(font, tprint("Score: %", score));
        Simp.draw_prepared_text(font, SCORE_PADDING_LEFT, WINDOW_HEIGHT - SCORE_PADDING_TOP - xx (TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT), TEXT_COLOR);
        if pause {
            pause_text_width := Simp.prepare_text(font, "Pause");
            Simp.draw_prepared_text(font, WINDOW_WIDTH/2 - pause_text_width/2, WINDOW_HEIGHT/2, TEXT_COLOR);
        }
        #if DEBUG {
            debug_text_width := Simp.prepare_text(font, "Debug");
            Simp.draw_prepared_text(font, WINDOW_WIDTH - DEBUG_PADDING_RIGHT - debug_text_width, WINDOW_HEIGHT - DEBUG_PADDING_TOP - xx (TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT), DEBUG_TEXT_COLOR);
        }

        Simp.swap_buffers(window);

        reset_temporary_storage();
    }
}
