const std = @import("std");
const Torrent = @import("../torrent.zig");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;

pub const CoroutineLoadTorrent = struct {
	path: []const u8,

	pub fn init(path: []const u8) !@This() {
		var self: @This() = undefined;
		self.path = path;
		return self;
	}

	pub fn deinit(self: *@This(), ctx: *CoroutineContext) void {
		ctx.allocator.free(self.path);
	}
	
	pub fn process(self: *@This(), ctx: *CoroutineContext) !bool {
		var torrent = try ctx.allocator.create(Torrent);
		std.debug.print("torrent path: {s}\n", .{self.path});
		torrent.* = try Torrent.loadFile(ctx.allocator, self.path);
		try ctx.torrents.append(torrent);

		const announces = if(torrent.file.announce_list) |announce_list| announce_list else @as([*][]const u8, @ptrCast(&torrent.file.announce))[0..1];
		for(announces) |announce| {
			try ctx.coroutineQueue.append(try Coroutine.create(ctx.allocator, .coroutineConnectTracker, .{
				try std.Uri.parse(announce),
				torrent
			}));
		}
		return true;
	}
};