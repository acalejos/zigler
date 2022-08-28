const beam = @import("beam.zig");
const e = @import("erl_nif.zig");
const std = @import("std");

pub fn make(env: beam.env, value: anytype) beam.term {
    const T = @TypeOf(value);
    if (T == beam.env) return value;
    switch (@typeInfo(T)) {
        .Array => return make_array(env, value),
        .Pointer => return make_pointer(env, value),
        .Int => return make_int(env, value),
        .ComptimeInt => return make_comptime_int(env, value),
        .Struct => return make_struct(env, value),
        .EnumLiteral => return make_enum_literal(env, value),
        .Null => return make_nil(env),
        else => {
            std.debug.print("{}\n", .{@typeInfo(T)});
            @panic("unknown type encountered");
        },
    }
}

// TODO: put this in the main namespace.
fn make_nil(env: beam.env) beam.term {
    return .{ .v = e.enif_make_atom(env, "nil") };
}

fn make_array(env: beam.env, value: anytype) beam.term {
    const array = @typeInfo(@TypeOf(value)).Array;

    // u8 arrays (sentinel terminated or otherwise) are treated as
    // strings.
    if (array.child == u8) {
        var result: e.ErlNifTerm = undefined;
        const buf = e.enif_make_new_binary(env, array.len, &result);
        std.mem.copy(u8, buf[0..array.len], value[0..]);
        return .{ .v = result };
    } else {
        @compileError("other arrays not implemented yet");
    }
}

fn make_pointer(env: beam.env, value: anytype) beam.term {
    const pointer = @typeInfo(@TypeOf(value)).Pointer;
    switch (pointer.size) {
        .One => {
            // pointers are only allowed to be decoded if they are string literals.
            const child_info = @typeInfo(pointer.child);
            switch (child_info) {
                .Array => if (child_info.Array.child == u8) {
                    return make_array(env, value.*);
                } else {
                    @compileError("this type is unsupported.");
                },
                else => @compileError("this type is unsupported"),
            }
        },
        .Many => @compileError("not implemented yet"),
        .Slice => @compileError("not implemented yet"),
        .C => @compileError("not implemented yet"),
    }
}

fn make_int(env: beam.env, value: anytype) beam.term {
    const int = @typeInfo(@TypeOf(value)).Int;
    switch (int.signedness) {
        .signed => switch (int.bits) {
            0 => return make_nil(env),
            1...32 => return .{ .v = e.enif_make_int(env, @intCast(i32, value)) },
            33...64 => return .{ .v = e.enif_make_int64(env, @intCast(i64, value)) },
            else => {},
        },
        .unsigned => switch (int.bits) {
            0 => return make_nil(env),
            1...32 => return .{ .v = e.enif_make_uint(env, @intCast(u32, value)) },
            33...64 => return .{ .v = e.enif_make_uint64(env, @intCast(u64, value)) },
            else => {
                const Bigger = std.meta.Int(.unsigned, comptime try std.math.ceilPowerOfTwo(u16, int.bits));
                const buf_size = @sizeOf(Bigger);
                var result: e.ErlNifTerm = undefined;
                var intermediate = @intCast(Bigger, value);
                var buf = e.enif_make_new_binary(env, buf_size, &result);

                // transfer content.
                std.mem.copy(u8, buf.?[0..buf_size], @ptrCast([*]u8, &intermediate)[0..buf_size]);

                return .{ .v = result };
            },
        },
    }
    unreachable;
}

fn make_comptime_int(env: beam.env, value: anytype) beam.term {
    if (value < std.math.minInt(i64)) {
        @compileError("directly making a value less than i64 is not supported");
    }
    if (value < std.math.minInt(i32)) {
        return make_int(env, @as(i64, value));
    }
    if (value < 0) {
        return make_int(env, @as(i32, value));
    }
    if (value <= std.math.maxInt(u32)) {
        return make_int(env, @as(u32, value));
    }
    if (value <= std.math.maxInt(u64)) {
        return make_int(env, @as(u64, value));
    }
    @compileError("directly making a value greater than u64 is not supported");
}

const EMPTY_TUPLE_LIST = [_]beam.term{};

fn make_struct(env: beam.env, value: anytype) beam.term {
    const struct_info = @typeInfo(@TypeOf(value)).Struct;
    _ = env;
    if (struct_info.is_tuple) {
        if (value.len > 16_777_215) {
            @compileError("The tuple size is too large for the erlang virtual machine");
        }
        var tuple_list: [value.len]e.ErlNifTerm = undefined;
        inline for (value) |term, index| {
            if (@TypeOf(value) == beam.term) {
                tuple_list[index] = term.v;
            } else {
                tuple_list[index] = make(env, term).v;
            }
        }
        return .{ .v = e.enif_make_tuple_from_array(env, &tuple_list, value.len) };
    } else {
        const fields = struct_info.fields;
        var result: e.ErlNifTerm = undefined;
        var keys: [fields.len]e.ErlNifTerm = undefined;
        var vals: [fields.len]e.ErlNifTerm = undefined;

        inline for (fields) |field, index| {
            if (field.name.len > 255) {
                @compileError("the length of the struct field name is too large for the erlang virtual machine");
            }
            keys[index] = e.enif_make_atom_len(env, field.name.ptr, field.name.len);
            vals[index] = make(env, @field(value, field.name)).v;
        }

        _ = e.enif_make_map_from_arrays(env, &keys, &vals, fields.len, &result);
        return .{ .v = result };
    }
}

fn make_enum_literal(env: beam.env, value: anytype) beam.term {
    const tag_name = @tagName(value);
    if (tag_name.len > 255) {
        @compileError("the length of this enum literal is too large for the erlang virtual machine");
    }
    return .{ .v = e.enif_make_atom_len(env, tag_name, tag_name.len) };
}
