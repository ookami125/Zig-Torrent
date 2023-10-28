const std = @import("std");

const bType = enum {
    //Bool,
    Integer,
    String,
    List,
    Dict,
};

const bError = error{
    NotInteger,
    NotString,
    NotList,
    NotDict,
    SyntaxError,
    NotImplemented,
};

pub fn getBType(bEncodeData: []const u8) bType {
    return switch (bEncodeData[0]) {
        'i' => .Integer,
        'l' => .List,
        'd' => .Dict,
        else => .String,
    };
}

pub fn getBTypeLength(bEncodeData: []const u8) !usize {
    var readOffset: usize = 0;
    switch (getBType(bEncodeData)) {
        .Integer => _ = try GetInt(i64, bEncodeData, &readOffset),
        .String => _ = try GetString(bEncodeData, &readOffset),
        .List, .Dict => _ = {
            readOffset += try GetInternalLength(bEncodeData[1..]) + 2;
        },
    }
    return readOffset;
}

test "getBTypeLength" {
    var data: []const u8 = "d1:ad1:bi32eee";
    try std.testing.expectEqual(getBTypeLength(data), 14);
}

pub fn GetInt(comptime T: type, bEncodeData: []const u8, readCount: ?*usize) !T {
    if (getBType(bEncodeData) != .Integer) return bError.NotInteger;
    var idx = std.mem.indexOf(u8, bEncodeData, "e");
    if (idx == null) return bError.SyntaxError;
    if (readCount) |rc| rc.* += idx.? + 1;
    return try std.fmt.parseInt(T, bEncodeData[1..(idx.?)], 10);
}

test "getInt" {
    var data: []const u8 = "i1337e";
    var readOffset: usize = 0;
    try std.testing.expectEqual(GetInt(i64, data, &readOffset), 1337);
    try std.testing.expectEqual(readOffset, 6);
}

fn GetInternalLength(bEncodeData: []const u8) !usize {
    var readOffset: usize = 0;
    while (bEncodeData[readOffset] != 'e') {
        switch (getBType(bEncodeData[readOffset..])) {
            .Integer => _ = try GetInt(i64, bEncodeData[readOffset..], &readOffset),
            .String => _ = try GetString(bEncodeData[readOffset..], &readOffset),
            .List, .Dict => _ = {
                readOffset += try GetInternalLength(bEncodeData[(readOffset + 1)..]) + 2;
            },
        }
    }
    return readOffset;
}

pub fn GetList(bEncodeData: []const u8, readCount: ?*usize) ![]const u8 {
    if (getBType(bEncodeData) != .List) return bError.NotList;
    var len: usize = try GetInternalLength(bEncodeData[1..]) + 1;
    if (readCount) |rc| rc.* += len + 1;
    return bEncodeData[1..len];
}

test "getList" {
    var data: []const u8 = "li1337ee";
    var readOffset: usize = 0;
    try std.testing.expectEqualStrings(try GetList(data, &readOffset), "i1337e");
    try std.testing.expectEqual(readOffset, 8);
}

pub fn GetString(bEncodeData: []const u8, readCount: ?*usize) ![]const u8 {
    if (getBType(bEncodeData) != .String) return bError.NotString;
    var idx = std.mem.indexOf(u8, bEncodeData, ":");
    if (idx == null) return bError.SyntaxError;
    var strLen: usize = try std.fmt.parseInt(usize, bEncodeData[0..(idx.?)], 10);
    if (readCount) |rc| rc.* += idx.? + 1 + strLen;
    return bEncodeData[(idx.? + 1)..(idx.? + 1 + strLen)];
}

test "GetString" {
    var data: []const u8 = "12:Hello World!";
    var readOffset: usize = 0;
    try std.testing.expectEqualStrings(try GetString(data, &readOffset), "Hello World!");
    try std.testing.expectEqual(readOffset, 15);
}

pub const DictPair = struct {
    key: []const u8,
    value: []const u8,
};

pub const DictIterator = struct {
    buffer: []const u8,
    index: usize,

    const Self = @This();

    /// Returns a slice of the next field, or null if splitting is complete.
    pub fn next(self: *Self) ?DictPair {
        if (self.buffer[self.index] == 'e') return null;
        return .{ .key = GetString(self.buffer[self.index..], &self.index) catch unreachable, .value = blk: {
            var start = self.index;
            var len = getBTypeLength(self.buffer[self.index..]) catch unreachable;
            var end = start + len;
            self.index += len;
            break :blk self.buffer[start..end];
        } };
    }

    /// Resets the iterator to the initial slice.
    pub fn reset(self: *Self) void {
        self.index = 0;
    }
};

pub fn GetDict(bEncodeData: []const u8, readCount: ?*usize) !DictIterator {
    if (getBType(bEncodeData) != .Dict) return bError.NotDict;
    var len: usize = try GetInternalLength(bEncodeData[1..]) + 1;
    if (readCount) |rc| rc.* += len + 1;
    return .{
        .buffer = bEncodeData[1..(1 + len)],
        .index = 0,
    };
}

test "getDict" {
    //var data: []const u8 = "d12:Hello World!i32ee";
    //var readOffset: usize = 0;
    //try std.testing.expectEqualStrings(try GetDict(data, &readOffset), "12:Hello World!i32e");
    //try std.testing.expectEqual(readOffset, 21);
}
