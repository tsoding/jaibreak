#import "Basic";
#import "File";
#import "String";
#import "Compiler";
#load "params.jai";

PARAMS_FILEPATH :: "params.conf";
DEBUG :: true;

#run {
    HT.init(*params);
    load_params_from_file(PARAMS_FILEPATH);



    w := compiler_create_workspace("JaiBreak");
    if !w {
        print("ERROR: Workspace creation failed.\n");
        return;
    }

    target_options := get_build_options(w);
    target_options.output_executable_name = "jaibreak";
    set_build_options(target_options, w);

    if !DEBUG {
        add_build_string(tprint("DEBUG :: false;"), w);
        for value, name: params {
            if value.tag == {
                case int; add_build_string(tprint("% :: () -> int { return %; };", name, <<(cast(*int) value.bytes.data)), w);
                case float; add_build_string(tprint("% :: () -> float { return %; };", name, <<(cast(*float) value.bytes.data)), w);
                case; assert(false, "unreachable");
            }
        }
    } else {
        add_build_string(tprint("#load \"params.jai\";"), w);
        add_build_string(tprint("DEBUG :: true;"), w);
        for value, name: params {
            if value.tag == {
                case int;   add_build_string(tprint("% :: () -> int { return get_int_param(\"%\"); };", name, name), w);
                case float; add_build_string(tprint("% :: () -> float { return get_float_param(\"%\"); };", name, name), w);
                case; assert(false, "unreachable");
            }
        }
    }

    add_build_file("./jaibreak.jai", w);

    set_build_options_dc(.{do_output=false});
}
