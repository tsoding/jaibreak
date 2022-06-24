#import "Basic";
#import "File";
#import "String";
#import "Compiler";
#load "params_loader.jai";

PARAMS_CONF_FILEPATH :: "params.conf";
PARAMS_DYNAMIC_FILEPATH :: "gen_params_dynamic.jai";
PARAMS_STATIC_FILEPATH :: "gen_params_static.jai";

gen_params_static :: () {
    file, success := file_open(PARAMS_STATIC_FILEPATH, for_writing=true);
    if !success {
        print("Could not open file % for writing.\n", PARAMS_STATIC_FILEPATH);
        return;
    }
    file_write(*file, tprint("// Generated from %\n", PARAMS_CONF_FILEPATH));

    for value, name: params {
        if value.tag == {
            case int; file_write(*file, tprint("% : int : %;\n", name, <<(cast(*int) value.bytes.data)));
            case float; file_write(*file, tprint("% : float : %;\n", name, <<(cast(*float) value.bytes.data)));
            // TODO: maybe the printer function (or whatever it is called in Jai, I don't actually know)
            // of Vector4 should put that dot in front of the literal?
            case Vector4; file_write(*file, tprint("% : Vector4 : .%;\n", name, <<(cast(*Vector4) value.bytes.data)));
            case; assert(false, "unreachable");
        }
    }
    file_close(*file);
}

gen_params_dynamic :: () {
    file, success := file_open(PARAMS_DYNAMIC_FILEPATH, for_writing=true);
    if !success {
        print("Could not open file % for writing.\n", PARAMS_DYNAMIC_FILEPATH);
        return;
    }

    file_write(*file, tprint("// Generated from %\n", PARAMS_CONF_FILEPATH));
    for value, name: params {
        if value.tag == {
            case int;     file_write(*file, tprint("% : int = %;\n", name, <<(cast(*int) value.bytes.data)));
            case float;   file_write(*file, tprint("% : float = %;\n", name, <<(cast(*float) value.bytes.data)));
            case Vector4; file_write(*file, tprint("% : Vector4 = .%;\n", name, <<(cast(*Vector4) value.bytes.data)));
            case; assert(false, "unreachable");
        }
    }

    file_write(*file, "sync_param_vars :: () {\n");
    file_write(*file, tprint("    if !load_params_from_file(\"%\") return;\n", PARAMS_CONF_FILEPATH));
    for value, name: params {
        if value.tag == {
            case int;     file_write(*file, tprint("    % = get_param(int, \"%\");\n", name, name));
            case float;   file_write(*file, tprint("    % = get_param(float, \"%\");\n", name, name));
            case Vector4; file_write(*file, tprint("    % = get_param(Vector4, \"%\");\n", name, name));
            case; assert(false, "unreachable");
        }
    }
    file_write(*file, "}\n");
    file_close(*file);
}

build_wasm :: () {
    w := compiler_create_workspace("Jai WASM");
    if !w {
        print("Error: Could not create a workspace\n");
        exit(1);
    }

    bo := get_build_options(w);
    bo.output_executable_name            = "wasm-jai";
    /* bo.dead_code_elimination             = .ALL; */
    bo.stack_trace                       = false;
    /* bo.enable_auto_dereference           = false; */
    bo.use_ansi_color                    = false;
    bo.array_bounds_check                = .OFF;
    bo.cast_bounds_check                 = .OFF;
    bo.math_bounds_check                 = .OFF;
    bo.null_pointer_check                = .OFF;
    bo.emit_debug_info                   = .NONE;
    bo.llvm_options.output_llvm_ir       = true;
    bo.llvm_options.enable_split_modules = false;
    set_build_options(bo, w);

    compiler_begin_intercept(w);

    gen_params_static();

    add_build_string(tprint("DEBUG :: false;"), w);
    add_build_file("gen_params_static.jai", w);
    add_build_file("game.jai", w);
    add_build_file("wasm_platform.jai", w);

    while true {
        message := compiler_wait_for_message();
        if !message break;

        if message.kind == {
            case .TYPECHECKED; {
                typechecked := cast(*Message_Typechecked) message;
                for typechecked.all {
                    for it.subexpressions {
                        if it.kind == .ASM {
                            print("%:%: ASM DETECTED!!!\n",
                                  it.location.enclosing_load.fully_pathed_filename,
                                  it.location.l0);
                        }
                    }
                }
            }

            case .COMPLETE; break;
        }
    }

    compiler_end_intercept(w);
}

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

    gen_params_static();

    add_build_file(PARAMS_STATIC_FILEPATH, w);
    add_build_file("./game.jai", w);
    add_build_file("./simp_platform.jai", w);
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
    add_build_file("params_loader.jai", w);

    gen_params_dynamic();

    add_build_file(PARAMS_DYNAMIC_FILEPATH, w);
    add_build_file("./game.jai", w);
    add_build_file("./simp_platform.jai", w);
}

#run {
    if !load_params_from_file(PARAMS_CONF_FILEPATH) {
        exit(1);
    }

    build_wasm();
    /*
    build_release();
    build_debug();
    */

    set_build_options_dc(.{do_output=false});
}
