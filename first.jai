#import "Basic";
#import "Compiler";

#run {
    w := compiler_create_workspace("JaiBreak");
    if !w {
        print("Workspace creation failed.\n");
        return;
    }

    target_options := get_build_options(w);
    target_options.output_executable_name = "jaibreak";
    set_build_options(target_options, w);
    add_build_file("./jaibreak.jai", w);

    set_build_options_dc(.{do_output=false});
}
