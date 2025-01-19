const NULL64 = 0n;
const EBADF = 9;

let app = document.getElementById("app");
let ctx = app.getContext("2d");
// TODO: read the font size from param.conf somehow
// I think the entire font management has to be moved out of the platforms to fascilitate that
ctx.font = '37px Alegreya-Regular';

let w = null;              // the WASM module
let context = 0n;        // the Jai context (the one that contains the allocator, logger, etc)
let output_buffer = "";    // buffer for write() "syscalls"
let prepared_text = null;  // prepared text for rendering by Simp

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
    // TODO: write() does not print stack traces adequately when an assertion fails or something
    // The easiest way to reproduce is to make an allocator that always returns `null`
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
    "memcpy": (dest_ptr, src_ptr, n) => {
        const buffer = w.instance.exports.memory.buffer;
        const src = new Uint8Array(buffer, Number(src_ptr), Number(n));
        const dest = new Uint8Array(buffer, Number(dest_ptr), Number(n));
        dest.set(src);
        return dest_ptr;
    },
    "fabs": Math.abs,
    "powf": Math.pow,
    "sqrtf": Math.sqrt,
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
        ctx.fillText(prepared_text, Number(x), Number(y));
    },
    "get_heap_base": () => {
        return w.instance.exports.__heap_base.value;
    }
};

function clamp(low, high, value) {
    return Math.min(Math.max(low, value), high);
}

function hexcolor(r, g, b, a) {
    r = clamp(0, 255, Math.floor(r*255)).toString(16).padStart(2, 0);
    g = clamp(0, 255, Math.floor(g*255)).toString(16).padStart(2, 0);
    b = clamp(0, 255, Math.floor(b*255)).toString(16).padStart(2, 0);
    a = clamp(0, 255, Math.floor(a*255)).toString(16).padStart(2, 0);
    return '#'+r+g+b+a;
}

// TODO: some sort of an indication that the page is loading
WebAssembly.instantiateStreaming(fetch('./wasm/main32.wasm'), {
    "env": make_environment(std, game)
}).then(w0 => {
    w = w0;
    const update      = find_name_by_regexp(w.instance.exports, "update");
    const key_press   = find_name_by_regexp(w.instance.exports, "key_press");
    const key_release = find_name_by_regexp(w.instance.exports, "key_release");
    console.log(w.instance);

    w.instance.exports.main(
        0,     // argc
        NULL64 // argv
    );

    let prev = null;
    function first(timestamp) {
        prev = timestamp;
        window.requestAnimationFrame(frame);
    }
    function frame(timestamp) {
        const dt = (timestamp - prev)*0.001;
        prev = timestamp;
        update(context, dt);
        window.requestAnimationFrame(frame);
    }
    window.requestAnimationFrame(first);

    document.addEventListener('keydown', (e) => {
        switch (e.key) {
        case "ArrowLeft":  key_press(context, 130); break;
        case "ArrowRight": key_press(context, 131); break;
        default:           key_press(context, e.keyCode);
        }
    });
    document.addEventListener('keyup', (e) => {
        switch (e.key) {
        case "ArrowLeft":  key_release(context, 130); break;
        case "ArrowRight": key_release(context, 131); break;
        default:           key_release(context, e.keyCode);
        }
    });
}).catch(console.error);
