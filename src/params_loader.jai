#import "Math";
#import "String";
#import "Math";
#import "File";
HT :: #import "Hash_Table";
for_expansion :: HT.for_expansion;
TU :: #import "Tagged_Union";

Param_Value :: TU.Tagged_Union(int, float, Vector4, string); 
Params :: struct {
    content: string;
    table: HT.Table(string, Param_Value);
}

params_free :: (params: *Params) {
    free(params.content);
    HT.deinit(*params.table);
}

parse_hex_digit :: (b: u8) -> u8, bool {
    if #char "0" <= b && b <= #char "9" return b - #char "0", true;
    if #char "a" <= b && b <= #char "f" return b - #char "a" + 10, true;
    if #char "A" <= b && b <= #char "F" return b - #char "A" + 10, true;
    return 0, false;
}

parse_hex_number :: (bytes: string) -> u64, bool {
    if bytes.count > 16 return 0, false;
    result: u64 = 0;
    for 0..bytes.count-1 {
        b, ok := parse_hex_digit(bytes.data[it]);
        if !ok return 0, false;
        result = result*0x10 + b;
    }
    return result, true;
}

parse_hex_color :: (hex: string) -> Vector4, bool {
    if hex.count != 8 return .{}, false;
    color: Vector4 = ---;
    for 0..3 {
        n, ok := parse_hex_number(slice(hex, it*2, 2));
        if !ok return .{}, false;
        color.component[it] = cast(float) (n&0xFF) / 255.0;
    }
    return color, true;
}

// TODO: implement dynamic params.conf reloading for WASM platform
reload_params_from_file :: (params: *Params, file_path: string) -> bool {
    content, ok := read_entire_file(file_path);
    if !ok {
        print("Error while opening parameters file % for reading\n", file_path);
        return false;
    }
    free(params.content.data);
    params.content = content;
    HT.table_reset(*params.table);

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
            print("%:%: ERROR: could not find parameter name\n", file_path, line_number);
            continue;
        }
        name = trim(name);

        found_type, type, value := split_from_left(rest_line, #char "=");
        if !found_type {
            print("%:%: ERROR: could not find parameter type\n", file_path, line_number);
            continue;
        }

        type = trim(type);
        value = trim(value);
        // TODO: make the program fail at compile time when you add a new type to params
        tagged_x : Param_Value;
        if type == {
            case "float"; {
                x, success, _ := string_to_float(value);
                if !success {
                    print("%:%: ERROR: could not parse float value\n", file_path, line_number);
                    continue;
                }
                TU.set(*tagged_x, x);
            }

            case "int"; {
                x, success, _ := string_to_int(value);
                if !success {
                    print("%:%: ERROR: could not parse int value\n", file_path, line_number);
                    continue;
                }
                TU.set(*tagged_x, x);
            }

            case "color"; {
                color, success := parse_hex_color(value);
                if !success {
                    print("%:%: ERROR: could not parse color value\n", file_path, line_number);
                    continue;
                }
                TU.set(*tagged_x, color);
            }

            case "string"; {
                // TODO: the string literals do not support any form of escaping
                // I'm not sure if they should, tbh.
                if (value.count < 2 || value[0] != #char "\"" || value[value.count - 1] != #char "\"") {
                    print("%:%: ERROR: string must be surrounded by double quotes `\"`\n", file_path, line_number);
                    continue;
                }
                TU.set(*tagged_x, slice(value, 1, value.count - 2));
            }

            case; {
                print("%:%: ERROR: unknown type `%`\n", file_path, line_number, type);
                continue;
            }

        }
        HT.table_add(*params.table, name, tagged_x);
    }

    return true;
}

load_params_from_file :: (file_path: string) -> Params, bool {
    params: Params;
    ok := reload_params_from_file(*params, file_path);
    return params, ok;
}

cast_param_value :: (value: Param_Value, $T: Type) -> T {
    // TODO: make sure T is within supported types (the ones that are in the Tagged_Union list)
    return <<(cast(*T) value.bytes.data);
}

get_param :: (params: Params, $T: Type, name: string) -> T {
    value, success := HT.table_find(*params.table, name);
    if success return cast_param_value(value, T);
    default: T;
    return default;
}
