const std = @import("std");
const Self = @This();

prev: ?*Self,
next: ?*Self,
start: usize,
end: usize,

pub fn write(self: *@This(), allocator: std.mem.Allocator, start: usize, end: usize) !void {
    if (start > self.end) return self.next.?.write(allocator, start, end);
    if (start < self.start or end > self.end) {
        std.debug.print("[Error] Writing ({}, {}) to ({}, {})", .{ start, end, self.start, self.end });
        return error.WriteNotValid;
    }
    if (start == self.start and end == self.end) {
        std.debug.print("DEBUG: remove self ({}, {})\n", .{ self.start, self.end });
        if (self.prev) |prev| prev.next = self.next;
        if (self.next) |next| next.prev = self.prev;
        return allocator.destroy(self);
    } else if ((start == self.start) != (end == self.end)) {
        if (start == self.start) {
            std.debug.print("DEBUG: update start {} -> {}\n", .{ self.start, end });
            self.start = end;
        } else {
            std.debug.print("DEBUG: update end {} -> {}\n", .{ self.end, start });
            self.end = start;
        }
    } else {
        var newNode = try allocator.create(@This());
        std.debug.print("DEBUG: new node ({}, {})\n", .{ end, self.end });
        newNode.* = .{
            .prev = self,
            .next = self.next,
            .start = end,
            .end = self.end,
        };
        std.debug.print("DEBUG: update end {} -> {}\n", .{ self.end, start });
        self.end = start;
        if (self.next) |next| {
            next.prev = newNode;
        }
        self.next = newNode;
    }
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    if (self.next) |next| {
        next.deinit(allocator);
        allocator.destroy(next);
    }
}

fn print(self: *@This()) void {
    var node = self;
    for (0..5) |_| {
        std.debug.print("({},{}]", .{ node.start, node.end });
        if (node.next) |next| {
            node = next;
        } else break;
        std.debug.print("->", .{});
    }
    std.debug.print("\n", .{});
}

test "write" {
    var list: Self = .{
        .prev = null,
        .next = null,
        .start = 0,
        .end = 32,
    };
    defer list.deinit(std.testing.allocator);
    std.debug.print("\n", .{});

    list.print();
    //00000000000000000000000000000000

    try list.write(std.testing.allocator, 4, 8);
    //write(4, 8)

    list.print();
    //00001111000000000000000000000000
    //(0,3]->(8,32]

    try list.write(std.testing.allocator, 12, 16);
    //write(12, 16)

    list.print();
    //00001111000011110000000000000000
    //(0,3]->(8,12]->(16,32)

    try list.write(std.testing.allocator, 8, 12);
    //write(8, 12)

    list.print();
    //00001111111111110000000000000000
    //(0,3]->(16,32)

    try list.write(std.testing.allocator, 2, 4);
    //write(2, 4)

    list.print();
    //00111111111111110000000000000000
    //(0,2]->(16,32)

    try list.write(std.testing.allocator, 16, 24);
    //write(16, 24)

    list.print();
    //00111111111111111111111100000000
    //(0,2]->(16,32)
}
