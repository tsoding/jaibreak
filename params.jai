#import "String";
#import "File";
HT :: #import "Hash_Table";
for_expansion :: HT.for_expansion;
TU :: #import "Tagged_Union";

Param :: struct {
    name: string;
    value: TU.Tagged_Union(int, float);
}

params_content: string = ---;
params: HT.Table(string, TU.Tagged_Union(int, float));

parse_param :: (line: string) -> Param, bool {
    result : Param;

    found_name, name, rest := split_from_left(line, #char ":");
    if !found_name return .{}, false;
    name = trim(name);
    result.name = name;

    found_type, type, value := split_from_left(rest, #char "=");
    if !found_type return .{}, false;
    type = trim(type);
    value = trim(value);

    if type == {
        case "float"; {
            x, success, _ := string_to_float(value);
            if !success return .{}, false;
            TU.set(*result.value, x);
        }

        case "int"; {
            x, success, _ := string_to_int(value);
            if !success return .{}, false;
            TU.set(*result.value, x);
        }

        case; {
            return .{}, false;
        }
    }

    return result, true;
}

Params_Parser :: struct {
    content: string;
    line_number: int;
}

Params_Result :: enum {
    OK;
    EOF;
    EMPTY;
    INVALID;
}

next_param :: (pp: *Params_Parser) -> Param, Params_Result {
    if pp.content.count == 0 return .{}, .EOF;

    pp.line_number += 1;
    _, line, rest := split_from_left(pp.content, #char "\n");
    pp.content = rest;

    line = trim(line);
    if line.count == 0 return .{}, .EMPTY;

    param, ok := parse_param(line);
    if !ok return .{}, .INVALID;

    return param, .OK;
}

load_params_from_file :: (file_path: string) -> bool {
    content, ok := read_entire_file(file_path);
    if !ok return false;
    free(params_content.data);
    params_content = content;
    HT.table_reset(*params);

    pp : Params_Parser;
    pp.content = params_content;
    while true {
        param, result := next_param(*pp);
        if result == {
            case .OK; HT.table_add(*params, param.name, param.value);
            case .EOF; break;
            case .INVALID; print("%:%: WARNING: invalid param\n", PARAMS_FILEPATH, pp.line_number);
        }
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
