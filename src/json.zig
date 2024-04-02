const std = @import("std");
const Buffer = std.ArrayList(u8);
const mem = std.mem;
const assert = std.debug.assert;
const TypeId = std.builtin.Type;

fn toJSONacc(allocator: std.mem.Allocator, buf: *Buffer, value: anytype) !void {
    switch (@typeInfo(@TypeOf(value))) {
        .Bool => {
            return buf.appendSlice(if(value) "true" else "false");
        },
        .Float => {
			const temp = try std.fmt.allocPrint(allocator, "{}", .{value});
			return buf.appendSlice(temp);
        },
        .ComptimeInt, .Int => {
			const temp = try std.fmt.allocPrint(allocator, "{}", .{value});
			return buf.appendSlice(temp);
        },
        .Optional => {
            if (value) |payload| {
                return toJSONacc(allocator, buf, payload);
            } else {
                return buf.appendSlice("null");
            }
        },
        .Struct => {
            try buf.append('{');
            comptime var field_i = 0;
			const structInfo = @typeInfo(@TypeOf(value)).Struct;
            inline while (field_i < structInfo.fields.len) : (field_i += 1) {
                if (field_i != 0) {
                    try buf.append(',');
                }
                try toJSONacc(allocator, buf, structInfo.fields[field_i].name);
                try buf.append(':');
                try toJSONacc(allocator, buf, @field(value, structInfo.fields[field_i].name));
            }
            try buf.append('}');
            return;
        },
        .Pointer => |info| switch (info.size) {
            .Slice => {
                if (info.child == u8) blk: {
                    var field_i:usize = 0;
					while (field_i < value.len) : (field_i += 1) {
                        if(!std.ascii.isPrint(value[field_i]))
						{
							break :blk;
						}
                    }
					field_i = 0;
                    try buf.append('"');
					while (field_i < value.len) : (field_i += 1) {
						// TODO: escape
						try buf.append(value[field_i]);
					}
                    try buf.append('"');
                    return;
                }

				{
                    try buf.append('[');
                    var field_i:usize = 0;
                    while (field_i < value.len) : (field_i += 1) {
                        if (field_i != 0) {
                            try buf.append(',');
                        }
                        try toJSONacc(allocator, buf, value[field_i]);
                    }
                    try buf.append(']');
                    return;
                }
            },
            else => try buf.appendSlice("{}"),
			//{
			//	const temp = try std.fmt.allocPrint(allocator, "{}", .{info});
			//	try buf.appendSlice(temp);
			//}
        },
        .Array => {
            return toJSONacc(allocator, buf, value[0..]);
        },
		else => try buf.appendSlice("{}"),
    }
}

pub fn toJSON(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var buf = Buffer.init(allocator);
    try toJSONacc(allocator, &buf, value);
    return buf.toOwnedSlice();
}