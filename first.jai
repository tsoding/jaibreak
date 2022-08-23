#import "Basic";
#import "File";
#import "String";
#import "Compiler";
#import "BuildCpp";
#import "Process";

#load "./src/params_loader.jai";
#load "./src/i18n.jai";

PARAMS_CONF_FILEPATH :: "params.conf";

gen_params_static :: (params: Params) -> string {
    builder: String_Builder;
    for value, name: params.table {
        if value.tag == {
            case int; print_to_builder(*builder, "% : int : %;\n", name, <<(cast(*int) value.bytes.data));
            case float; print_to_builder(*builder, "% : float : %;\n", name, <<(cast(*float) value.bytes.data));
            // TODO: maybe the printer function (or whatever it is called in Jai, I don't actually know)
            // of Vector4 should put that dot in front of the literal?
            case Vector4; print_to_builder(*builder, "% : Vector4 : .%;\n", name, <<(cast(*Vector4) value.bytes.data));
            // TODO: implement escaping of the string literals when serializing them
            case string; print_to_builder(*builder, "% : string : \"%\";\n", name, <<(cast(*string) value.bytes.data));
            case; assert(false, "unreachable");
        }
    }
    return builder_to_string(*builder);
}

gen_params_dynamic :: (params: Params) -> string {
    builder: String_Builder;

    for value, name: params.table {
        if value.tag == {
            case int;     print_to_builder(*builder, "% : int = %;\n", name, <<(cast(*int) value.bytes.data));
            case float;   print_to_builder(*builder, "% : float = %;\n", name, <<(cast(*float) value.bytes.data));
            case Vector4; print_to_builder(*builder, "% : Vector4 = .%;\n", name, <<(cast(*Vector4) value.bytes.data));
            // TODO: implement escaping of the string literals when serializing them
            case string;  print_to_builder(*builder, "% : string = \"%\";\n", name, <<(cast(*string) value.bytes.data));
            case; assert(false, "unreachable");
        }
    }

    print_to_builder(*builder, "params: Params;\n");
    print_to_builder(*builder, "sync_param_vars :: () {\n");
    print_to_builder(*builder, "    if !reload_params_from_file(*params, \"%\") return;\n", PARAMS_CONF_FILEPATH);
    for value, name: params.table {
        if value.tag == {
            case int;     print_to_builder(*builder, "    % = get_param(params, int, \"%\");\n", name, name);
            case float;   print_to_builder(*builder, "    % = get_param(params, float, \"%\");\n", name, name);
            case Vector4; print_to_builder(*builder, "    % = get_param(params, Vector4, \"%\");\n", name, name);
            case string;  print_to_builder(*builder, "    % = get_param(params, string, \"%\");\n", name, name);
            case; assert(false, "unreachable");
        }
    }
    print_to_builder(*builder, "}\n");
    return builder_to_string(*builder);
}

build_wasm :: (base_name: string) {
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

    CLANG := "clang";
    WASMLD := "wasm-ld";
    WASM64232 := "./3rd_party/wasm64232";

    BC_NAME := tprint("%.bc", base_name);
    O_NAME := tprint("%.o", base_name);

    cmd(CLANG, "--target=wasm64", "-o", O_NAME, "-c", BC_NAME);
    cmd(WASMLD, "-m", "wasm64", "--no-entry", "--export-all", "--allow-undefined", O_NAME, "-o", "./wasm/main64.wasm");
    cmd(WASM64232, "./wasm/main64.wasm", "-o", "./wasm/main32.wasm");
}

prepare_object_file_for_build_wasm :: (w: Workspace) -> string {
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
                        new_statements : [..] *Code_Node;
                        body.block.statements = new_statements;
                        compiler_modify_procedure(w, body);
                    }
                }
            }

            case .PHASE; {
                phase := cast(*Message_Phase) message;
                if phase.phase == .POST_WRITE_EXECUTABLE {
                    assert(phase.compiler_generated_object_files.count == 1, "The build process supports only a single object file compilation");
                    assert(object_file_to_translate_to_wasm.count == 0, "The build process supports only a single object file compilation");
                    object_file_to_translate_to_wasm = phase.compiler_generated_object_files[0];
                }
            }

            case .COMPLETE; break;
        }
    }

    return object_file_to_translate_to_wasm;
}

build_wasm_release :: (params: Params) {
    params_string := gen_params_static(params);
    i18n_string := gen_i18n_static();

    if OS != .LINUX {
        print("TODO: Build WASM platform is only support on Linux right now");
        return;
    }

    if !build_cpp_dynamic_lib("libwasmstub", "src/wasmstub.c") {
        compiler_report("Could not build dynamic lib with external names for WASM");
    }

    w := compiler_create_workspace("Jaibreak WASM Release");
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
    add_build_string(tprint("DEBUG :: false;"), w);
    add_build_string(params_string, w);
    add_build_file("./src/i18n.jai", w);
    add_build_string(i18n_string, w);
    add_build_file("./src/game.jai", w);
    add_build_file("./src/wasm_platform.jai", w);
    object_file_to_translate_to_wasm := prepare_object_file_for_build_wasm(w);
    compiler_end_intercept(w);

    if object_file_to_translate_to_wasm.count > 0 {
        build_wasm(path_strip_extension(object_file_to_translate_to_wasm));
    } else {
        print("Could not generate the object file. Skipping WASM translation step...\n");
    }
}

build_simp_release :: (params: Params) {
    params_string := gen_params_static(params);
    i18n_string := gen_i18n_static();

    w := compiler_create_workspace("Jaibreak Simp Release");
    if !w {
        print("ERROR: Workspace creation failed.\n");
        return;
    }

    target_options := get_build_options(w);
    target_options.output_executable_name = "jaibreak-release";
    set_build_options(target_options, w);

    add_build_string(tprint("DEBUG :: false;"), w);
    add_build_file("./src/i18n.jai", w);
    add_build_string(i18n_string, w);
    add_build_string(params_string, w);
    add_build_file("./src/game.jai", w);
    add_build_file("./src/simp_platform.jai", w);
}

build_simp_debug :: (params: Params) {
    params_string := gen_params_dynamic(params);
    i18n_string := gen_i18n_static();

    w := compiler_create_workspace("Jaibreak Simp Debug");
    if !w {
        print("ERROR: Workspace creation failed.\n");
        return;
    }

    target_options := get_build_options(w);
    target_options.output_executable_name = "jaibreak-debug";
    set_build_options(target_options, w);

    add_build_string(tprint("DEBUG :: true;"), w);
    add_build_file("./src/params_loader.jai", w);
    add_build_string(params_string, w);
    add_build_file("./src/i18n.jai", w);
    add_build_string(i18n_string, w);
    add_build_file("./src/game.jai", w);
    add_build_file("./src/simp_platform.jai", w);
}

gen_i18n_static :: () -> string {
    builder: String_Builder;
    print_to_builder(*builder, "I18N_TABLES : [I18N_LANG_COUNT][I18N_TEXT_COUNT]string : .[\n");
    for lang: enum_names(I18N_Lang) {
        file_path := tprint("i18n/%.conf", lang);
        i18n, ok := load_params_from_file(file_path);
        if !ok then compiler_report(tprint("Could not find translation for lang %", lang));
        print_to_builder(*builder, "    // %\n", lang);
        print_to_builder(*builder, "    .[\n");
        for text: enum_names(I18N_Text) {
            // TODO: report error if the param is not string.
            // TODO: handle the situation when certain translation text is not found
            value := get_param(i18n, string, text);
            print_to_builder(*builder, "        // %\n", text);
            print_to_builder(*builder, "        \"%\",\n", value);
        }
        print_to_builder(*builder, "    ],\n");
    }
    print_to_builder(*builder, "];\n");
    result := builder_to_string(*builder);
    return result;
}

#run {
    params, ok := load_params_from_file(PARAMS_CONF_FILEPATH);
    if !ok then compiler_report(tprint("Could not parse param file %", PARAMS_CONF_FILEPATH));
    defer params_free(*params);

    build_simp_release(params);
    build_simp_debug(params);
    // TODO: document how to build WASM platform
    build_wasm_release(params);

    set_build_options_dc(.{do_output=false});
}
