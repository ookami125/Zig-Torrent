const std = @import("std");
const Tracker = @import("../Tracker.zig");
const Torrent = @import("../torrent.zig");
const Peer = @import("../Peer.zig");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;
const EventBitfield = Coroutine.EventBitfield;
const EventType = Coroutine.EventType;

fn pieceCheck(data: []const u8, pieceHash: Torrent.Hash) bool {
	var buff: Torrent.Hash = undefined;
	std.crypto.hash.Sha1.hash(data, &buff, .{});
	return std.mem.eql(u8, &pieceHash, &buff);
}

fn popCountArray(data: []const u8) u64 {
	var count: u64 = 0;
	for(data.items) |elem| {
		count += @popCount(elem);
	}
	return count;
}

pub const CoroutinePeerHandler = struct {
	log: std.fs.File,
	torrent: *Torrent,
	state: States,
	address: std.net.Address,
	peerID: Torrent.Hash,
	peer: Peer,
	reqs: std.ArrayList(ReqBlocks),
	focusPiece: ?u32,
	prng: std.rand.DefaultPrng,
	bitfield: Torrent.TBitfield,
	lastPieceCount: u32,

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

	pub fn init(torrent: *Torrent, peerID: Torrent.Hash, address: std.net.Address) !@This() {
		var self: @This() = undefined;
		self.state = .Unstarted;
		self.torrent = torrent;
		self.peerID = peerID;
		self.address = address;
		self.focusPiece = null;
		self.lastPieceCount = 0;
		self.prng = std.rand.DefaultPrng.init(blk: {
			const longSeed: u128 = @intCast(std.time.nanoTimestamp());
			var seed: u64 = @as(u64, @intCast(longSeed >> 64)) | @as(u64, @intCast(longSeed & 0xFFFFFFFFFFFFFFFF));
			try std.os.getrandom(std.mem.asBytes(&seed));
			break :blk seed;
		});
		
		var filename = [16]u8{
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),

			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			self.prng.random().intRangeAtMost(u8, 'A', 'Z'),
			'.', 'l', 'o', 'g',
		};
		
		self.log = try (try std.fs.cwd().openDir("logs", .{})).createFile(&filename, .{});
		return self;
	}

	pub fn deinit(self: *@This(), ctx: *CoroutineContext) void {
		self.peer.deinit();
		ctx.unsubscribe(.coroutinePeerHandler, self);
		for(self.reqs.items) |req| {
			const start = req.piece_idx * self.torrent.file.info.pieceLength + req.piece_offset;
			const end = start + req.block_length;
			self.torrent.notDownloaded.add(start, end) catch |err| {
				std.fmt.format(self.log.writer(),"ERROR: {any}", .{err}) catch |err2| {
					std.log.err("DUAL ERROR: {any}\n {any}", .{err2, err});
				};
			};
		}
		self.reqs.deinit();
		ctx.allocator.free(self.bitfield.bytes);
	}

	pub fn message(self: *@This(), ctx: *CoroutineContext, eventData: Coroutine.EventData) void {
		switch (eventData) {
			.eventRequestPeersConnected => ctx.publish(.{
					.eventPeerConnected = .{
						.peerId = self.peer.remote_id,
					},
				}),
			inline else => {},
			//else => {},
		}
	}

	fn processInternal(self: *@This(), ctx: *CoroutineContext) !bool {
		switch(self.state) {
			.Unstarted => {
				self.reqs = @TypeOf(self.reqs).init(ctx.allocator);

				self.peer = Peer.init(ctx.allocator, self.peerID, self.torrent.file.infoHash, @intCast(self.torrent.file.info.pieces.len), self.log) catch |err| {
					//self.log.write(bytes: []const u8)
					try std.fmt.format(self.log.writer(),"(Peer.init) Error: {}\n", .{err});
					return true;
				};

    			const byteCount = Torrent.TBitfield.bytesRequired(self.torrent.file.info.pieces.len);
				const bitfieldBytes = try ctx.allocator.alloc(u8, byteCount);
				@memset(bitfieldBytes, 0);
				self.bitfield = Torrent.TBitfield.init(bitfieldBytes, self.torrent.file.info.pieces.len);

				self.peer.connect(self.address) catch |err| {
					try std.fmt.format(self.log.writer(),"(peer.connect) Error: {}\n", .{err});
					return true;
				};

				ctx.subscribe(EventBitfield.initMany(&[_]EventType{
					.eventRequestPeersConnected,
				}),
				.coroutinePeerHandler,
				self);

				self.state = .WaitForConnection;
			},
			.WaitForConnection => {
				const connected = self.peer.pollConnected() catch |err| {
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
					self.peer.bitfield(self.torrent.bitfield.bytes) catch |err| {
						try std.fmt.format(self.log.writer(),"(peer.bitfield) Error: {}\n", .{err});
						return true;
					};
					std.mem.copyForwards(u8, self.bitfield.bytes, self.torrent.bitfield.bytes);
					self.peer.interested() catch |err| {
						try std.fmt.format(self.log.writer(),"(peer.interested) Error: {}\n", .{err});
						return true;
					};
					ctx.publish(.{
						.eventPeerConnected = .{
							.peerId = self.peer.remote_id,
						},
					});
					self.state = .Connected;
				}
			},
			.Connected => {
				try self.peer.process();

				if(!std.mem.eql(u8, self.bitfield.bytes, self.torrent.bitfield.bytes)) {
					for(0..self.torrent.bitfield.len) |i| {
						if(self.bitfield.get(i) == 0 and self.torrent.bitfield.get(i) == 1) {
							try self.peer.have(@intCast(i));
							self.bitfield.set(i, 1);
						}
					}
				}

				{
					var count: u32 = 0;
					for(self.peer.remote_pieces) |piece| {
						count += @popCount(piece);
					}
					if(count > self.lastPieceCount) {
						// ctx.publish(.{
						// 	.eventPeerUpdated = self,
						// });
						self.lastPieceCount = count;
					}
				}

				if(!self.peer.peer_choking) {
					if(self.peer.received_blocks.items.len > 0) {
						var file = self.torrent.outfile;//try std.fs.cwd().createFile("output.bin", .{.read = true, .truncate = false});
						//defer file.close();

						try std.fmt.format(self.log.writer(),"Recieved Blocks: {}\n", .{self.peer.received_blocks.items.len});
						while(self.peer.received_blocks.popOrNull()) |block| {
							
							const offsetStart = block.piece_idx * self.torrent.file.info.pieceLength + block.piece_offset;
							try file.seekTo(offsetStart);
							try file.writeAll(block.data);

							try self.torrent.downloaded.add(offsetStart, offsetStart + block.data.len);
							try self.torrent.downloaded.merge();

							block.allocator.free(block.data);
							for(self.reqs.items, 0..) |req, i| {
								if(req.piece_idx == block.piece_idx and req.piece_offset == block.piece_offset and block.data.len == req.block_length)
								{
									_ = self.reqs.swapRemove(i);
									break;
								}
							}

							const pieceLen = self.torrent.file.info.pieceLength;
							const downloadOffset = block.piece_idx * pieceLen;
							const downloadOffsetEnd = (block.piece_idx+1) * pieceLen;
							if(self.torrent.downloaded.checkAll(downloadOffset, downloadOffsetEnd)) {
								const temp = try ctx.allocator.alloc(u8, pieceLen);
								defer ctx.allocator.free(temp);
								try self.torrent.outfile.seekTo(downloadOffset);
								_ = try self.torrent.outfile.read(temp);
								if(pieceCheck(temp, self.torrent.file.info.pieces[block.piece_idx])) {
									self.torrent.bitfield.set(block.piece_idx, 1);
								} else {
									std.debug.print("({}) PIECE CHECK FAILED!\n", .{block.piece_idx});
								}
							}
						}
						const sum: u64 = self.torrent.getDownloaded();
						const percent: f32 = (@as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(self.torrent.getSize()))) * 100.0;
						try std.fmt.format(self.log.writer(),"({}/{}) {d:0>.2}% [{}]\n", .{sum, self.torrent.getSize(), percent, self.torrent.downloaded.ranges.len});
					}

					if(self.torrent.notDownloaded.ranges.len > 0 and self.reqs.items.len < 5) requestBlk: {
						//var piece_range = RandomIndex(rand, notDownloaded.ranges);
						const Range = @TypeOf(self.torrent.notDownloaded).Range;
						var piece_range: Range = undefined;

						if(self.focusPiece != null) {
							try std.fmt.format(self.log.writer(),"Downloading from focused piece: {}\n", .{self.focusPiece.?});
							const focusPieceOffset = self.focusPiece.? * self.torrent.file.info.pieceLength;
							const focusPieceOffsetEnd = focusPieceOffset + self.torrent.file.info.pieceLength;
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
							
							//std.debug.assert(!(self.prng.s[0] == 0 and self.prng.s[1] == 0 and self.prng.s[2] == 0 and self.prng.s[3] == 0));
							//self.rand.ptr
							const largestRangeSelected: u32 = if(largestRangeCount==1) 1 else self.prng.random().intRangeLessThan(u32, 1, largestRangeCount);

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
						const piece_id: u32 = @intCast(@divTrunc(block_range.start, self.torrent.file.info.pieceLength));

						self.focusPiece = piece_id;

						const byteOffset = @divTrunc(piece_id, 8);
						const bitOffset: u3 = @intCast(7 - @mod(piece_id, 8));
						const isSet = (self.peer.remote_pieces[byteOffset] >> bitOffset) & 0x1 == 0x1;
						if(isSet)
						{
							try std.fmt.format(self.log.writer(),"Attempting to download piece ({})\n", .{isSet});
							const block_offset: u32 = @intCast(block_range.start - piece_id * self.torrent.file.info.pieceLength);
							const block_length: u32 = @intCast(block_range.length());
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

					var i : u32 = 0;
					while(i<self.reqs.items.len) {
						const req = self.reqs.items[i];
						if(req.time + 10_000 < std.time.milliTimestamp()) {
							try self.peer.cancel(req.piece_idx, req.piece_offset, req.block_length);
							const start = req.piece_idx * self.torrent.file.info.pieceLength + req.piece_offset;
							const end = start + req.block_length;
							try self.torrent.notDownloaded.add(start, end);
							_ = self.reqs.swapRemove(i);
							continue;
						}
						i+=1;
					}
				
				}

				if(self.peer.peer_interested) intrstd_blk: {
					if(self.peer.am_choking) {
						try self.peer.unchoke();
						break :intrstd_blk;
					}

					var block_temp = try ctx.allocator.alloc(u8, 0);
					defer ctx.allocator.free(block_temp);
					for(self.peer.requested_blocks.items) |block| {
						block_temp = try ctx.allocator.realloc(block_temp, block.piece_length);
						try self.torrent.outfile.seekTo(block.piece_idx * self.torrent.file.info.pieceLength + block.piece_offset);
						_ = try self.torrent.outfile.read(block_temp);
						try self.peer.piece(block.piece_idx, block.piece_offset, block_temp);
					}
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
			},
			.Done => {
				try std.fmt.format(self.log.writer(),"!Done\n", .{});
				try self.torrent.outfile.sync();
				ctx.publish(.{
					.eventPeerDisconnected = .{
						.peerId = self.peer.remote_id,
					},
				});
				return true;
			}
		}
		return false;
	}

	pub fn process(self: *@This(), ctx: *CoroutineContext) !bool {
		//std.debug.print("self: {*}\n", .{self});
		return processInternal(self, ctx) catch {
			self.state = .Done;
			return false; 
		};
	}
};
