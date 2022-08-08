#import "Basic";
#import "Math";

init :: () {
    allocate_targets();
    center_bar();
    lifes = 3;

    // TODO: save the fact that the player already passed the tutorial
    tutorial = true;
    if tutorial {
        switch_to_start_state();
    } else {
        switch_to_attach_state();
    }
}

update :: (dt: float) {
    update_game(dt);
    render_game();
    reset_temporary_storage();
}

key_press :: (key: u32) {
    if key == {
        case #char "Q"; #if DEBUG if state == .PLAY for *targets target_hit(it);
        case #char "A"; {
            left = true;
            if state == .START {
                popup_dispose(*primary_popup);
                switch_to_attach_state();
            }
        }
        case #char "D"; {
            right = true;
            if state == .START {
                popup_dispose(*primary_popup);
                switch_to_attach_state();
            }
        }
        case 27; pause = !pause;
        case #char " "; if !pause {
            if state == {
                case .READY; switch_to_play_state();
                case .GAMEOVER; if curtain >= 1 then switch_to_restart_state();
            }
        }
    }
}

key_release :: (key: u32) {
    if key == {
        case #char "A"; left = false;
        case #char "D"; right = false;
    }
}

wait_for :: (dt: float, t: *float, duration: float) -> bool {
    if <<t >= 1 return true;
    <<t += dt/duration;
    return false;
}

attach_to :: (dt: float, position: *Vector2, velocity: *Vector2, destination : Vector2) -> bool {
    attach_velocity := length(velocity);
    <<velocity = destination - position;
    len := length(velocity);
    if len > 0 {
        attach_velocity += ATTACH_ACCELERATION*dt;
        <<velocity /= len;
        <<velocity *= attach_velocity;
    }
    <<position += <<velocity*dt;
    return length(position - destination) < ATTACH_DISTANCE;
}

update_game :: (dt: float) {
    if !pause {
        update_bar(dt);
        update_both_popups(dt);
        update_particles(dt);

        if state == {
            case .RESTART; {
                if curtain > 0 {
                    curtain -= dt/POPUP_FADEOUT_TIME;
                } else {
                    curtain = 0;
                    switch_to_attach_state();
                }
            }

            case .READY; {
                proj_velocity = .{0, 0};
                proj_position = bar_anchor(bar_x);
            }

            case .PLAY; {
                handle_proj_collision(horz_collision(*proj_position, *proj_velocity, make_vector2(PROJ_SIZE, PROJ_SIZE), dt));
                handle_proj_collision(vert_collision(*proj_position, *proj_velocity, make_vector2(PROJ_SIZE, PROJ_SIZE), dt));
            }

            case .ATTACH; {
                if wait_for(dt, *attach_cooldown, ATTACH_COOLDOWN) {
                    if attach_to(dt, *proj_position, *proj_velocity, bar_anchor(bar_x)) {
                        particle_burst(proj_rect(proj_position), BAR_COLOR, PARTICLE_BURST_DEATH_COUNT);
                        switch_to_ready_state();
                    }
                }
            }

            case .GAMEOVER; {
                if primary_popup.state == .DISPLAY && curtain < 1 {
                    curtain += dt/GAMEOVER_FADEOUT_TIME;
                    if curtain >= 1 then popup_show(*secondary_popup, "(press SPACE to restart)");
                }
            }

            case .VICTORY; {
                if wait_for(dt, *victory_cooldown, VICTORY_COOLDOWN) {
                    if attach_to(dt, *proj_position, *proj_velocity, life_position(lifes)) {
                        if fallen_balls.count > 0 {
                            lifes += 1;
                            fallen_balls.count -= 1;
                            proj_position = fallen_balls.data[fallen_balls.count];
                            proj_velocity = .{0, 0};
                            particle_burst(proj_rect(proj_position), PROJ_COLOR, PARTICLE_BURST_HIT_COUNT);
                        } else {
                            switch_to_restore_targets();
                        }
                    }
                }
            }

            case .RESTORE_TARGETS; {
                finished := true;
                for *targets {
                    if it.dead {
                        finished = false;
                        if it.waiting > 0 {
                            it.waiting -= dt;
                        } else if attach_to(dt, *it.position, *it.velocity, it.destination) {
                            it.position = it.destination;
                            it.dead = false;
                        }
                    }
                }
                if finished then switch_to_attach_state();
            }
        }
    }
}

render_game :: () {
    render_background();
    render_particles();
    render_targets(state == .RESTORE_TARGETS);

    if state != .GAMEOVER {
        render_proj();
        render_bar();
    }

    // TODO: make the score and lifes semi-transparent when the projectile cross them
    render_lifes();
    render_score();
    render_curtain();
    render_both_popups();

    text_height := cast(int)(TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT);
    if pause {
        pause_text_width := prepare_text("Pause");
        draw_prepared_text(WINDOW_WIDTH/2 - pause_text_width/2, WINDOW_HEIGHT/2 + text_height/4, TEXT_COLOR);
    }

    #if DEBUG {
        debug_text_width := prepare_text("Debug");
        draw_prepared_text(WINDOW_WIDTH - DEBUG_PADDING_RIGHT - debug_text_width, DEBUG_PADDING_TOP + text_height, DEBUG_TEXT_COLOR);
    }
}

Popup :: struct {
    state: enum {
        DISPOSED;
        HIDDEN;
        FADEIN;
        DISPLAY;
        FADEOUT;
    };
    text: string;
    a: float; // 0..1
}

popup_render :: (using popup: *Popup, y: int) {
    alpha : float = ---;
    if state == {
        case .HIDDEN;   return;
        case .FADEIN;   alpha = a;
        case .DISPLAY;  alpha = 1;
        case .FADEOUT;  alpha = 1 - a;
        case .DISPOSED; return;
    }

    color := TEXT_COLOR;
    color.w = alpha;
    text_width := prepare_text(text);
    draw_prepared_text(WINDOW_WIDTH/2 - text_width/2, y, color);
}

popup_update :: (using popup: *Popup, dt: float) {
    if state == {
        case .HIDDEN;  if a < 1.0 then a += dt/POPUP_HIDDEN_TIME;  else { a = 0; state = .FADEIN;  }
        case .FADEIN;  if a < 1.0 then a += dt/POPUP_FADEIN_TIME;  else { a = 0; state = .DISPLAY; }
        case .DISPLAY;
        case .FADEOUT; if a < 1.0 then a += dt/POPUP_FADEOUT_TIME; else { a = 0; state = .DISPOSED; }
        case .DISPOSED;
    }
}

popup_show :: (popup: *Popup, text: string) {
    popup.state = .HIDDEN;
    popup.text = text;
    popup.a = 0;
}

popup_dispose :: (using popup: *Popup) {
    if state == {
        case .HIDDEN; state = .DISPOSED;
        case .FADEIN; {
            a = 1.0 - a;
            state = .FADEOUT;
        }
        case .DISPLAY; {
            a = 0;
            state = .FADEOUT;
        }
        case .FADEOUT;
        case .DISPOSED;
    }
}

Target :: struct {
    position: Vector2;
    destination: Vector2;
    velocity: Vector2;
    waiting: float;
    color: Vector4;
    dead: bool;
}

Particle :: struct {
    position: Vector2;
    velocity: Vector2;
    size_factor: float = 1.0;
    lifetime: float;
    color: Vector4;
}

update_bar :: (dt: float) {
    // TODO: slight ease in/out of the bar movement
    bar_dx = 0;
    if left  then bar_dx += -1;
    if right then bar_dx +=  1;
    bar_collision(dt, proj_rect(proj_position));
}

update_particles :: (dt: float) {
    for * particles {
        if it.lifetime > 0 {
            size := it.size_factor*make_vector2(PARTICLE_BASE_SIZE, PARTICLE_BASE_SIZE);
            ignore_bar := state == .GAMEOVER;
            horz_collision(*it.position, *it.velocity, size, dt, ignore_bar);
            vert_collision(*it.position, *it.velocity, size, dt, ignore_bar);
            it.lifetime -= dt;
        }
    }
}

State_Kind :: enum {
    // Waiting until the player proves that they can move (with A/D keys)
    START;
    // The ball from the life bar rapidly moving towards the paddle to attach to it
    ATTACH;
    // The ball is attached to the paddle and waiting until the player presses SPACE
    READY;
    // Just the usual game play until the ball hits the bottom
    PLAY;
    // Ran out of lifes before destroying all the targets
    GAMEOVER;
    // Start the whole game from scratch
    RESTART;
    // Destroyed all the targets
    VICTORY;
    RESTORE_TARGETS;
}

// The Game itself
left: bool;
right: bool;
particles : [256]Particle;
targets : [..]Target;
fallen_balls : [..]Vector2;
bar_x: float;
bar_dx: float;
proj_position: Vector2;
proj_velocity: Vector2;
score: int;
bonus_score: int;
lifes: int;

// Intermediate values for transitions and stuff
state: State_Kind;
tutorial: bool;
attach_cooldown: float;
victory_cooldown: float;
curtain: float;
primary_popup : Popup;
secondary_popup : Popup;

// Pausing is above any state all the time
pause: bool;

// TODO: speeding up the ball over time
// TODO: sound

some_dead_target :: () -> *Target {
    for *targets if it.dead return it;
    return null;
}

switch_to_start_state :: () {
    proj_position = life_position(lifes);
    proj_velocity = .{0, 0};

    popup_show(*primary_popup, "Press A or D to move around");
    state = .START;
}

switch_to_attach_state :: () {
    proj_position = life_position(lifes);
    proj_velocity = .{0, 0};
    attach_cooldown = 0;

    state = .ATTACH;
}

switch_to_ready_state :: () {
    if tutorial then popup_show(*primary_popup, "Press SPACE to start");
    state = .READY;
}

switch_to_game_over :: () {
    curtain = 0;
    popup_show(*primary_popup, "Game Over");
    state = .GAMEOVER;
}

switch_to_victory :: () {
    victory_cooldown = 0;
    state = .VICTORY;
}

switch_to_restore_targets :: () {
    for *targets {
        it.dead = true;
        it.destination = it.position;
        it.position.y += WINDOW_HEIGHT;
        it.velocity = .{0, 0};
        it.waiting = TARGETS_RESTORE_DELAY*it_index;
    }
    proj_position = life_position(lifes);
    state = .RESTORE_TARGETS;
}

switch_to_play_state :: () {
    if tutorial {
        popup_dispose(*primary_popup);
        tutorial = false;
    }
    // TODO: direct angle factored projectile based on the last direction
    proj_velocity.x = PROJ_SPEED*ANGLE_FACTOR;
    proj_velocity.y = -PROJ_SPEED;
    if left  then proj_velocity.x = -PROJ_SPEED;
    if right then proj_velocity.x = PROJ_SPEED;
    state = .PLAY;
}

switch_to_restart_state :: () {
    popup_dispose(*primary_popup);
    popup_dispose(*secondary_popup);

    center_bar();
    score = 0;
    lifes = 3;
    proj_position = life_position(lifes);
    proj_velocity = .{0, 0};
    for *targets it.dead = false;
    array_reset_keeping_memory(*fallen_balls);

    state = .RESTART;
}

particle_burst :: (area: Rect, color: Vector4, count: int) {
    for 1..count {
        position : Vector2 = ---;
        position.x = area.x + random_get_zero_to_one()*area.w;
        position.y = area.y + random_get_zero_to_one()*area.h;
        particle_emit(position, color);
    }
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

allocate_targets :: () {
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
            t     := cast(float) row/TARGET_ROWS;
            c     := cast(float) (t < level);
            g1    := lerp(red, green, t/level);
            g2    := lerp(green, blue, (t - level)/(1 - level));
            target.color = linear_to_srgb(c*g1 + (1 - c)*g2);

            array_add(*targets, target);
        }
    }
}

center_bar :: () {
    bar_x = WINDOW_WIDTH/2 - BAR_LEN/2;
}

Rect :: struct {
    x: float;
    y: float;
    w: float;
    h: float;
}

make_rect :: (position: Vector2, size: Vector2) -> Rect {
    return make_rect(position.x, position.y, size.x, size.y);
}

make_rect :: (x: float, y: float, w: float, h: float) -> Rect {
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

proj_rect :: (x: float, y: float) -> Rect {
    return make_rect(x, y, PROJ_SIZE, PROJ_SIZE);
}

bar_anchor :: (x: float) -> Vector2 {
    anchor_x := x + BAR_LEN/2 - PROJ_SIZE/2;
    anchor_y := (WINDOW_HEIGHT - PROJ_SIZE - BAR_PADDING_Y_BOTTOM) - BAR_THICCNESS/2 - PROJ_SIZE - 1.0;
    return make_vector2(anchor_x, anchor_y);
}

bar_rect :: (x: float) -> Rect {
    result : Rect = ---;
    result.x = x;
    result.y = (WINDOW_HEIGHT - PROJ_SIZE - BAR_PADDING_Y_BOTTOM) - BAR_THICCNESS/2;
    result.w = BAR_LEN;
    result.h = BAR_THICCNESS;
    return result;
}

sides :: (using rect: Rect) -> float, float, float, float {
    return x, x + w, y, y + h;
}

overlaps :: (a: Rect, b: Rect) -> bool {
    La, Ra, Ta, Ba := sides(a);
    Lb, Rb, Tb, Bb := sides(b);
    return !(Ra < Lb || Rb < La || Ba < Tb || Bb < Ta);
}

all_targets_dead :: () -> bool {
    for targets if !it.dead return false;
    return true;
}

target_hit :: (target: *Target) {
    if target.dead return;
    particle_burst(target_rect(target), target.color, PARTICLE_BURST_HIT_COUNT + bonus_score*2);
    target.dead = true;
    // TODO: indicate how much score points you've got by showing a fading sign with the number at the point of the impact
    score += 1 + bonus_score;
    bonus_score += 1;
    if all_targets_dead() {
        bonus_score = 0;
        switch_to_victory();
    }
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

horz_collision :: (position: *Vector2, velocity: *Vector2, size: Vector2, dt: float, ignore_bar := false) -> Collision {
    nx := position.x + velocity.x*dt;
    if nx < 0 {
        velocity.x *= -1;
        return .BORDER_LEFT;
    }
    if nx + size.x > xx WINDOW_WIDTH {
        velocity.x *= -1;
        return .BORDER_RIGHT;
    }
    if !ignore_bar && overlaps(make_rect(nx, position.y, size.x, size.y), bar_rect(bar_x)) {
        velocity.x *= -1;
        return .BAR;
    }
    for * targets {
        if !it.dead && overlaps(make_rect(nx, position.y, size.x, size.y), target_rect(it)) {
            velocity.x *= -1;
            return xx (xx Collision.TARGET + it_index);
        }
    }
    position.x = nx;
    return .NO;
}

vert_collision :: (position: *Vector2, velocity: *Vector2, size: Vector2, dt: float, ignore_bar := false) -> Collision {
    ny := position.y + velocity.y*dt;
    if ny < 0 {
        velocity.y *= -1;
        return .BORDER_TOP;
    }
    if ny + size.y > xx WINDOW_HEIGHT {
        velocity.y *= -1;
        return .BORDER_BOTTOM;
    }
    if !ignore_bar && state != .GAMEOVER && overlaps(make_rect(position.x, ny, size.x, size.y), bar_rect(bar_x)) {
        velocity.y *= -1;
        return .BAR;
    }
    for *targets {
        if !it.dead && overlaps(make_rect(position.x, ny, size.x, size.y), target_rect(it)) {
            velocity.y *= -1;
            return xx (xx Collision.TARGET + it_index);
        }
    }
    position.y = ny;
    return .NO;
}

bar_collision :: (dt: float, obstacle: Rect) {
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
            bonus_score = 0;
            particle_burst(proj_rect(proj_position), BAR_COLOR, PARTICLE_BURST_HIT_COUNT);
            if bar_dx != 0 {
                proj_velocity.x = bar_dx*PROJ_SPEED;
            } else {
                sign :: inline (x: float) -> float {
                    return xx (-cast(int)(x<0) + cast(int)(x>0));
                }
                proj_velocity.x = sign(proj_velocity.x)*PROJ_SPEED*ANGLE_FACTOR;
            }

        }

        case .BORDER_BOTTOM; {
            array_add(*fallen_balls, proj_position);
            bonus_score = 0;
            particle_burst(proj_rect(proj_position), PROJ_COLOR, PARTICLE_BURST_DEATH_COUNT);
            if lifes > 0 {
                lifes = max(lifes - 1, 0);
                switch_to_attach_state();
            } else {
                particle_burst(bar_rect(bar_x), BAR_COLOR, PARTICLE_BURST_DEATH_COUNT);
                switch_to_game_over();
            }
        }

        case; if c >= .TARGET {
            target_hit(*targets[c - .TARGET]);
        }
    }
}

update_both_popups :: (dt: float) {
    popup_update(*primary_popup, dt);
    popup_update(*secondary_popup, dt);
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

score_text :: (x: int) -> string {
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

draw_horz_line :: (x1: float, x2: float, y: float, thiccness: float, color: Vector4) {
    fill_rect(make_rect(x1, y - thiccness*.5, x2 - x1, thiccness), color);
}

draw_vert_line :: (y1: float, y2: float, x: float, thiccness: float, color: Vector4) {
    fill_rect(make_rect(x - thiccness*.5, y1, thiccness, y2 - y1), color);
}

render_debug_guides :: () {
    draw_horz_line(0, xx WINDOW_WIDTH,  WINDOW_HEIGHT/2.0, DEBUG_LINE_THICCNESS, DEBUG_LINE_COLOR);
    draw_vert_line(0, xx WINDOW_HEIGHT, WINDOW_WIDTH/2.0,  DEBUG_LINE_THICCNESS, DEBUG_LINE_COLOR);
}

render_background :: () {
    fill_rect(make_rect(0, 0, xx WINDOW_WIDTH, xx WINDOW_HEIGHT), BACKGROUND_COLOR);
}

render_particles :: () {
    for particles {
        if it.lifetime > 0 {
            size := make_vector2(PARTICLE_BASE_SIZE, PARTICLE_BASE_SIZE)*it.size_factor;
            color := it.color;
            color.w = it.lifetime/PARTICLE_LIFETIME;
            fill_rect(make_rect(it.position, size), color);
        }
    }
}

render_targets :: (render_all := false) {
    for targets {
        if render_all || !it.dead {
            fill_rect(target_rect(it), it.color);
        }
    }
}

render_proj :: () {
    fill_rect(proj_rect(proj_position), PROJ_COLOR);
}

render_bar :: () {
    fill_rect(bar_rect(bar_x), BAR_COLOR);
}

render_lifes :: () {
    for i: 0..lifes-1 {
        position := life_position(i);
        fill_rect(make_rect(position.x, position.y, LIFE_SIZE, LIFE_SIZE), LIFE_COLOR);
    }
}

render_score :: () {
    // TODO: it would be cool if we could use tprint here, but tprint uses assembly right now
    /* score_text_width := prepare_text(tprint("Score: %", score)); */
    text_height := cast(int)(TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT);
    score_text_width := prepare_text(score_text(score));
    draw_prepared_text(SCORE_PADDING_LEFT, SCORE_PADDING_TOP + text_height, TEXT_COLOR);
}

render_curtain :: () {
    color := BACKGROUND_COLOR;
    color.w = curtain;
    fill_rect(make_rect(0, 0, xx WINDOW_WIDTH, xx WINDOW_HEIGHT), color);
}

render_both_popups :: () {
    if !pause {
        text_height := cast(int)(TEXT_PIXEL_HEIGHT_FACTOR*WINDOW_HEIGHT);
        popup_render(*primary_popup, WINDOW_HEIGHT/2 + text_height/4);
        // TODO: make secondary popup smaller
        popup_render(*secondary_popup, WINDOW_HEIGHT/2 + text_height/4 + text_height + SECONDARY_POPUP_PADDING);
    }
}

