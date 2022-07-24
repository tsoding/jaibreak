const NULL64 = 0n;
let app = document.getElementById("app");
let ctx = app.getContext("2d");
// TODO: read the font size from param.conf somehow
ctx.font = '37px Alegreya-Regular';
let w = null;

function find_name_by_regexp(exports, prefix) {
    const re = new RegExp('^'+prefix+'_[0-9a-z]+$');
    for (let name in exports) {
        if (re.test(name)) {
            return exports[name];
        }
    }
    return null;
}

function make_environment(env) {
    return new Proxy(env, {
        get(target, prop, receiver) {
            if (!env.hasOwnProperty(prop)) {
                return (...args) => {console.error("NOT IMPLEMENTED: "+prop, args)}
            }
            return env[prop];
        }
    });
}

let prepared_text = null;

function hexcolor(r, g, b, a) {
    r = Math.floor(r*255).toString(16).padStart(2, 0);
    g = Math.floor(g*255).toString(16).padStart(2, 0);
    b = Math.floor(b*255).toString(16).padStart(2, 0);
    a = Math.floor(a*255).toString(16).padStart(2, 0);
    return '#'+r+g+b+a;
}

WebAssembly.instantiateStreaming(fetch('./main32.wasm'), {
    "env": make_environment({
        "memset": (s, c, n) => {
            const buffer = w.instance.exports.memory.buffer;
            new Uint8Array(buffer, Number(s), Number(n)).fill(c);
            return s;
        },
        "fill_rect_wasm": (x, y, w, h, r, g, b, a) => {
            ctx.fillStyle = hexcolor(r, g, b, a);
            ctx.fillRect(x, y, w, h);
        },
        "fabs": Math.abs,
        "powf": Math.pow,
        "random_get_zero_to_one": Math.random,
        "random_get_within_range": (a, b) => a + Math.random()*(b - a),
        "platform_prepare_text": (data, count) => {
            const buffer = w.instance.exports.memory.buffer;
            const text = new TextDecoder().decode(new Uint8Array(buffer, Number(data), Number(count)));
            prepared_text = text;
            return BigInt(Math.floor(ctx.measureText(text).width));
        },
        "platform_draw_prepared_text": (x, y, r, g, b, a) => {
            ctx.fillStyle = hexcolor(r, g, b, a);
            ctx.fillText(prepared_text, Number(x), app.height - Number(y));
        }
    })
}).then(w0 => {
    w = w0;
    const init_state  = find_name_by_regexp(w.instance.exports, "init_state");
    const render      = find_name_by_regexp(w.instance.exports, "render");
    const update      = find_name_by_regexp(w.instance.exports, "update");
    const key_press   = find_name_by_regexp(w.instance.exports, "key_press");
    const key_release = find_name_by_regexp(w.instance.exports, "key_release");
    init_state(NULL64);

    let prev = null;
    function first(timestamp) {
        prev = timestamp;
        window.requestAnimationFrame(frame);
    }
    function frame(timestamp) {
        const dt = (timestamp - prev)*0.001;
        prev = timestamp;
        update(NULL64, dt);
        ctx.fillStyle = '#181818';
        ctx.fillRect(0, 0, 1600, 900);
        render(NULL64);
        window.requestAnimationFrame(frame);
    }
    window.requestAnimationFrame(first);

    document.addEventListener('keydown', (e) => key_press(NULL64, e.keyCode));
    document.addEventListener('keyup', (e) => key_release(NULL64, e.keyCode));
}).catch(console.error);
