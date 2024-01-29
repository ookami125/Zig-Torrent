const std = @import("std");
const Torrent = @import("torrent.zig");
const Peer = @import("peer.zig");
const Tracker = @import("Tracker.zig");
const network = @import("network.zig");
const RangeArray = @import("RangeArray.zig").RangeArray;

const http = std.http;
const Client = std.http.Client;

const PEER_PER_TORRENT: usize = 20;

var peers: std.ArrayList(Peer) = undefined;

pub fn handlePeers() !void {
	var i : usize = 0;
	while(i<peers.items.len) {
		var peer = peers.items[i];
		peer.process() catch {
			_ = peers.swapRemove(i);
			peer.deinit();
			continue;
		};
		if (peer.localState.Unchoked and !peer.waitingForBlock) {
			peer.GetNextBlock() catch {
				_ = peers.swapRemove(i);
				peer.deinit();
				continue;
			};
		}

		i += 1;
	}
}

const EventType = enum {
	eventLoadTorrent,
	eventConnectTracker,
	eventPeerHandler,
};

const EventContext = struct {
	allocator: std.mem.Allocator,
	torrents: std.ArrayList(*Torrent),

	pub fn init(allocator: std.mem.Allocator) !@This() {
		var self: @This() = undefined;
		self.allocator = allocator;
		self.torrents = std.ArrayList(*Torrent).init(allocator);
		return self;
	}

	pub fn deinit(self: *@This()) void {
		for(self.torrents.items) |torrent| {
			std.debug.print("Deinit Torrent!\n", .{});
			torrent.deinit();
			self.allocator.destroy(torrent);
		}
		self.torrents.deinit();
	}
};

const EventPeerHandler = struct {
	log: std.fs.File,
	torrent: *Torrent,
	state: States,
	address: std.net.Address,
	peerID: [20]u8,
	peer: Peer,
	reqs: std.ArrayList(ReqBlocks),
	focusPiece: ?u32,
	prng: std.rand.DefaultPrng,
	rand: std.rand.Random,

	const ReqBlocks = struct {
		time: i64,
		piece_idx: u32,
		piece_offset: u32,
		block_length: u32,
	};

	const States = enum {
		Unstarted,
		WaitForConnection,
		WaitForHandshake,
		Connected,
		Done,
	};

	pub fn init(torrent: *Torrent, peerID: [20]u8, address: std.net.Address) !@This() {
		var self: @This() = undefined;
		self.state = .Unstarted;
		self.torrent = torrent;
		self.peerID = peerID;
		self.address = address;
		self.focusPiece = null;
		self.prng = std.rand.DefaultPrng.init(blk: {
			var longSeed: u128 = @intCast(std.time.nanoTimestamp());
			var seed: u64 = @as(u64, @intCast(longSeed >> 64)) | @as(u64, @intCast(longSeed & 0xFFFFFFFFFFFFFFFF));
			try std.os.getrandom(std.mem.asBytes(&seed));
			break :blk seed;
		});
		self.rand = self.prng.random();
		
		var filename = [10]u8{
			self.rand.intRangeAtMost(u8, 'A', 'Z'),
			self.rand.intRangeAtMost(u8, 'A', 'Z'),
			self.rand.intRangeAtMost(u8, 'A', 'Z'),
			self.rand.intRangeAtMost(u8, 'A', 'Z'),
			self.rand.intRangeAtMost(u8, 'A', 'Z'),
			self.rand.intRangeAtMost(u8, 'A', 'Z'),
			'.', 'l', 'o', 'g',
		};
		
		self.log = try (try std.fs.cwd().openDir("logs", .{})).createFile(&filename, .{});
		return self;
	}

	pub fn deinit(self: *@This()) void {
		for(self.reqs.items) |req| {
			var start = req.piece_idx * self.torrent.file.info.pieceLength + req.piece_offset;
			var end = start + req.block_length;
			self.torrent.notDownloaded.add(start, end) catch |err| {
				std.fmt.format(self.log.writer(),"ERROR: {any}", .{err}) catch |err2| {
					std.log.err("DUAL ERROR: {any}\n {any}", .{err2, err});
				};
			};
		}
	}

	pub fn process(self: *@This(), ctx: *EventContext) !bool {
		switch(self.state) {
			.Unstarted => {
				self.reqs = @TypeOf(self.reqs).init(ctx.allocator);

				self.peer = Peer.init(ctx.allocator, self.peerID, self.torrent.file.infoHash, self.log) catch |err| {
					//self.log.write(bytes: []const u8)
					try std.fmt.format(self.log.writer(),"(Peer.init) Error: {}\n", .{err});
					return true;
				};
				self.peer.connect(self.address) catch |err| {
					try std.fmt.format(self.log.writer(),"(peer.connect) Error: {}\n", .{err});
					return true;
				};
				self.state = .WaitForConnection;
			},
			.WaitForConnection => {
				var connected = self.peer.pollConnected() catch |err| {
					try std.fmt.format(self.log.writer(),"(peer.pollConnected) Error: {}", .{err});
					return true;
				};
				if(connected) {
					self.peer.handshake() catch |err| {
						try std.fmt.format(self.log.writer(),"(peer.handshake) Error: {}\n", .{err});
						return true;
					};
					self.state = .WaitForHandshake;
				}
			},
			.WaitForHandshake => {
				self.peer.process() catch |err| {
					try std.fmt.format(self.log.writer(),"(peer.process) Error: {}\n", .{err});
					return true;
				};
				if(self.peer.processed_handshake) {
					self.peer.interested() catch |err| {
						try std.fmt.format(self.log.writer(),"(peer.interested) Error: {}\n", .{err});
						return true;
					};
					self.state = .Connected;
				}
			},
			.Connected => {
				self.peer.process() catch |err| {
					try std.fmt.format(self.log.writer(),"(peer.process) Error: {}\n", .{err});
					return true;
				};
				if(!self.peer.peer_choking) {
					if(self.peer.received_blocks.items.len > 0) {
						var file = self.torrent.outfile;//try std.fs.cwd().createFile("output.bin", .{.read = true, .truncate = false});
						//defer file.close();

						try std.fmt.format(self.log.writer(),"Recieved Blocks: {}\n", .{self.peer.received_blocks.items.len});
						while(self.peer.received_blocks.popOrNull()) |block| {
							
							var offsetStart = block.piece_idx * self.torrent.file.info.pieceLength + block.piece_offset;
							try file.seekTo(offsetStart);
							try file.writeAll(block.data);

							try self.torrent.downloaded.add(offsetStart, offsetStart + block.data.len);
							try self.torrent.downloaded.merge();
							//try std.fmt.format(self.log.writer(),"Downloaded: {any}\n", .{self.torrent.downloaded});
							//try std.fmt.format(self.log.writer(),"Waiting:    {any}\n", .{self.torrent.notDownloaded});

							block.allocator.free(block.data);
							for(self.reqs.items, 0..) |req, i| {
								if(req.piece_idx == block.piece_idx and req.piece_offset == block.piece_offset and block.data.len == req.block_length)
								{
									_ = self.reqs.swapRemove(i);
									break;
								}
							}
						}
						var sum: u64 = 0;
						for(self.torrent.downloaded.ranges) |range| {
							sum += range.length();
						}
						var percent: f32 = (@as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(self.torrent.getSize()))) * 100.0;
						try std.fmt.format(self.log.writer(),"({}/{}) {d:0>.2}% [{}]\n", .{sum, self.torrent.getSize(), percent, self.torrent.downloaded.ranges.len});
					}

					if(self.torrent.notDownloaded.ranges.len > 0 and self.reqs.items.len < 5) requestBlk: {
						try std.fmt.format(self.log.writer(),"Make more requests: {}\n", .{self.reqs.items.len});
						//var piece_range = RandomIndex(rand, notDownloaded.ranges);
						const Range = @TypeOf(self.torrent.notDownloaded).Range;
						var piece_range: Range = undefined;

						if(self.focusPiece != null) {
							try std.fmt.format(self.log.writer(),"Downloading from focused piece: {}\n", .{self.focusPiece.?});
							var focusPieceOffset = self.focusPiece.? * self.torrent.file.info.pieceLength;
							var focusPieceOffsetEnd = focusPieceOffset + self.torrent.file.info.pieceLength;
							for(self.torrent.notDownloaded.ranges) |range| {
								if(range.start > focusPieceOffset) {
									piece_range = range;
									break;
								}
							} else {
								self.focusPiece = null;
							}
							if(piece_range.start >= focusPieceOffsetEnd or piece_range.start >= self.torrent.file.info.length) {
								self.focusPiece = null;
							}
						}

						if(self.focusPiece == null) {
							try std.fmt.format(self.log.writer(),"Finding new focused piece...\n", .{});
							var largestRange: usize = 0;
							var largestRangeCount: u32 = 0;
							for(self.torrent.notDownloaded.ranges) |range| {
								if(range.length() > largestRange) {
									largestRange = range.length();
									largestRangeCount = 1;
								} else if (range.length() == largestRange) {
									largestRangeCount += 1;
								} 
							}

							if(largestRangeCount == 0) {
								break :requestBlk;
							}
							
							var largestRangeSelected: u32 = if(largestRangeCount==1) 1 else self.rand.intRangeLessThan(u32, 1, largestRangeCount);

							piece_range = blk: {
								var largestRangeTest: usize = 0;
								var largestRangeTestCount: u32 = 0;
								for(self.torrent.notDownloaded.ranges) |range| {
									if(range.length() > largestRangeTest) {
										largestRangeTest = range.length();
										largestRangeTestCount = 1;
									} else if (range.length() == largestRangeTest) {
										largestRangeTestCount += 1;
									} 
									if(largestRangeTest == largestRange and largestRangeSelected == largestRangeTestCount) {
										break :blk range;
									}
								}
								try std.fmt.format(self.log.writer(),"RangeSelected: {}", .{largestRangeSelected});
								try std.fmt.format(self.log.writer(),"RangeSize: {} (?= {})", .{largestRange, largestRangeTest});
								try std.fmt.format(self.log.writer(),"RangeCount: {} (?= {})", .{largestRangeCount, largestRangeTestCount});
								return error.FailedToRefindBlock;
							};
						}

						var block_range = if(piece_range.length() > Peer.MAX_BLOCK_LENGTH) Range.initLen(piece_range.start, Peer.MAX_BLOCK_LENGTH) else piece_range;
						//try std.fmt.format(self.log.writer(),"block_range: {}\n", .{block_range});
						var piece_id: u32 = @intCast(@divTrunc(block_range.start, self.torrent.file.info.pieceLength));

						self.focusPiece = piece_id;

						const byteOffset = @divTrunc(piece_id, 8);
						const bitOffset: u3 = @intCast(7 - @mod(piece_id, 8));
						if(self.peer.remote_pieces) |remote_pieces| {
							const isSet = (remote_pieces[byteOffset] >> bitOffset) & 0x1 == 0x1;
							try std.fmt.format(self.log.writer(),"Attempting to download piece ({})\n", .{isSet});
							if(isSet)
							{
								var block_offset: u32 = @intCast(block_range.start - piece_id * self.torrent.file.info.pieceLength);
								var block_length: u32 = @intCast(block_range.length());
								try self.peer.request(piece_id, block_offset, block_length);
								try self.reqs.append(.{
									.time = std.time.milliTimestamp(),
									.piece_idx = piece_id,
									.piece_offset = block_offset,
									.block_length = block_length,
								});
								try self.torrent.notDownloaded.remove(block_range.start, block_range.end);
							}
						}
					}

					var i : u32 = 0;
					while(i<self.reqs.items.len) {
						var req = self.reqs.items[i];
						if(req.time + 10_000 < std.time.milliTimestamp()) {
							try self.peer.cancel(req.piece_idx, req.piece_offset, req.block_length);
							var start = req.piece_idx * self.torrent.file.info.pieceLength + req.piece_offset;
							var end = start + req.block_length;
							try self.torrent.notDownloaded.add(start, end);
							_ = self.reqs.swapRemove(i);
							continue;
						}
						i+=1;
					}
				
					{
						var sum: u64 = 0;
						for(self.torrent.downloaded.ranges) |range| {
							sum += range.length();
						}
						if(sum == self.torrent.getSize()) {
							try std.fmt.format(self.log.writer(),"Moving onto Done ({}, {})\n", .{self.reqs.items.len, self.torrent.notDownloaded.ranges.len});
							self.state = .Done;
						}
					}
				}
			},
			.Done => {
				try std.fmt.format(self.log.writer(),"!Done\n", .{});
				try self.torrent.outfile.sync();
				return true;
			}
		}
		return false;
	}
};

const EventConnectTracker = struct {
	uri: std.Uri,
	waitTime: i64,
	state: States,
	tracker: Tracker,
	torrent: *Torrent,

	const States = enum {
		Unstarted,
		WaitForConnection,
		WaitForPeers,
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

	pub fn deinit(self: *@This()) void {
		_ = self;
	}

	pub fn process(self: *@This(), ctx: *EventContext) !bool {
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
					self.state = .WaitForPeers;
				}
			},
			.WaitForPeers => {
				self.tracker.process() catch |err| {
					//ctx.trackerManager.removeTracker(self.tracker);
					std.debug.print("(tracker.process) Error: {}\n", .{err});
					return true;
				};
				if(self.tracker.peers.len > 0) {
					self.state = .Done;
				}
			},
			.Done => {
				std.debug.print("[{s}] Peers:\n", .{self.uri.host.?});
				for(self.tracker.peers) |peer| {
					std.debug.print("{}\n", .{peer});
					try eventQueue.append(try Events.create(ctx.allocator, 0, .eventPeerHandler, .{
						self.torrent,
						self.torrent.file.infoHash,
						std.net.Address.initIp4(peer.address, peer.port),
					}));
				}
				return true;
			}
		}
		return false;
	}
};

const EventLoadTorrent = struct {
	path: []const u8,

	pub fn init(path: []const u8) !@This() {
		var self: @This() = undefined;
		self.path = path;
		return self;
	}

	pub fn deinit(self: *@This()) void {
		_ = self;
	}
	
	pub fn process(self: *@This(), ctx: *EventContext) !bool {
		var torrent = try ctx.allocator.create(Torrent);
		torrent.* = try Torrent.loadFile(ctx.allocator, self.path);
		try ctx.torrents.append(torrent);

		const announces = if(torrent.file.announce_list) |announce_list| announce_list else @as([*][]const u8, @ptrCast(&torrent.file.announce))[0..1];
		for(announces) |announce| {
			try eventQueue.append(try Events.create(ctx.allocator, 0, .eventConnectTracker, .{
				try std.Uri.parse(announce),
				torrent
			}));
		}
		return true;
	}
};

const Events = struct {
	prio: u32,
	event: union(EventType) {
		eventLoadTorrent: EventLoadTorrent,
		eventConnectTracker: EventConnectTracker,
		eventPeerHandler: EventPeerHandler,
	},

	pub fn create(allocator: std.mem.Allocator, prio: u32, comptime eventType: EventType, args: anytype) !*@This() {
		var self = try allocator.create(@This());
		self.prio = prio;
		const CurrEventType = @TypeOf(@field(self.event, @tagName(eventType)));
		self.event = @unionInit(
			@TypeOf(self.event),
			@tagName(eventType),
			try @call(.auto, CurrEventType.init, args));
		return self;
	}
};

fn eventSort(_: *EventContext, a: *Events, b: *Events) std.math.Order { return std.math.order(a.prio, b.prio); }
//var eventQueue: std.PriorityQueue(*Events, *EventContext, eventSort) = undefined;
var eventQueue: std.ArrayList(*Events) = undefined;
var context: EventContext = undefined;
var quit = false;

pub fn processingLoop() !void {
	while(!quit) {
		if(eventQueue.items.len == 0) break;
		var _event = eventQueue.orderedRemove(0);
		var event: *Events = _event;
		var done = switch(event.event) {
			inline else => |*ev| try ev.process(&context),
		};
		if(!done) {
			try eventQueue.append(event);
		} else {
			switch(event.event) {
				inline else => |*ev| ev.deinit(),
			}
			eventQueue.allocator.destroy(event);
		}
	}
}

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();

	context = try EventContext.init(allocator);
	defer context.deinit();

	eventQueue = @TypeOf(eventQueue).init(allocator);
	defer eventQueue.deinit();

	var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const dirpath = try std.fs.realpath("./torrents", &path_buffer);
    var dir = try std.fs.cwd().openIterableDir(dirpath, .{});
    var dirIter = dir.iterate();
    var entry = (try dirIter.next()).?;
    const path: []const u8 = try dir.dir.realpath(entry.name, &path_buffer);

	var event = try Events.create(allocator, 0, .eventLoadTorrent, .{path});
	try eventQueue.append(event);

	defer {
		std.debug.print("Shutting down...\n", .{});
	}
	
	return processingLoop();
}

test {
    std.testing.refAllDecls(Torrent);
}
