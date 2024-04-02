const std = @import("std");
const Tracker = @import("Tracker.zig");
const Torrent = @import("torrent.zig");
const Peer = @import("Peer.zig");

pub const CoroutineLogger = @import("coroutines/CoroutineLogger.zig").CoroutineLogger;
pub const CoroutinePeerHandler = @import("coroutines/CoroutinePeerHandler.zig").CoroutinePeerHandler;
pub const CoroutineConnectTracker = @import("coroutines/CoroutineConnectTracker.zig").CoroutineConnectTracker;
pub const CoroutineLoadTorrent = @import("coroutines/CoroutineLoadTorrent.zig").CoroutineLoadTorrent;
pub const CoroutineWebsocket = @import("coroutines/CoroutineWebsocket.zig").CoroutineWebsocket;
pub const CoroutineWebserver = @import("coroutines/CoroutineWebserver.zig").CoroutineWebserver;
pub const CoroutineWebclient = @import("coroutines/CoroutineWebclient.zig").CoroutineWebclient;

pub const Coroutine = @This();

pub const CoroutineType = enum {
	coroutineLogger,
	coroutineLoadTorrent,
	coroutineConnectTracker,
	coroutinePeerHandler,
	coroutineWebclient,
	coroutineWebsocket,
	coroutineWebserver,
};

pub const CoroutineData = union(CoroutineType) {
	coroutineLogger: CoroutineLogger,
	coroutineLoadTorrent: CoroutineLoadTorrent,
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
	eventRequestPeersConnected,
	eventPeerStateChange,
	eventPeerHave,
};

pub const EventData = union(EventType) {
	eventTorrentAdded: struct{},
	eventPeerConnected: struct {
		peerId: [20]u8,
	},
	eventPeerDisconnected: struct {
		peerId: [20]u8,
	},
	eventRequestPeersConnected: struct {},
	eventPeerStateChange: struct {
		peerId: [20]u8,
		am_choking: bool,
		am_interested: bool,
		remote_choking: bool,
		remote_interested: bool,
	},
	eventPeerHave: struct {
		peerId: [20]u8,
		have: u64,
	},
};

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
		//std.debug.print("coroutine(self): {*}\n", .{coroutine});
		//const typed = @TypeOf(coroutine);
		//std.debug.print("Type: {}\n", .{typed});
		const parent = @fieldParentPtr(Coroutine.CoroutineData, @tagName(coroutineType), coroutine);
		//std.debug.print("parent: {*}\n", .{parent});
		const parentParent = @fieldParentPtr(Coroutine, "coroutine", parent);
		//std.debug.print("parentParent: {*}\n", .{parentParent});
		//std.debug.print("parentParent.eventBitfield: {*}\n", .{&(parentParent.eventBitfield)});
		//std.debug.print("parentParent.coroutine: {*}\n", .{&(parentParent.coroutine)});
		parentParent.eventBitfield = bitfield;
		self.subscriberQueue.append(parentParent) catch {};
	}

	pub fn unsubscribe(self: *@This(), comptime coroutineType: CoroutineType, coroutine: anytype) void {
		const parent = @fieldParentPtr(Coroutine.CoroutineData, @tagName(coroutineType), coroutine);
		const parentParent = @fieldParentPtr(Coroutine, "coroutine", parent);
		for(self.subscriberQueue.items, 0..) |item, i| {
			if(parentParent == item) {
				_ = self.subscriberQueue.orderedRemove(i);
				break;
			}
		}
	}

	pub fn publish(self: *@This(), eventData: EventData) void {
		const eventType: EventType = eventData;
		for(self.subscriberQueue.items) |item| {
			if(item.*.eventBitfield.contains(eventType) == true) {
				switch(item.coroutine) {
					inline else => |*item2| {
						if(@hasDecl(@TypeOf(item2.*), "message")) {
							item2.message(self, eventData);
						}
					}
				}
			}
		}
	}
};