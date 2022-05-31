#import "Basic";
#import "File";
#import "String";
#import "Compiler";
#load "params.jai";

PARAMS_FILEPATH :: "params.conf";

build_release :: () {
    w := compiler_create_workspace("JaiBreak Release");
    if !w {
        print("ERROR: Workspace creation failed.\n");
        return;
    }

    target_options := get_build_options(w);
    target_options.output_executable_name = "jaibreak-release";
    set_build_options(target_options, w);

    add_build_string(tprint("DEBUG :: false;"), w);
    for value, name: params {
        if value.tag == {
            case int; add_build_string(tprint("% : int : %;", name, <<(cast(*int) value.bytes.data)), w);
            case float; add_build_string(tprint("% : float : %;", name, <<(cast(*float) value.bytes.data)), w);
            // TODO: maybe the printer function (or whatever it is called in Jai, I don't actually know)
            // of Vector4 should put that dot in front of the literal?
            case Vector4; add_build_string(tprint("% : Vector4 : .%;", name, <<(cast(*Vector4) value.bytes.data)), w);
            case; assert(false, "unreachable");
        }
    }

    add_build_file("./jaibreak.jai", w);
}

build_debug :: () {
    w := compiler_create_workspace("JaiBreak Debug");
    if !w {
        print("ERROR: Workspace creation failed.\n");
        return;
    }

    target_options := get_build_options(w);
    target_options.output_executable_name = "jaibreak-debug";
    set_build_options(target_options, w);

    add_build_string(tprint("DEBUG :: true;"), w);

    file, success := file_open("sync_params.jai", for_writing=true);
    if !success {
        print("Could not open file sync_params.jai for writing.\n");
        return;
    }
    defer(file_close(*file));

    file_write(*file, "#load \"params.jai\";\n");

    for value, name: params {
        if value.tag == {
            case int;     file_write(*file, tprint("% : int;\n", name));
            case float;   file_write(*file, tprint("% : float;\n", name));
            case Vector4; file_write(*file, tprint("% : Vector4;\n", name));
            case; assert(false, "unreachable");
        }
    }

    file_write(*file, "sync_param_vars :: () {\n");
    for value, name: params {
        if value.tag == {
            case int;     file_write(*file, tprint("    % = get_param(int, \"%\");\n", name, name));
            case float;   file_write(*file, tprint("    % = get_param(float, \"%\");\n", name, name));
            case Vector4; file_write(*file, tprint("    % = get_param(Vector4, \"%\");\n", name, name));
            case; assert(false, "unreachable");
        }
    }
    file_write(*file, "}\n");
    add_build_file("./sync_params.jai", w);
    add_build_file("./jaibreak.jai", w);
}

#run {
    HT.init(*params);
    load_params_from_file(PARAMS_FILEPATH);

    build_release();
    build_debug();

    set_build_options_dc(.{do_output=false});
}
