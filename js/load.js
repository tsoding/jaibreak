const NULL64 = 0n;
const EBADF = 9;

let app = document.getElementById("app");
let ctx = app.getContext("2d");
// TODO: read the font size from param.conf somehow
ctx.font = '37px Alegreya-Regular';

let w = null;
let context = null;
let output_buffer = "";

function find_name_by_regexp(exports, prefix) {
    const re = new RegExp('^'+prefix+'_[0-9a-z]+$');
    for (let name in exports) {
        if (re.test(name)) {
            return exports[name];
        }
    }
    return null;
}

function make_environment(...envs) {
    return new Proxy(envs, {
        get(target, prop, receiver) {
            for (let env of envs) {
                if (env.hasOwnProperty(prop)) {
                    return env[prop];
                }
            }
            return (...args) => {console.error("NOT IMPLEMENTED: "+prop, args)}
        }
    });
}

const std = {
    "write": (fd, buf, count) => {
        let log = undefined;
        switch (fd) {
            case 1: log = console.log;   break;
            case 2: log = console.error; break;
            default: {
                console.error("write: Unsupported file descriptor "+fd);
                return -EBADF;
            }
        }
        const buffer = w.instance.exports.memory.buffer;
        const bytes = new Uint8Array(buffer, Number(buf), Number(count));
        let text = new TextDecoder().decode(bytes);
        let index = text.indexOf('\n');
        while (index >= 0) {
            output_buffer += text.slice(0, index);
            text = text.slice(index + 1);
            log(output_buffer);
            output = "";
            index = text.indexOf('\n');
        }
        if (text.length > 0) output_buffer += text;
        return count;
    },
    "memset": (s, c, n) => {
        const buffer = w.instance.exports.memory.buffer;
        const bytes = new Uint8Array(buffer, Number(s), Number(n));
        bytes.fill(c);
        return s;
    },
    "fabs": Math.abs,
    "powf": Math.pow,
    "set_context": (c) => context = c,
};

// Game runtime
const game = {
    "fill_rect_wasm": (x, y, w, h, r, g, b, a) => {
        ctx.fillStyle = hexcolor(r, g, b, a);
        ctx.fillRect(x, y, w, h);
    },
    "random_get_zero_to_one": Math.random,
    "random_get_within_range": (a, b) => a + Math.random()*(b - a),
    "prepare_text_wasm": (data, count) => {
        const buffer = w.instance.exports.memory.buffer;
        const text = new TextDecoder().decode(new Uint8Array(buffer, Number(data), Number(count)));
        prepared_text = text;
        return BigInt(Math.floor(ctx.measureText(text).width));
    },
    "draw_prepared_text_wasm": (x, y, r, g, b, a) => {
        ctx.fillStyle = hexcolor(r, g, b, a);
        ctx.fillText(prepared_text, Number(x), app.height - Number(y));
    }
};

let prepared_text = null;

function hexcolor(r, g, b, a) {
    r = Math.floor(r*255).toString(16).padStart(2, 0);
    g = Math.floor(g*255).toString(16).padStart(2, 0);
    b = Math.floor(b*255).toString(16).padStart(2, 0);
    a = Math.floor(a*255).toString(16).padStart(2, 0);
    return '#'+r+g+b+a;
}

WebAssembly.instantiateStreaming(fetch('./wasm/main32.wasm'), {
    "env": make_environment(std, game)
}).then(w0 => {
    w = w0;
    const update      = find_name_by_regexp(w.instance.exports, "update");
    const key_press   = find_name_by_regexp(w.instance.exports, "key_press");
    const key_release = find_name_by_regexp(w.instance.exports, "key_release");

    w.instance.exports.main(0, NULL64);

    let prev = null;
    function first(timestamp) {
        prev = timestamp;
        window.requestAnimationFrame(frame);
    }
    function frame(timestamp) {
        const dt = (timestamp - prev)*0.001;
        prev = timestamp;
        // TODO: move rendering of the background out of the platforms
        ctx.fillStyle = '#181818';
        ctx.fillRect(0, 0, 1600, 900);
        update(context, dt);
        window.requestAnimationFrame(frame);
    }
    window.requestAnimationFrame(first);

    document.addEventListener('keydown', (e) => { key_press(context, e.keyCode) });
    document.addEventListener('keyup', (e) => { key_release(context, e.keyCode) });
}).catch(console.error);
