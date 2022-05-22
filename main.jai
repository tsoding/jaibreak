#import "Basic";
#import "Math";
#import "Window_Creation";
#import "Input";
Simp :: #import "Simp";

// Configuration
FPS :: 60;
DT_MAX : float : 0.15;
DELTA_TIME_SEC : float32 : 1.0/FPS;
WINDOW_FACTOR :: 100;
WINDOW_WIDTH :: 16*WINDOW_FACTOR;
WINDOW_HEIGHT :: 9*WINDOW_FACTOR;
BACKGROUND_COLOR :: #run unpack_color(0xFF181818);
PROJ_SIZE: float32 : 25*0.80;
PROJ_SPEED: float32 : 350;
PROJ_COLOR :: #run unpack_color(0xFFFFFFFF);
BAR_LEN: float32 : 100;
BAR_THICCNESS: float32 : PROJ_SIZE;
BAR_Y: float32 : WINDOW_HEIGHT - PROJ_SIZE - 50;
BAR_SPEED: float32 : PROJ_SPEED*2.0;
BAR_COLOR :: #run unpack_color(0xFF3030FF);
TARGET_WIDTH :: BAR_LEN;
TARGET_HEIGHT :: PROJ_SIZE;
TARGET_PADDING_X :: 20;
TARGET_PADDING_Y :: TARGET_HEIGHT + 20;
TARGET_ROWS :: 10;
TARGET_COLS :: 10;
TARGET_GRID_WIDTH :: (TARGET_COLS*TARGET_WIDTH + (TARGET_COLS - 1)*TARGET_PADDING_X);
TARGET_GRID_X :: WINDOW_WIDTH/2 - TARGET_GRID_WIDTH/2;
TARGET_GRID_Y :: 50;

Target :: struct {
    x: float32;
    y: float32;
    color: Vector4;
    dead: bool;
}

init_targets :: () -> [TARGET_ROWS*TARGET_COLS]Target {
    targets: [TARGET_ROWS*TARGET_COLS]Target = ---;
    for row: 0..TARGET_ROWS-1 {
        for col: 0..TARGET_COLS-1 {
            using targets[row*TARGET_COLS + col];
            x     = xx (TARGET_GRID_X + (TARGET_WIDTH + TARGET_PADDING_X)*col);
            y     = xx (TARGET_GRID_Y + TARGET_PADDING_Y*row);
            dead  = false;

            red   :: #run srgb_to_linear(Vector4.{1, .18, .18, 1});
            green :: #run srgb_to_linear(Vector4.{.18, 1, .18, 1});
            blue  :: #run srgb_to_linear(Vector4.{.18, .18, 1, 1});
            level :: .5;
            t  := cast(float) row/TARGET_COLS;
            c  := cast(float) (t < level);
            g1 := lerp(red, green, t/level);
            g2 := lerp(green, blue, (t - level)/(1 - level));
            color = linear_to_srgb(c*g1 + (1 - c)*g2);
        }
    }
    return targets;
}

// State
targets_pool := #run init_targets();
bar_x:   float32 = WINDOW_WIDTH/2 - BAR_LEN/2;
bar_dx:  float32 = 0;
proj_x:  float32 = WINDOW_WIDTH/2 - PROJ_SIZE/2;
proj_y:  float32 = BAR_Y - BAR_THICCNESS/2 - PROJ_SIZE - 1.0;
proj_dx: float32 = 1;
proj_dy: float32 = 1;
quit := false;
pause := false;
started := false;
// TODO: death
// TODO: score
// TODO: victory

Rect :: struct {
    x: float32;
    y: float32;
    w: float32;
    h: float32;
}

unpack_color :: (color: u32) -> Vector4 {
    r := ((color >> (0*8)) & 0xFF) / 255.0;
    g := ((color >> (1*8)) & 0xFF) / 255.0;
    b := ((color >> (2*8)) & 0xFF) / 255.0;
    a := ((color >> (3*8)) & 0xFF) / 255.0;
    return make_vector4(r, g, b, a);
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
    result.y = BAR_Y - BAR_THICCNESS/2;
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

horz_collision :: (dt: float32) {
    proj_nx := proj_x + proj_dx*PROJ_SPEED*dt;
    if proj_nx < 0 || proj_nx + PROJ_SIZE > WINDOW_WIDTH || overlaps(proj_rect(proj_nx, proj_y), bar_rect(bar_x)) {
        proj_dx *= -1;
        return;
    }
    for * targets_pool {
        if !it.dead && overlaps(proj_rect(proj_nx, proj_y), target_rect(it)) {
            it.dead = true;
            proj_dx *= -1;
            return;
        }
    }
    proj_x = proj_nx;
}

vert_collision :: (dt: float32) {
    proj_ny := proj_y + proj_dy*PROJ_SPEED*dt;
    if proj_ny < 0 || proj_ny + PROJ_SIZE > WINDOW_HEIGHT {
        proj_dy *= -1;
        return;
    }
    if overlaps(proj_rect(proj_x, proj_ny), bar_rect(bar_x)) {
        if bar_dx != 0 proj_dx = bar_dx;
        proj_dy *= -1;
        return;
    }
    for *targets_pool {
        if !it.dead && overlaps(proj_rect(proj_x, proj_ny), target_rect(it)) {
            it.dead = true;
            proj_dy *= -1;
            return;
        }
    }
    proj_y = proj_ny;
}

bar_collision :: (dt: float32) {
    bar_nx := clamp(bar_x + bar_dx*BAR_SPEED*dt, 0, WINDOW_WIDTH - BAR_LEN);
    if overlaps(proj_rect(proj_x, proj_y), bar_rect(bar_nx)) return;
    bar_x = bar_nx;
}

update :: (dt: float32) {
    if !pause && started {
        if (overlaps(proj_rect(proj_x, proj_y), bar_rect(bar_x))) {
            proj_y = BAR_Y - BAR_THICCNESS/2 - PROJ_SIZE - 1.0;
            return;
        }
        bar_collision(dt);
        horz_collision(dt);
        vert_collision(dt);
    }
}

fill_rect :: (using rect: Rect, color: Vector4) {
    Simp.immediate_quad(x, WINDOW_HEIGHT - y, x + w, WINDOW_HEIGHT - y - h, color);
}

render :: () {
    fill_rect(proj_rect(proj_x, proj_y), PROJ_COLOR);
    fill_rect(bar_rect(bar_x), BAR_COLOR);
    for targets_pool if !it.dead fill_rect(target_rect(it), it.color);
}

main :: () {
    window := create_window(window_name="Jaibreak", width=WINDOW_WIDTH, height=WINDOW_HEIGHT);
    Simp.set_render_target(window);

    Simp.set_shader_for_color();
    last_time := get_time();
    left := false;
    right := false;
    while !quit {
        now := get_time();
        delta : float64 = now - last_time;
        current_dt := cast(float) delta;
        if current_dt > DT_MAX current_dt = DT_MAX;
        last_time = now;

        update_window_events();

        for event : events_this_frame {
            if event.type == {
                case .QUIT; {
                    quit = true;
                    break;
                }

                case .KEYBOARD; if event.key_code == {
                    case #run get_key_code(#char "a"); #through;
                    case .ARROW_LEFT;
                    left  = event.key_pressed != 0;

                    case #run get_key_code(#char "d"); #through;
                    case .ARROW_RIGHT;
                    right = event.key_pressed != 0;

                    case #run get_key_code(#char " ");
                    if event.key_pressed pause = !pause;
                }
            }
        }

        bar_dx = 0;
        if left {
            bar_dx += -1;
            if !started {
                started = true;
                proj_dx = -1;
            }
        }
        if right {
            bar_dx += 1;
            if !started {
                started = true;
                proj_dx = 1;
            }
        }

        update(current_dt);

        {
            using BACKGROUND_COLOR;
            Simp.clear_render_target(x, y, z, w);
        }

        render();

        Simp.swap_buffers(window);
    }
}
