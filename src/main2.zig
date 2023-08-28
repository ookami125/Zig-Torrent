const std = @import("std");
const Torrent = @import("torrent.zig");
const network = @import("network.zig");

torrents: std.AutoArrayHashMap([20]u8, Torrent),

const PeerState = packed struct {
	Unchoked: bool,
	Interested: bool,
};

const TBitfield = std.packed_int_array.PackedIntSliceEndian(u1, std.builtin.Endian.Big);

const Peer = struct {
	allocator: std.mem.Allocator,
	torrent: *const Torrent,
	sock: network.Socket,
	handshake: bool,
	bitfielded: bool,
	pieceByteCount: []u32,
	bitfield: TBitfield,
	remoteBitfield: TBitfield,
	remoteState: PeerState, //instructions sent to remote
	localState: PeerState, //instructions sent to self
	
	//temp
	file: std.fs.File,
	recvFile: std.fs.File,

	pub fn init(self: *@This(), allocator: std.mem.Allocator, torrent: *const Torrent) !void {
		
		self.allocator = allocator;

		self.torrent = torrent;

		self.sock = try network.Socket.create(.ipv4, .tcp);
    	try self.sock.enablePortReuse(true);
		//try self.sock.bindToPort(51444);
		try self.sock.connect(try network.EndPoint.parse("127.0.0.1:58241"));
		try self.sock.setReadTimeout(1);

		self.handshake = false;
		self.bitfielded = false;

		self.pieceByteCount = try allocator.alloc(u32, torrent.info.pieces.len);
		for(0..self.pieceByteCount.len) |i| {
			self.pieceByteCount[i] = 0;
		}
		var bitfieldBytes = try allocator.alloc(u8, try std.math.divCeil(usize, torrent.info.pieces.len, 8));
		@memset(bitfieldBytes, 0);
		self.bitfield = TBitfield.init(bitfieldBytes, torrent.info.pieces.len);
		for(0..torrent.info.pieces.len) |i| {
			self.bitfield.set(i, 0);
		}

		var remoteBitfieldBytes = try allocator.alloc(u8, try std.math.divCeil(usize, torrent.info.pieces.len, 8));
		@memset(remoteBitfieldBytes, 0);
		self.remoteBitfield = TBitfield.init(remoteBitfieldBytes, torrent.info.pieces.len);

		self.localState = .{ .Unchoked = false, .Interested = false };
		self.remoteState = .{ .Unchoked = false, .Interested = false };

		self.file = try std.fs.cwd().createFile(
			"torrent.bin",
			.{ .read = false },
		);

		self.recvFile = try std.fs.cwd().createFile(
			"recv.bin",
			.{ .read = false },
		);

		//Attempt handshake and connection
		const protocol: []const u8 = "BitTorrent protocol";
		var sendBuf = std.mem.zeroes([49 + protocol.len]u8);
		sendBuf[0] = protocol.len;
		std.mem.copyForwards(u8, sendBuf[1..], protocol);
		std.mem.copyForwards(u8, sendBuf[(1+8+protocol.len)..], &torrent.infoHash);
		std.mem.copyForwards(u8, sendBuf[(1+8+protocol.len+20)..], &torrent.infoHash);
		_ = try self.sock.send(&sendBuf);

		//var scratch = std.mem.zeroes([49+255]u8);
		//var recvInfo = try self.sock.receive(&scratch);
		//std.debug.print("{any}\n", .{scratch[0..recvInfo]});
	}

	pub fn deinit(self: *@This()) void {
		self.pieceBitset.deinit();
		self.sock.close();
	}

	pub fn parsePacket(self: *@This(), data: []const u8) !usize {
		if(self.handshake == false) {
			var protocolNameLen = data[0];
			var protocolName = data[1..][0..protocolNameLen];
			std.debug.print("Protocol Name: {s}\n", .{protocolName});
			var infoHash = data[(1+protocolNameLen+8)..][0..20];
			var peerId = data[(1+protocolNameLen+8+20)..][0..20];
			std.debug.print("Info Hash: {any}\n", .{infoHash});
			std.debug.print("Peer ID: {any}\n", .{peerId});
			self.handshake = true;
			return 49+protocolNameLen;
		}
		var size: u32 = std.mem.readIntBig(u32, data[0..4]);
		if(size == 0) {
			std.debug.print("keep alive!\n", .{});
			_ = try self.sock.send("\x00\x00\x00\x00");
			return 4;
		}
		std.debug.print("packet: {}\n\tsize: {d}\n", .{ data[4], size});
		if(size > 20_000) {
			std.debug.print("packet({}): {any}\n", .{size, data});
			return error.PacketSizeToBig;
		}
		switch(data[4]) {
			0 => { //choke
				std.debug.print("choke\n", .{});
				self.localState.Unchoked = false;
			},
			1 => { //unchoke
				std.debug.print("unchoke\n", .{});
				self.localState.Unchoked = true;
			},
			2 => { //interested
				std.debug.print("interested\n", .{});
				self.localState.Interested = true;
			},
			3 => { //not interested
				std.debug.print("not interested\n", .{});
				self.localState.Interested = false;
			},
			4 => { //have
				std.debug.print("have\n", .{});
				var pieceIdx = std.mem.readIntBig(u32, data[5..][0..4]);
				self.bitfield.bytes[pieceIdx] = 1;
			},
			5 => { //bitfield
				if (self.bitfielded) return error.BitfieldAlreadyRecvd;
				self.bitfielded = true;
				std.debug.print("bitfield\n", .{});
				//std.debug.print("Packet: {any}\n", .{data});
				std.mem.copyForwards(u8, self.remoteBitfield.bytes, data[5..size]);
			},
			6 => { //request
				std.debug.print("request\n", .{});
			},
			7 => { //piece
				var pieceIdx = std.mem.readIntBig(u32, data[5..9]);
				var beginOffset = std.mem.readIntBig(u32, data[9..13]);
				//std.debug.print("piece ({}, {}, {})\n", .{pieceIdx, beginOffset, size});
				self.pieceByteCount[pieceIdx] = beginOffset + size - 9;
				if(self.pieceByteCount[pieceIdx] == self.torrent.info.pieceLength) {
					self.bitfield.set(pieceIdx, 1);
					try self.Have(pieceIdx);
				}
				try self.file.writeAll(data[13..]);
			},
			8 => { //cancel
				std.debug.print("cancel\n", .{});
			},
			else => return error.InvalidPacketID,
		}
		return size + 4;
	}

	pub fn Choke(self: *@This()) !void {
		std.debug.print("Sending Choke...\n", .{});
		_ = try self.sock.send("\x00\x00\x00\x01\x00");
		self.remoteState.Unchoked = false;
	}

	pub fn Unchoke(self: *@This()) !void {
		std.debug.print("Sending Unchoke...\n", .{});
		_ = try self.sock.send("\x00\x00\x00\x01\x01");
		self.remoteState.Unchoked = true;
	}

	pub fn Interested(self: *@This()) !void {
		std.debug.print("Sending Interested...\n", .{});
		_ = try self.sock.send("\x00\x00\x00\x01\x02");
		self.remoteState.Interested = true;
	}

	pub fn NotInterested(self: *@This()) !void {
		std.debug.print("Sending Not Interested...\n", .{});
		_ = try self.sock.send("\x00\x00\x00\x01\x03");
		self.remoteState.Interested = false;
	}

	pub fn Have(self: *@This(), pieceIdx: u32) !void {
		std.debug.print("Sending Have({d})...\n", .{pieceIdx});
		var data: [9]u8 = undefined;
		std.mem.copyForwards(u8, data[0..], "\x00\x00\x00\x05\x04");
		std.mem.writeIntBig(u32, data[5..][0..4], pieceIdx);
		_ = try self.sock.send(&data);
	}

	pub fn Bitfield(self: *@This()) !void {
		std.debug.print("Sending Bitfield...\n", .{});
		var length: u32 = @intCast(self.bitfield.bytes.len);
		var data: []u8 = try self.allocator.alloc(u8, length + 1 + 4);
		defer self.allocator.free(data);
		std.mem.writeIntBig(u32, data[0..][0..4], length + 1);
		std.mem.copyForwards(u8, data[4..], "\x05");
		std.mem.copyForwards(u8, data[5..], self.bitfield.bytes);
		_ = try self.sock.send(data);
	}

	pub fn GetNextBlock(self: *@This()) !void {
		var piece: u32 = 0;
		var offset: u32 = 0;
		for(self.pieceByteCount, 0..) |bytes, i| {
			var pieceLen = self.torrent.info.pieceLength;
			if(i == self.torrent.info.pieces.len - 1) {
				pieceLen = @intCast(self.torrent.info.length - self.torrent.info.pieceLength * (self.torrent.info.pieces.len - 1));
				//std.debug.print("{} {}\n", .{bytes, pieceLen});
			}
			if(bytes < pieceLen) {
				piece = @intCast(@as(u64, i));
				offset = bytes;
				break;
			}
		} else {
			return error.NoPieceLeft;
		}
		try self.GetBlock(piece, offset);
	}

	pub fn GetBlock(self: *@This(), piece: u32, offset: u32) !void {
		std.debug.print("Send Get Block ({d}, {d})...\n", .{piece, offset});
		var pieceLen = self.torrent.info.pieceLength;
		var length: u32 = 1<<14;
		if(offset + length > pieceLen) {
			length = pieceLen - offset;
		}
		var data: [17]u8 = undefined;
		std.mem.copyForwards(u8, data[0..], "\x00\x00\x00\x0d\x06");
		std.mem.writeIntBig(u32, data[5..][0..4], piece);
		std.mem.writeIntBig(u32, data[9..][0..4], offset);
		std.mem.writeIntBig(u32, data[13..][0..4], length);
		_ = try self.sock.send(&data);
	}

	pub fn process(self: *@This()) !bool {
		var scratch: [65527]u8 = undefined;
		@memset(scratch[0..], 0);
		var numberOfBytes = self.sock.receive(&scratch) catch |err| {
			if(err == network.Socket.ReceiveError.WouldBlock) {
				return false;
			}
			return err;
		};
		std.debug.print("numberOfBytes: {}\n", .{numberOfBytes});
		std.debug.print("bytes 0-4: {{{any}, {any}, {any}, {any}, {any}}}\n", .{scratch[0], scratch[1], scratch[2], scratch[3], scratch[4]});
		_ = try self.recvFile.write(scratch[0..numberOfBytes]);
		var bytesUsed: usize = 0;
		while(bytesUsed < numberOfBytes) {
			std.debug.print("offset: {}\n", .{bytesUsed});
			bytesUsed += self.parsePacket(scratch[bytesUsed..numberOfBytes]) catch |err| {
				if(err == error.PacketSizeToBig) {
					return err;
				}
				break;
			};
		}
		return true;
	}
};

pub fn main() !void {
	var gp = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();

    const stdin = std.io.getStdIn().reader();
    _ = stdin;

    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
	const path = try std.fs.realpath("./torrents/cosmos-laundromat.torrent", &path_buffer); 
	var torrent = try Torrent.loadFile(allocator, path);
	defer torrent.deinit();

	//std.debug.print("{} - {} * {} = {}\n", .{
	//	torrent.info.length,
	//	torrent.info.pieceLength,
	//	torrent.info.pieces.len,
	//	torrent.info.length - torrent.info.pieceLength * (torrent.info.pieces.len - 1)
	//});

	var peer: Peer = undefined;
	//defer peer.deinit();
	try peer.init(allocator, &torrent);
	_ = try peer.process();
	//try peer.Bitfield();
	//try peer.process();
	try peer.Interested();
	while(true) {
		if(try peer.process()) {
			try peer.GetNextBlock();
		}
		std.time.sleep(40_000_000);
	}
}