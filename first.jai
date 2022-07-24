#import "Basic";
#import "File";
#import "String";
#import "Compiler";
#import "BuildCpp";
#import "Process";
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
    defer file_close(*file);
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

cmd :: (args: .. string, redirect_stdout_to_file := "", loc := #caller_location) {
    log("[CMD] %\n", get_quoted_command_string(args));

    result, output_string, error_string := run_command(..args, capture_and_return_output = redirect_stdout_to_file != "");
    if result.exit_code {
        if output_string then log("%", output_string);
        if error_string then log("%", error_string);
        compiler_report(tprint("Command failed with exit code '%'.\n", result.exit_code), loc);
        exit(result.exit_code);
    }

    if redirect_stdout_to_file then write_entire_file(redirect_stdout_to_file, output_string);
}

build_wasm :: (base_name: string) {
    CLANG := "clang";
    WASMLD := "wasm-ld";
    WASM64232 := "./3rd_party/wasm64232";

    BC_NAME := tprint("%.bc", base_name);
    O_NAME := tprint("%.o", base_name);

    cmd(CLANG, "--target=wasm64", "-o", O_NAME, "-c", BC_NAME);
    cmd(WASMLD, "-m", "wasm64", "--no-entry", "--export-all", "--allow-undefined", O_NAME, "-o", "main64.wasm");
    cmd(WASM64232, "main64.wasm", "-o", "main32.wasm");
}

build_wasm_platform :: () {
    if !build_cpp_dynamic_lib("libwasmstub", "wasmstub.c") {
        print("Error: Could not build dynamic lib with external names");
        exit(1);
    }

    w := compiler_create_workspace("Jaibreak WASM");
    if !w {
        print("Error: Could not create a workspace\n");
        exit(1);
    }

    bo := get_build_options(w);
    bo.output_executable_name            = "jaibreak-wasm";
    bo.llvm_options.output_bitcode       = true;
    bo.llvm_options.enable_split_modules = false;
    set_build_options(bo, w);

    compiler_begin_intercept(w);

    gen_params_static();

    add_build_string(tprint("DEBUG :: false;"), w);
    add_build_file("gen_params_static.jai", w);
    add_build_file("game.jai", w);
    add_build_file("wasm_platform.jai", w);

    object_file_to_translate_to_wasm := "";
    while true {
        message := compiler_wait_for_message();
        if !message break;

        if message.kind == {
            case .TYPECHECKED; {
                typechecked := cast(*Message_Typechecked) message;
                for typechecked.procedure_bodies {
                    contains_asm := false;
                    for it.subexpressions {
                        if it.kind == .ASM {
                            // NOTE: #asm blocks are not translatable to WASM, we need to remove them
                            compiler_report("ASM DETECTED!!!", make_location(it), .WARNING);
                            contains_asm = true;
                        }
                    }
                    if contains_asm {
                        body := it.expression;
                        // TODO: delete only the ASM blocks
                        // I'm just too lazy to write such a surgically precise code right now, sorry
                        compiler_report(tprint("Removing the whole body of the function %. DON'T USE IT!!!", body.header.name),
                                        make_location(body),
                                        .WARNING);
                        // TODO: replace the body of the deleted function with something that indicates at runtime that you are calling to a deleted function
                        new_statements : [..] *Code_Node;
                        body.block.statements = new_statements;
                        compiler_modify_procedure(w, body);
                    }
                }
            }

            case .PHASE; {
                phase := cast(*Message_Phase) message;
                if phase.phase == .POST_WRITE_EXECUTABLE {
                    assert(phase.compiler_generated_object_files.count == 1);
                    assert(object_file_to_translate_to_wasm.count == 0);
                    object_file_to_translate_to_wasm = phase.compiler_generated_object_files[0];
                }
            }

            case .COMPLETE; break;
        }
    }
    assert(object_file_to_translate_to_wasm.count > 0);

    build_wasm(path_strip_extension(object_file_to_translate_to_wasm));

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

    // TODO: document how to build WASM platform
    build_wasm_platform();
    build_release();
    build_debug();

    set_build_options_dc(.{do_output=false});
}
