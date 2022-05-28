#import "String";
#import "File";
HT :: #import "Hash_Table";
for_expansion :: HT.for_expansion;
TU :: #import "Tagged_Union";

params_content: string;
params: HT.Table(string, TU.Tagged_Union(int, float));

load_params_from_file :: (file_path: string) -> bool {
    content, ok := read_entire_file(file_path);
    if !ok return false;
    free(params_content.data);
    params_content = content;
    HT.table_reset(*params);

    line_number := 0;
    while content.count > 0 {
        line_number += 1;
        _, line, rest_content := split_from_left(content, #char "\n");
        content = rest_content;

        // TODO: support comments

        line = trim(line);
        if line.count == 0 continue;

        found_name, name, rest_line := split_from_left(line, #char ":");
        if !found_name {
            print("%:%: WARNING: could not find parameter name\n", file_path, line_number);
            continue;
        }
        name = trim(name);


        found_type, type, value := split_from_left(rest_line, #char "=");
        if !found_type {
            print("%:%: WARNING: could not find parameter type\n", file_path, line_number);
            continue;
        }

        type = trim(type);
        value = trim(value);
        tagged_x : TU.Tagged_Union(int, float);
        if type == {
            case "float"; {
                x, success, _ := string_to_float(value);
                if !success {
                    print("%:%: WARNING: could not parse float value\n", file_path, line_number);
                    continue;
                }
                TU.set(*tagged_x, x);
            }

            case "int"; {
                x, success, _ := string_to_int(value);
                if !success {
                    print("%:%: WARNING: could not parse int value\n", file_path, line_number);
                    continue;
                }
                TU.set(*tagged_x, x);
            }

            case; {
                print("%:%: WARNING: unknown type `%`\n", file_path, line_number, type);
                continue;
            }

        }
        HT.table_add(*params, name, tagged_x);
    }

    return true;
}

get_param :: ($T: Type, name: string) -> T {
    // TODO: make sure T is within supported types (the ones that are in the Tagged_Union list)
    value, success := HT.table_find(params, name);
    if success return <<(cast(*T) value.bytes.data);
    default: T;
    return default;
}
