const std = @import("std");
const Tracker = @import("Tracker.zig");
const Torrent = @import("torrent.zig");
const Peer = @import("Peer.zig");

pub const CoroutineLogger = @import("coroutines/CoroutineLogger.zig").CoroutineLogger;
pub const CoroutinePeerHandler = @import("coroutines/CoroutinePeerHandler.zig").CoroutinePeerHandler;
pub const CoroutineConnectTracker = @import("coroutines/CoroutineConnectTracker.zig").CoroutineConnectTracker;
pub const CoroutineTorrentHandler = @import("coroutines/CoroutineTorrentHandler.zig").CoroutineTorrentHandler;
pub const CoroutineWebsocket = @import("coroutines/CoroutineWebsocket.zig").CoroutineWebsocket;
pub const CoroutineWebserver = @import("coroutines/CoroutineWebserver.zig").CoroutineWebserver;
pub const CoroutineWebclient = @import("coroutines/CoroutineWebclient.zig").CoroutineWebclient;

pub const Coroutine = @This();

pub const CoroutineType = enum {
	coroutineLogger,
	coroutineTorrentHandler,
	coroutineConnectTracker,
	coroutinePeerHandler,
	coroutineWebclient,
	coroutineWebsocket,
	coroutineWebserver,
};

pub const CoroutineData = union(CoroutineType) {
	coroutineLogger: CoroutineLogger,
	coroutineTorrentHandler: CoroutineTorrentHandler,
	coroutineConnectTracker: CoroutineConnectTracker,
	coroutinePeerHandler: CoroutinePeerHandler,
	coroutineWebclient: CoroutineWebclient,
	coroutineWebsocket: CoroutineWebsocket,
	coroutineWebserver: CoroutineWebserver,
};

eventBitfield: EventBitfield,
coroutine: CoroutineData,

pub const EventType = enum {
	eventTorrentAdded,
	eventPeerConnected,
	eventPeerDisconnected,
	eventRequestGlobalState,
	eventPeerStateChange,
	eventPeerHave,
	eventBlockReceived,
	eventRequestReadBlock,
	eventRequestRemoveTorrent,
	eventTorrentRemoved,
};

pub const EventData = union(EventType) {
	eventTorrentAdded: struct {
		hash: [20]u8,
		pieces: u64,
		completed: u64,
	},
	eventPeerConnected: struct {
		peerId: [20]u8,
	},
	eventPeerDisconnected: struct {
		peerId: [20]u8,
	},
	eventRequestGlobalState: struct {
		requester: *Coroutine,
	},
	eventPeerStateChange: struct {
		peerId: [20]u8,
		state: u32,
		pieceCount: u64,
	},
	eventPeerHave: struct {
		peerId: [20]u8,
		have: u64,
	},
	eventBlockReceived: struct {
		hash: [20]u8,
		pieceIdx: u64,
		blockOffset: u64,
		data: []const u8,
	},
	eventRequestReadBlock: struct {
		hash: [20]u8,
		pieceIdx: u64,
		blockOffset: u64,
		data: []u8,
		failed: *bool,
	},
	eventRequestRemoveTorrent: struct {
		hash: [20]u8,
	},
	eventTorrentRemoved: struct {
		hash: [20]u8,
	}
};

pub fn getParentCoroutine(comptime coroutineType: CoroutineType, coroutine: anytype) *Coroutine {
	const parent = @fieldParentPtr(Coroutine.CoroutineData, @tagName(coroutineType), coroutine);
	const parentParent = @fieldParentPtr(Coroutine, "coroutine", parent);
	return parentParent;
}

pub const EventBitfield = std.EnumSet(EventType);

pub fn create(allocator: std.mem.Allocator, comptime coroutineType: CoroutineType, args: anytype) !*@This() {
	var self = try allocator.create(@This());
	self.eventBitfield = @TypeOf(self.eventBitfield).initEmpty();
	const CurrCoroutineType = @TypeOf(@field(self.coroutine, @tagName(coroutineType)));
	self.coroutine = @unionInit(
		@TypeOf(self.coroutine),
		@tagName(coroutineType),
		try @call(.auto, CurrCoroutineType.init, args));
	return self;
}

pub const CoroutineContext = struct {
	allocator: std.mem.Allocator,
	torrents: std.ArrayList(*Torrent),
	coroutineQueue: std.ArrayList(*Coroutine),
	subscriberQueue: std.ArrayList(*Coroutine),

	pub fn init(allocator: std.mem.Allocator) !@This() {
		var self: @This() = undefined;
		self.allocator = allocator;
		self.torrents = std.ArrayList(*Torrent).init(allocator);
		self.coroutineQueue = std.ArrayList(*Coroutine).init(allocator);
		self.subscriberQueue = std.ArrayList(*Coroutine).init(allocator);
		return self;
	}

	pub fn deinit(self: *@This()) void {
		self.coroutineQueue.deinit();
		self.subscriberQueue.deinit();
		for(self.torrents.items) |torrent| {
			std.debug.print("Deinit Torrent!\n", .{});
			torrent.deinit();
			self.allocator.destroy(torrent);
		}
		self.torrents.deinit();
	}

	pub fn addCoroutine(self: *@This(), coro: *Coroutine) !void {
		try self.coroutineQueue.append(coro);
	}

	pub fn subscribe(self: *@This(), bitfield: EventBitfield, comptime coroutineType: CoroutineType, coroutine: anytype) void {
		const parent = getParentCoroutine(coroutineType, coroutine);
		parent.eventBitfield = bitfield;
		self.subscriberQueue.append(parent) catch {};
	}

	pub fn unsubscribe(self: *@This(), comptime coroutineType: CoroutineType, coroutine: anytype) void {
		const parent = getParentCoroutine(coroutineType, coroutine);
		for(self.subscriberQueue.items, 0..) |item, i| {
			if(parent == item) {
				_ = self.subscriberQueue.orderedRemove(i);
				break;
			}
		}
	}

	pub fn publish(self: *@This(), eventData: EventData) void {
		const eventType: EventType = eventData;
		for(self.subscriberQueue.items) |item| {
			if(item.*.eventBitfield.contains(eventType) == true) {
				self.publishDirect(item, eventData);
			}
		}
	}

	pub fn publishDirect(self: *@This(), item: *Coroutine, eventData: EventData) void {
		switch(item.coroutine) {
			inline else => |*item2| {
				if(@hasDecl(@TypeOf(item2.*), "message")) {
					item2.message(self, eventData);
				}
			}
		}
	}
};