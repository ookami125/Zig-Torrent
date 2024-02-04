const std = @import("std");
const builtin = @import("builtin");
const net = std.net;

pub const InfoHash = [20]u8;

pub const PeerError = error {
	NonCompletePacket,
	IncompatibleProtocol,
	MismatchedInfohash,
	NotConnected,
	InvalidPackedId,
	NoBytesAvailable,
};

pub fn bytesAvailable(stream: net.Stream) !bool {
	var poll_fd = std.mem.zeroes([1]std.os.pollfd);
	poll_fd[0].fd = stream.handle;
	poll_fd[0].events = std.os.POLL.IN;
	var ready = try std.os.poll(&poll_fd, 0);
	if(ready == 0) return false;
	return (poll_fd[0].revents & std.os.POLL.IN != 0x0);
}

pub fn writable(stream: net.Stream) !bool {
	var poll_fd = std.mem.zeroes([1]std.os.pollfd);
	poll_fd[0].fd = stream.handle;
	poll_fd[0].events = std.os.POLL.OUT;
	var ready = try std.os.poll(&poll_fd, 0);
	if(ready == 0) return false;
	return (poll_fd[0].revents & std.os.POLL.OUT != 0x0);
}

pub const MAX_BLOCK_LENGTH = std.math.pow(u32, 2,14);

pub const Block = struct {
	allocator: std.mem.Allocator,
	piece_idx: u32,
	piece_offset: u32,
	data: []const u8,
};

pub const ReqBlock = struct {
	piece_idx: u32,
	piece_offset: u32,
	piece_length: u32,
};

const PacketId = enum(u8) {
	Choke = 0,
	Unchoke = 1,
	Interested = 2,
	NotInterested = 3,
	Have = 4,
	Bitfield = 5,
	Request = 6,
	Piece = 7,
	Cancel = 8,
	Port = 9,
};

allocator: std.mem.Allocator,

am_choking: bool,
am_interested: bool,
peer_choking: bool,
peer_interested: bool,

id: InfoHash,
infoHash: InfoHash,

peer_connection: ?net.Stream,
packet_stasis: std.ArrayList(u8),
packet_stasis_offset: usize,
processed_handshake: bool,

received_blocks: std.ArrayList(Block),
requested_blocks: std.ArrayList(ReqBlock),
remote_pieces: []u8,

keep_alive_time: i64,

log: std.fs.File,

pub fn init(allocator: std.mem.Allocator, peerID: InfoHash, infoHash: InfoHash, piece_count: u32, log: std.fs.File) !@This() {
	var self: @This() = undefined;
	self.allocator = allocator;
	self.am_choking = true;
	self.am_interested = false;
	self.peer_choking = true;
	self.peer_interested = false;

	self.id = peerID;
	self.infoHash = infoHash;

	self.packet_stasis = std.ArrayList(u8).init(allocator);
	self.packet_stasis_offset = 0; 
	self.processed_handshake = false;

	self.received_blocks = @TypeOf(self.received_blocks).init(allocator);
	self.requested_blocks = @TypeOf(self.requested_blocks).init(allocator);
	self.remote_pieces = try self.allocator.alloc(u8, @divTrunc(piece_count+7, 8));
	@memset(self.remote_pieces, 0);

	self.keep_alive_time = 0;

	self.log = log;
	return self;
}

pub fn deinit(self: *@This()) void {
	self.packet_stasis.deinit();
	self.received_blocks.deinit();
	self.allocator.free(self.remote_pieces);
}

pub fn connect(self: *@This(), address: net.Address) !void {
	try std.fmt.format(self.log.writer(), "Peer {}\n", .{address});
	//self.peer_connection = try net.tcpConnectToAddress(address);
	const nonblock = std.os.SOCK.NONBLOCK;
    const sock_flags = std.os.SOCK.STREAM | nonblock |
        (if (builtin.target.os.tag == .windows) 0 else std.os.SOCK.CLOEXEC);
    const sockfd = try std.os.socket(address.any.family, sock_flags, std.os.IPPROTO.TCP);
    errdefer std.os.closeSocket(sockfd);

	//Timeout is 1 seconds to avoid disconnecting from other peers
	const micros: u32 = 1 * std.time.us_per_s;
	
	if (builtin.target.os.tag == .windows) {
		var val: u32 = @divTrunc(micros, 1000);
		try std.os.windows.setsockopt(sockfd, std.os.SOL.SOCKET, std.os.SO.RCVTIMEO, std.mem.asBytes(&val));
	} else {
		var read_timeout: std.os.timeval = undefined;
		read_timeout.tv_sec = @intCast(@divTrunc(micros, 1000000));
		read_timeout.tv_usec = @intCast(@mod(micros, 1000000));
		try std.os.setsockopt(sockfd, std.os.SOL.SOCKET, std.os.SO.RCVTIMEO, std.mem.toBytes(read_timeout)[0..]);
	}
	
	var server_addr = address.any;
	std.os.connect(sockfd, &server_addr, @sizeOf(@TypeOf(server_addr))) catch |err| {
		if (err != error.WouldBlock) {
			return err;
		}
	};

	self.keep_alive_time = std.time.milliTimestamp();

    self.peer_connection = std.net.Stream{ .handle = sockfd };
}

pub fn pollConnected(self: *@This()) !bool {
	if(self.peer_connection == null) return false;
	var poll_fds = std.mem.zeroes([1]std.os.pollfd);
	poll_fds[0].fd = self.peer_connection.?.handle;
	poll_fds[0].events = std.os.POLL.OUT;
	var result: usize = std.os.poll(&poll_fds, 0) catch |err| blk: {
		if(err != error.WouldBlock) return err;
		break :blk 0;
	};
	if (result == 0 and self.keep_alive_time + 60_000 < std.time.milliTimestamp()) {
		return error.ConnectionTimedOut;
	}
	if(result > 0) {
		if(poll_fds[0].revents & std.os.POLL.ERR > 0) return error.PollFailed;
		if(poll_fds[0].revents & std.os.POLL.NVAL > 0) return error.PollFailed;
		if(poll_fds[0].revents & std.os.POLL.HUP > 0) return error.PollFailed;
		if(poll_fds[0].revents & std.os.POLL.OUT > 0) {
			var flags: usize = try std.os.fcntl(self.peer_connection.?.handle, 3, 0);
			flags &= ~@as(usize, std.os.O.NONBLOCK);
			_ = try std.os.fcntl(self.peer_connection.?.handle, 3, 0);
			return true;
		}
	}
	return false;
}

pub fn disconnect(self: *@This()) void {
	if(self.peer_connection) |conn| {
		conn.close();
	}
	self.peer_connection = null;
	self.am_choking = true;
	self.am_interested = false;
	self.peer_choking = true;
	self.peer_interested = false;
	self.processed_handshake = false;
	self.packet_stasis.clearAndFree();
	self.packet_stasis_offset = 0;

	while(self.received_blocks.popOrNull()) |block| {
		self.allocator.free(block.data);
	}
}

fn readLenFromStream(self: *@This(), len: usize) ![]u8 {
	if(self.packet_stasis_offset + len < self.packet_stasis.items.len) {
		self.packet_stasis_offset += len;
		return self.packet_stasis.items[self.packet_stasis_offset-len..][0..len];
	}
	const lengthNeeded = self.packet_stasis_offset + len - self.packet_stasis.items.len;
	if(!try bytesAvailable(self.peer_connection.?))
		return PeerError.NonCompletePacket;
	try self.packet_stasis.ensureUnusedCapacity(lengthNeeded);
	var read_count = try self.peer_connection.?.read(self.packet_stasis.unusedCapacitySlice()[0..lengthNeeded]);
	if(read_count == 0) {
		self.disconnect();
		return PeerError.NotConnected;
	}
	_ = self.packet_stasis.addManyAsSliceAssumeCapacity(read_count);
	if(read_count == lengthNeeded) {
		self.packet_stasis_offset += len;
		return self.packet_stasis.items[self.packet_stasis_offset-len..][0..len];
	}
	return PeerError.NonCompletePacket;
}

pub fn processInteral(self: *@This()) !void {
	self.packet_stasis_offset = 0;
	if(!self.processed_handshake) {
		//Read Protocol Length
		const protocol_length_raw = try self.readLenFromStream(1);
		const protocol_length = protocol_length_raw[0];
		const protocol = try self.readLenFromStream(protocol_length);
		if(!std.mem.eql(u8, protocol, "BitTorrent protocol"))
			return PeerError.IncompatibleProtocol;
		const reserved_raw = try self.readLenFromStream(8);
		_ = reserved_raw; //Throw away reserved bytes, not used
		const infoHash = try self.readLenFromStream(20);
		if(!std.mem.eql(u8, infoHash, &self.infoHash))
			return PeerError.MismatchedInfohash;
		const peerid = try self.readLenFromStream(20);
		_ = peerid; //Throw away peer id, not needed
		self.processed_handshake = true;
		try std.fmt.format(self.log.writer(), "> Handshake\n", .{});
	} else {
		//Emit keep alive if needed
		if(self.keep_alive_time + 10 * std.time.ms_per_s <= std.time.milliTimestamp()) {
			try self.alive();
		}
		//Read Packet Length
		const packet_length_raw = try self.readLenFromStream(4);
		const packet_length = std.mem.readIntBig(u32, packet_length_raw[0..4]);
		if(packet_length == 0) {
			try std.fmt.format(self.log.writer(), "> Alive\n", .{});
			try self.alive();
			self.packet_stasis.clearRetainingCapacity();
			return;
		}
		const packet = try self.readLenFromStream(packet_length);
		const packet_id: PacketId = @enumFromInt(packet[0]);
		switch(packet_id) {
			.Unchoke => {
				try std.fmt.format(self.log.writer(), "> Unchoked\n", .{});
				self.peer_choking = false;
			},
			.Interested => {
				try std.fmt.format(self.log.writer(), "> Interested\n", .{});
				self.peer_interested = true;
			},
			.Have => {
				try std.fmt.format(self.log.writer(), "> Have\n", .{});
				var index = std.mem.readIntBig(u32, packet[1..5]);
				const byteOffset = @divTrunc(index, 8);
				const bitOffset: u3 = @intCast(7 - @mod(index, 8));
				self.remote_pieces[byteOffset] |= @as(u8,1) << bitOffset;
			},
			.Bitfield => {
				try std.fmt.format(self.log.writer(), "> Bitfield\n", .{});
				const bitfield_byte_count = packet_length-1;
				const bitfield_bit_count = bitfield_byte_count*8;
				_ = bitfield_bit_count;
				//try self.remote_pieces.resize(bitfield_bit_count, false);

				//self.remote_pieces = try self.allocator.alloc(u8, bitfield_byte_count);
				@memset(self.remote_pieces, 0);
				std.mem.copyBackwards(u8, self.remote_pieces, packet[1..]);
			},
			.Request => {
				var index = std.mem.readIntBig(u32, packet[1..5]);
				var begin = std.mem.readIntBig(u32, packet[5..9]);
				var length = std.mem.readIntBig(u32, packet[9..13]);
				if(length > 16384) return error.RequestPacketSizeTooLarge;

				try self.requested_blocks.append(.{
					.piece_idx = index,
					.piece_offset = begin,
					.piece_length = length,
				});
				
				try std.fmt.format(self.log.writer(), "> Request\n", .{});
			},
			.Piece => {
				var index = std.mem.readIntBig(u32, packet[1..5]);
				var begin = std.mem.readIntBig(u32, packet[5..9]);
				var block = packet[9..];
				try self.received_blocks.append(.{
					.allocator = self.allocator,
					.piece_idx = index,
					.piece_offset = begin,
					.data = try self.allocator.dupe(u8, block),
				});
				try std.fmt.format(self.log.writer(), "> Piece({},{},{})\n", .{index, begin, block.len});
			},
			else => {
				try std.fmt.format(self.log.writer(), "Invalid PacketID Recvd: {}\n", .{packet_id});
				return PeerError.InvalidPackedId;
			}
		}
	}
	self.packet_stasis.clearRetainingCapacity();
}

pub fn process(self: *@This()) !void {
	self.processInteral() catch |err| {
		if(err == PeerError.NonCompletePacket) return;
		return err;
	};
}

pub fn processLimit(self: *@This(), limit: usize) !void {
	for(0..limit) |_| {
		self.processInteral() catch |err| {
			if(err == PeerError.NonCompletePacket) return;
			return err;
		};
	}
}

pub fn handshake(self: *@This()) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	const protocol: []const u8 = "BitTorrent protocol";
	var sendBuf = std.mem.zeroes([49 + protocol.len]u8);
	sendBuf[0] = protocol.len;
	std.mem.copyForwards(u8, sendBuf[1..], protocol);
	std.mem.copyForwards(u8, sendBuf[(1 + 8 + protocol.len)..], &self.infoHash);
	std.mem.copyForwards(u8, sendBuf[(1 + 8 + protocol.len + 20)..], &self.id);
	try self.peer_connection.?.writeAll(&sendBuf);
	try std.fmt.format(self.log.writer(), "< Handshake [{s}]\n", .{std.fmt.fmtSliceHexLower(&sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}

pub fn unchoke(self: *@This()) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	var sendBuf = "\x00\x00\x00\x01\x01";
	try self.peer_connection.?.writeAll(sendBuf);
	self.am_choking = false;
	try std.fmt.format(self.log.writer(), "< Unchoke [{s}]\n", .{std.fmt.fmtSliceHexLower(sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}

pub fn interested(self: *@This()) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	var sendBuf = "\x00\x00\x00\x01\x02";
	try self.peer_connection.?.writeAll(sendBuf);
	self.am_interested = true;
	try std.fmt.format(self.log.writer(), "< Interested [{s}]\n", .{std.fmt.fmtSliceHexLower(sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}

pub fn have(self: *@This(), index: u32) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	var sendBuf = std.mem.zeroes([9]u8);
	std.mem.writeIntBig(u32, sendBuf[0..4], 5); //packet length
	std.mem.writeIntBig(u8, sendBuf[4..5], 4); //packet id
	std.mem.writeIntBig(u32, sendBuf[5..9], index); //index
	try self.peer_connection.?.writeAll(&sendBuf);
	try std.fmt.format(self.log.writer(), "< Have [{s}]\n", .{std.fmt.fmtSliceHexLower(&sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}

pub fn bitfield(self: *@This(), bitset: []u8) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	var length: u32 = @intCast(bitset.len);
	var sendBuf = try self.allocator.alloc(u8, 5+length);
	defer self.allocator.free(sendBuf);
	std.mem.writeIntBig(u32, sendBuf[0..4], length+1);
	std.mem.writeIntBig(u8, sendBuf[4..5], '\x05');
	std.mem.copy(u8, sendBuf[5..], bitset);
	try self.peer_connection.?.writeAll(sendBuf);
	try std.fmt.format(self.log.writer(), "< Bitfield [{s}]\n", .{std.fmt.fmtSliceHexLower(sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}

pub fn alive(self: *@This()) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	var sendBuf = "\x00\x00\x00\x00";
	try self.peer_connection.?.writeAll(sendBuf);
	self.am_interested = true;
	try std.fmt.format(self.log.writer(), "< Alive [{s}]\n", .{std.fmt.fmtSliceHexLower(sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}

pub fn request(self: *@This(), index: u32, begin: u32, length: u32) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	var sendBuf = std.mem.zeroes([17]u8);
	std.mem.writeIntBig(u32, sendBuf[0..4], 13); //packet length
	std.mem.writeIntBig(u8, sendBuf[4..5], 6); //packet id
	std.mem.writeIntBig(u32, sendBuf[5..9], index); //index
	std.mem.writeIntBig(u32, sendBuf[9..13], begin); //begin
	std.mem.writeIntBig(u32, sendBuf[13..17], length); //length
	try self.peer_connection.?.writeAll(&sendBuf);
	try std.fmt.format(self.log.writer(), "< Request [{s}]\n", .{std.fmt.fmtSliceHexLower(&sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}

pub fn piece(self: *@This(), index: u32, begin: u32, data: []const u8) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	var length: u32 = @intCast(data.len);
	var sendBuf = try self.allocator.alloc(u8, 13+length);
	defer self.allocator.free(sendBuf);
	std.mem.writeIntBig(u32, sendBuf[0..4], length+1);
	std.mem.writeIntBig(u8, sendBuf[4..5], 7);
	std.mem.writeIntBig(u32, sendBuf[5..9], index);
	std.mem.writeIntBig(u32, sendBuf[9..13], begin);
	std.mem.copy(u8, sendBuf[13..], data);
	try self.peer_connection.?.writeAll(sendBuf);
	try std.fmt.format(self.log.writer(), "< Piece [{s}]\n", .{std.fmt.fmtSliceHexLower(sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}

pub fn cancel(self: *@This(), index: u32, begin: u32, length: u32) !void {
	if(self.peer_connection == null) return PeerError.NotConnected;
	var sendBuf = std.mem.zeroes([17]u8);
	std.mem.writeIntBig(u32, sendBuf[0..4], 13); //packet length
	std.mem.writeIntBig(u8, sendBuf[4..5], 8); //packet id
	std.mem.writeIntBig(u32, sendBuf[5..9], index); //index
	std.mem.writeIntBig(u32, sendBuf[9..13], begin); //begin
	std.mem.writeIntBig(u32, sendBuf[13..17], length); //length
	try self.peer_connection.?.writeAll(&sendBuf);
	try std.fmt.format(self.log.writer(), "< Cancel [{s}]\n", .{std.fmt.fmtSliceHexLower(&sendBuf)});
	self.keep_alive_time = std.time.milliTimestamp();
}