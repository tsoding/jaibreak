#import "Basic";
#import "Math";

Target :: struct {
    position: Vector2;
    color: Vector4;
    dead: bool;
}

Particle :: struct {
    position: Vector2;
    velocity: Vector2;
    size_factor: float32 = 1.0;
    lifetime: float32;
    color: Vector4;
}

State :: enum {
    READY;
    PLAY;
    RESTART;
    GAMEOVER;
}

left := false;
right := false;
particles : [256]Particle;
targets_pool : [..]Target;
bar_x:   float32;
bar_dx:  float32;
proj_position: Vector2;
proj_velocity: Vector2;
quit: bool;
pause: bool;
state: State;
score: int;
restart_cooldown: float;
restart_velocity: float;
bonus_score: int;
lifes: int;
// TODO: victory
// TODO: game over
// TODO: tutorial
// TODO: speeding up the ball over time

particle_burst :: (position: Vector2, color: Vector4, count: int) {
    for 0..count-1 particle_emit(position, color);
}

// TODO: gravity for particles
particle_emit :: (position: Vector2, color: Vector4) {
    for * particles {
        if it.lifetime <= 0 {
            angle := random_get_zero_to_one()*2*PI;
            t := random_get_within_range(0.5, 1.5);
            it.position = position;
            it.velocity = make_vector2(cos(angle), sin(angle))*PARTICLE_BASE_VELOCITY*t;
            it.size_factor = random_get_within_range(0.5, 1.5);
            it.color = color;
            it.lifetime = PARTICLE_LIFETIME;
            return;
        }
    }
}

key_press :: (key: u32) {
    if key == {
        case #char "A"; left = true;
        case #char "D"; right = true;
        case 27; pause = !pause;
        case #char " "; if !pause && state == .READY {
            state = .PLAY;
            // TODO: direct angle factored projectile based on the last direction
            proj_velocity.x = PROJ_SPEED*ANGLE_FACTOR;
            proj_velocity.y = -PROJ_SPEED;
            if left  then proj_velocity.x = -PROJ_SPEED;
            if right then proj_velocity.x = PROJ_SPEED;
        }
    }
}

key_release :: (key: u32) {
    if key == {
        case #char "A"; left = false;
        case #char "D"; right = false;
    }
}

init_state :: () {
    bonus_score = 0;

    target_grid_width := (TARGET_COLS*TARGET_WIDTH + (TARGET_COLS - 1)*TARGET_PADDING_X);
    target_grid_x := WINDOW_WIDTH/2 - target_grid_width/2;

    for row: 0..TARGET_ROWS-1 {
        for col: 0..TARGET_COLS-1 {
            target: Target = ---;
            target.position.x = xx (target_grid_x + (TARGET_WIDTH + TARGET_PADDING_X)*col);
            target.position.y = xx (TARGET_GRID_Y + (TARGET_HEIGHT + TARGET_PADDING_Y)*row);
            target.dead       = false;

            red   := srgb_to_linear(make_vector4(1, .18, .18, 1));
            green := srgb_to_linear(make_vector4(.18, 1, .18, 1));
            blue  := srgb_to_linear(make_vector4(.18, .18, 1, 1));
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
    quit = false;
    pause = false;
    state = .RESTART;
    score = 0;
    lifes = 3;
    proj_position = life_position(lifes);
    restart_cooldown = RESTART_COOLDOWN;
}

Rect :: struct {
    x: float32;
    y: float32;
    w: float32;
    h: float32;
}

make_rect :: (position: Vector2, size: Vector2) -> Rect {
    return make_rect(position.x, position.y, size.x, size.y);
}

make_rect :: (x: float32, y: float32, w: float32, h: float32) -> Rect {
    result : Rect = ---;
    result.x = x;
    result.y = y;
    result.w = w;
    result.h = h;
    return result;
}

target_rect :: (using target: Target) -> Rect {
    return make_rect(position.x, position.y, TARGET_WIDTH, TARGET_HEIGHT);
}

rect_center :: (using rect: Rect) -> Vector2 {
    return make_vector2(x + w/2, y + h/2);
}

proj_center :: () -> Vector2 {
    return rect_center(proj_rect(proj_position));
}

proj_rect :: (using position: Vector2) -> Rect {
    return proj_rect(x, y);
}

proj_rect :: (x: float32, y: float32) -> Rect {
    result : Rect = ---;
    result.x = x;
    result.y = y;
    result.w = PROJ_SIZE;
    result.h = PROJ_SIZE;
    return result;
}

bar_anchor :: (x: float) -> Vector2 {
    anchor_x := x + BAR_LEN/2 - PROJ_SIZE/2;
    anchor_y := (WINDOW_HEIGHT - PROJ_SIZE - BAR_PADDING_Y_BOTTOM) - BAR_THICCNESS/2 - PROJ_SIZE - 1.0;
    return make_vector2(anchor_x, anchor_y);
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
    particle_burst(proj_center(), target.color, PARTICLE_BURST_HIT_COUNT + bonus_score*2);
    target.dead = true;
    // TODO: indicate how much score points you've got by showing a fading sign with the number at the point of the impact
    score += 1 + bonus_score;
    bonus_score += 1;
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

horz_collision :: (position: *Vector2, velocity: *Vector2, size: Vector2, dt: float32) -> Collision {
    nx := position.x + velocity.x*dt;
    if nx < 0 {
        velocity.x *= -1;
        return .BORDER_LEFT;
    }
    if nx + size.x > xx WINDOW_WIDTH {
        velocity.x *= -1;
        return .BORDER_RIGHT;
    }
    if overlaps(make_rect(nx, position.y, size.x, size.y), bar_rect(bar_x)) {
        velocity.x *= -1;
        return .BAR;
    }
    for * targets_pool {
        if !it.dead && overlaps(make_rect(nx, position.y, size.x, size.y), target_rect(it)) {
            velocity.x *= -1;
            return xx (xx Collision.TARGET + it_index);
        }
    }
    position.x = nx;
    return .NO;
}

vert_collision :: (position: *Vector2, velocity: *Vector2, size: Vector2, dt: float32) -> Collision {
    ny := position.y + velocity.y*dt;
    if ny < 0 {
        velocity.y *= -1;
        return .BORDER_TOP;
    }
    if ny + size.y > xx WINDOW_HEIGHT {
        velocity.y *= -1;
        return .BORDER_BOTTOM;
    }
    if overlaps(make_rect(position.x, ny, size.x, size.y), bar_rect(bar_x)) {
        velocity.y *= -1;
        return .BAR;
    }
    for *targets_pool {
        if !it.dead && overlaps(make_rect(position.x, ny, size.x, size.y), target_rect(it)) {
            velocity.y *= -1;
            return xx (xx Collision.TARGET + it_index);
        }
    }
    position.y = ny;
    return .NO;
}

bar_collision :: (dt: float32, obstacle: Rect) {
    bar_nx := clamp(bar_x + bar_dx*BAR_SPEED*dt, 0, WINDOW_WIDTH - BAR_LEN);
    if overlaps(obstacle, bar_rect(bar_nx)) return;
    bar_x = bar_nx;
}

life_position :: (index: int) -> Vector2 {
    position : Vector2 = ---;
    position.x = LIFES_PADDING_RIGHT + index*(LIFE_SIZE + LIFES_PADDING);
    position.y = LIFES_PADDING_TOP;
    return position;
}

handle_proj_collision :: (c: Collision) {
    if c == {
        case .BAR; {
            particle_burst(proj_center(), BAR_COLOR, PARTICLE_BURST_HIT_COUNT);
            if bar_dx != 0 {
                proj_velocity.x = bar_dx*PROJ_SPEED;
            } else {
                sign :: inline (x: float) -> float {
                    return xx (-cast(int)(x<0) + cast(int)(x>0));
                }
                proj_velocity.x = sign(proj_velocity.x)*PROJ_SPEED*ANGLE_FACTOR;
            }
            bonus_score = 0;
        }

        case .BORDER_BOTTOM; {
            particle_burst(proj_center(), PROJ_COLOR, PARTICLE_BURST_DEATH_COUNT);
            state = .RESTART;
            bonus_score = 0;
            lifes = max(lifes - 1, 0);
            proj_position = life_position(lifes);
            proj_velocity = .{0, 0};
            restart_cooldown = RESTART_COOLDOWN;
            restart_velocity = 0;
        }

        case; if c >= .TARGET {
            target_hit(*targets_pool[c - .TARGET]);
        }
    }
}

update :: (dt: float32) {
    if !pause {
        // TODO: slight ease in/out of the bar movement
        bar_dx = 0;
        if left  then bar_dx += -1;
        if right then bar_dx +=  1;
        bar_collision(dt, proj_rect(proj_position));

        if state == {
            case .READY; {
                proj_velocity = .{0, 0};
                proj_position = bar_anchor(bar_x);
            }

            case .PLAY; {
                handle_proj_collision(horz_collision(*proj_position, *proj_velocity, make_vector2(PROJ_SIZE, PROJ_SIZE), dt));
                handle_proj_collision(vert_collision(*proj_position, *proj_velocity, make_vector2(PROJ_SIZE, PROJ_SIZE), dt));
            }

            case .RESTART; if restart_cooldown > 0 {
                restart_cooldown -= dt;
            } else {
                anchor := bar_anchor(bar_x);
                proj_velocity = anchor - proj_position;
                len := length(proj_velocity);
                if len > 0 {
                    restart_velocity += RESTART_ACCELERATION*dt;
                    proj_velocity /= len;
                    proj_velocity *= restart_velocity;
                }
                proj_position += proj_velocity*dt;
                if length(proj_position - anchor) < RESTART_DISTANCE {
                    particle_burst(proj_center(), BAR_COLOR, PARTICLE_BURST_DEATH_COUNT);
                    state = .READY;
                }
            }
        }

        for * particles {
            if it.lifetime > 0 {
                size := it.size_factor*make_vector2(PARTICLE_BASE_SIZE, PARTICLE_BASE_SIZE);
                horz_collision(*it.position, *it.velocity, size, dt);
                vert_collision(*it.position, *it.velocity, size, dt);
                it.lifetime -= dt;
            }
        }
    }

    render();

    reset_temporary_storage();
}

int_to_string :: (x: int, data: *u8) -> int {
    assert(x >= 0);
    if (x == 0) {
        data[0] = xx #char "0";
        return 1;
    }

    count := 0;
    while x > 0 {
        data[count] = xx (x%10 + #char "0");
        count += 1;
        x /= 10;
    }
    n := count/2-1;
    for 0..n Swap(*data[it], *data[count - it - 1]);
    return count;
}

render_score :: (x: int) -> string {
    SCORE_BUFFER_CAP :: 64;
    score_buffer : []u8;
    score_buffer.data = talloc(SCORE_BUFFER_CAP);
    score_buffer.count = SCORE_BUFFER_CAP;

    score_label :: "Score: ";
    memcpy(score_buffer.data, score_label.data, score_label.count);
    count := int_to_string(x, score_buffer.data + score_label.count);

    result : string = ---;
    result.data = score_buffer.data;
    result.count = score_label.count + count;
    return result;
}

render :: () {
    fill_rect(make_rect(0, 0, xx WINDOW_WIDTH, xx WINDOW_HEIGHT), BACKGROUND_COLOR);

    for particles {
        if it.lifetime > 0 {
            size := make_vector2(PARTICLE_BASE_SIZE, PARTICLE_BASE_SIZE)*it.size_factor;
            color := it.color;
            color.w = it.lifetime/PARTICLE_LIFETIME;
            fill_rect(make_rect(it.position, size), color);
        }
    }

    for targets_pool if !it.dead then fill_rect(target_rect(it), it.color);
    fill_rect(proj_rect(proj_position), PROJ_COLOR);
    fill_rect(bar_rect(bar_x), BAR_COLOR);

    // TODO: make the score and lifes semi-transparent when the projectile cross them
    for i: 0..lifes-1 {
        position := life_position(i);
        fill_rect(make_rect(position.x, position.y, LIFE_SIZE, LIFE_SIZE), LIFE_COLOR);
    }

    /* score_text_width := prepare_text(tprint("Score: %", score)); */
    score_text_width := prepare_text(render_score(score));
    // TODO: coordinate system for rendering the text is inconsistent compared to fill_rect
    draw_prepared_text(SCORE_PADDING_LEFT, WINDOW_HEIGHT - SCORE_PADDING_TOP - xx (TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT), TEXT_COLOR);
    if pause {
        pause_text_width := prepare_text("Pause");
        draw_prepared_text(WINDOW_WIDTH/2 - pause_text_width/2, WINDOW_HEIGHT/2, TEXT_COLOR);
    }
#if DEBUG {
    debug_text_width := prepare_text("Debug");
    draw_prepared_text(WINDOW_WIDTH - DEBUG_PADDING_RIGHT - debug_text_width, WINDOW_HEIGHT - DEBUG_PADDING_TOP - xx (TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT), DEBUG_TEXT_COLOR);
}
}
