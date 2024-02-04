const std = @import("std");
const Tracker = @import("Tracker.zig");
const Torrent = @import("torrent.zig");

pub const CoroutineLogger = @import("coroutines/CoroutineLogger.zig").CoroutineLogger;
pub const CoroutinePeerHandler = @import("coroutines/CoroutinePeerHandler.zig").CoroutinePeerHandler;
pub const CoroutineConnectTracker = @import("coroutines/CoroutineConnectTracker.zig").CoroutineConnectTracker;
pub const CoroutineLoadTorrent = @import("coroutines/CoroutineLoadTorrent.zig").CoroutineLoadTorrent;

pub const Coroutine = @This();

prio: u32,
coroutine: union(CoroutineType) {
	coroutineLogger: CoroutineLogger,
	coroutineLoadTorrent: CoroutineLoadTorrent,
	coroutineConnectTracker: CoroutineConnectTracker,
	coroutinePeerHandler: CoroutinePeerHandler,
},

pub fn create(allocator: std.mem.Allocator, prio: u32, comptime coroutineType: CoroutineType, args: anytype) !*@This() {
	var self = try allocator.create(@This());
	self.prio = prio;
	const CurrCoroutineType = @TypeOf(@field(self.coroutine, @tagName(coroutineType)));
	self.coroutine = @unionInit(
		@TypeOf(self.coroutine),
		@tagName(coroutineType),
		try @call(.auto, CurrCoroutineType.init, args));
	return self;
}

pub const CoroutineType = enum {
	coroutineLogger,
	coroutineLoadTorrent,
	coroutineConnectTracker,
	coroutinePeerHandler,
};

pub const CoroutineContext = struct {
	allocator: std.mem.Allocator,
	torrents: std.ArrayList(*Torrent),
	coroutineQueue: std.ArrayList(*Coroutine),

	pub fn init(allocator: std.mem.Allocator) !@This() {
		var self: @This() = undefined;
		self.allocator = allocator;
		self.torrents = std.ArrayList(*Torrent).init(allocator);
		self.coroutineQueue = std.ArrayList(*Coroutine).init(allocator);
		return self;
	}

	pub fn deinit(self: *@This()) void {
		self.coroutineQueue.deinit();
		for(self.torrents.items) |torrent| {
			std.debug.print("Deinit Torrent!\n", .{});
			torrent.deinit();
			self.allocator.destroy(torrent);
		}
		self.torrents.deinit();
	}
};