const std = @import("std");
const Tracker = @import("../Tracker.zig");
const Torrent = @import("../torrent.zig");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;

pub const CoroutineConnectTracker = struct {
	uri: std.Uri,
	waitTime: i64,
	state: States,
	tracker: Tracker,
	torrent: *Torrent,

	const States = enum {
		Unstarted,
		WaitForConnection,
		WaitForPeers,
		ProcessPeers,
		Done,
	};

	pub fn init(uri: std.Uri, torrent: *Torrent) !@This() {
		var self: @This() = undefined;
		self.uri = uri;
		self.waitTime = 0;
		self.state = .Unstarted;
		self.torrent = torrent;
		return self;
	}

	pub fn deinit(self: *@This(), ctx: *CoroutineContext) void {
		_ = ctx;
		self.tracker.deinit();
	}

	pub fn process(self: *@This(), ctx: *CoroutineContext) !bool {
		switch(self.state) {
			.Unstarted => {
				std.debug.print("START: {s}://{s}\n", .{self.uri.scheme, self.uri.host.?});
				self.waitTime = std.time.milliTimestamp() + std.time.ms_per_s * 10;
				self.state = .WaitForPeers;

				self.tracker = try Tracker.init(ctx.allocator);//self.uri);

				self.tracker.connect(self.uri) catch |err| {
					//ctx.trackerManager.removeTracker(self.tracker);
					std.debug.print("(tracker.connect) Error: {}\n", .{err});
					return true;
				};

				self.state = .WaitForConnection;
			},
			.WaitForConnection => {
				self.tracker.process() catch |err| {
					//ctx.trackerManager.removeTracker(self.tracker);
					std.debug.print("(tracker.process) Error: {}\n", .{err});
					return true;
				};
				if(self.tracker.connected) {
					const torrent = self.torrent.file;
					self.tracker.announce(
						torrent.infoHash,
						torrent.infoHash, 
						0,
						torrent.info.pieces.len,
						0,
						.Started,
						0,
						0xBAADDAAD,
						50,
						0
					) catch |err| {
						//ctx.trackerManager.removeTracker(self.tracker);
						std.debug.print("(tracker.announce) Error: {}\n", .{err});
						return true;
					};
					self.waitTime = std.time.milliTimestamp() + std.time.ms_per_s * 10;
					self.state = .WaitForPeers;
				} else if(self.waitTime < std.time.milliTimestamp()) {
					self.state = .Done;
				}
			},
			.WaitForPeers => {
				self.tracker.process() catch |err| {
					//ctx.trackerManager.removeTracker(self.tracker);
					std.debug.print("(tracker.process) Error: {}\n", .{err});
					return true;
				};
				if(self.tracker.peers.len > 0) {
					self.state = .ProcessPeers;
				} else if(self.waitTime < std.time.milliTimestamp()) {
					self.state = .Done;
				}
			},
			.ProcessPeers => {
				std.debug.print("[{s}] Peers:\n", .{self.uri.host.?});
				for(self.tracker.peers) |peer| {
					std.debug.print("{}\n", .{peer});
					try ctx.coroutineQueue.append(try Coroutine.create(ctx.allocator, .coroutinePeerHandler, .{
						self.torrent,
						self.torrent.file.infoHash,
						std.net.Address.initIp4(peer.address, peer.port),
					}));
				}
				self.state = .Done;
				return false;
			},
			.Done => {
				return true;
			}
		}
		return false;
	}
};