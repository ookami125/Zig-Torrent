const std = @import("std");
const net = @import("network.zig");
pub const InfoHash = [20]u8;
pub const Peer = struct {
	address: [4]u8,
	port: u16,
};

allocator: std.mem.Allocator,

endpoint: net.EndPoint,
connection: ?net.Socket,
packet_stasis: []u8,
packet_stasis_offset: usize,

connected: bool,
connection_type: ConnectionType,

connection_id: u64,
transaction_id: u32,

peers: []Peer,

const ActionID = enum(u32) {
	Connect = 0,
	Announce = 1,
	Scrape = 2,
	Error = 3,
};

pub fn init(allocator: std.mem.Allocator) !@This() {
	var self: @This() = undefined;
	self.allocator = allocator;
	self.connected = false;
	self.connection = null;
	self.connection_id = 0x41727101980;
	self.transaction_id = 0;
	self.packet_stasis = try allocator.alloc(u8, 65535);
	self.packet_stasis_offset = 0;
	self.peers = try allocator.alloc(Peer, 0);
	return self;
}

pub fn deinit(self: @This()) void {
	self.allocator.free(self.peers);
	self.allocator.free(self.packet_stasis);
}

const ConnectionType = enum {
    UNKNOWN,
    UDP,
    HTTP,
    HTTPS,
};

fn getConnectionType(uri: std.Uri) ConnectionType {
    if (uri.port != null) return .UDP;
    if (std.mem.eql(u8, uri.scheme, "http")) return .HTTP;
    if (std.mem.eql(u8, uri.scheme, "https")) return .HTTPS;
    return .UNKNOWN;
}

fn getPort(uri: std.Uri) u16 {
    if (uri.port) |port| return port;
    return switch (getConnectionType(uri)) {
        .HTTP => 80,
        .HTTPS => 443,
        else => 25565,
    };
}

pub fn bytesAvailable(stream: net.Socket) !bool {
	var poll_fd = std.mem.zeroes([1]std.os.pollfd);
	poll_fd[0].fd = stream.internal;
	poll_fd[0].events = 1;
	var ready = try std.os.poll(&poll_fd, 0);
	if(ready == 0) return false;
	return (poll_fd[0].revents & 0x9 != 0x0);
}

pub fn processInteral(self: *@This()) !void {
	if(self.connection == null) return;
	if(!try bytesAvailable(self.connection.?)) return;
	
	const recvFrom = try self.connection.?.receiveFrom(self.packet_stasis);
	const count = recvFrom.numberOfBytes;

	std.debug.print("> RAW: [{}]\n", .{std.fmt.fmtSliceHexLower(self.packet_stasis[0..count])});
	
	const action: ActionID = @enumFromInt(std.mem.readIntBig(u32, self.packet_stasis[0..][0..4]));
	const transaction_id = std.mem.readIntBig(u32, self.packet_stasis[4..][0..4]);
	if(!self.connected) {
		const connection_id = std.mem.readIntBig(u64, self.packet_stasis[8..][0..8]);
		if(action != .Connect) return error.InvalidPacket;
		if(transaction_id != self.transaction_id) return error.InvalidPacket;
		self.connection_id = connection_id;
		self.connected = true;
		std.log.debug("> Connect", .{});
		return;
	}
	
	if(transaction_id != self.transaction_id) return error.InvalidPacket;
	switch(action) {
		ActionID.Announce => {
			if(count <= 20) return error.InvalidPacket;
			if((count - 20) % 6 != 0) return error.InvalidPacket;
			const interval = std.mem.readIntBig(u32, self.packet_stasis[8..][0..4]);
			_ = interval;
			const leechers = std.mem.readIntBig(u32, self.packet_stasis[12..][0..4]);
			_ = leechers;
			const seeders = std.mem.readIntBig(u32, self.packet_stasis[16..][0..4]);
			_ = seeders;
			self.peers = try self.allocator.realloc(self.peers, (count - 20) / 6);
			for(0..((count - 20) / 6)) |i| {
				const address = std.mem.readIntLittle(u32, self.packet_stasis[i*6+20..][0..4]);
				const port = std.mem.readIntBig(u16, self.packet_stasis[i*6+24..][0..2]);
				const addressBytes = std.mem.asBytes(&address);
				std.mem.copyForwards(u8, &self.peers[i].address, addressBytes);
				self.peers[i].port = port;
			}
		},
		else => {},
	}
}

pub fn process(self: *@This()) !void {
	self.processInteral() catch |err| {
		if(err == error.NonCompletePacket) return;
		return err;
	};
}

pub fn connect(self: *@This(), uri: std.Uri) !void {
    self.connection_type = getConnectionType(uri);
    const list = try std.net.getAddressList(self.allocator, uri.host.?, getPort(uri));
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;
    const addr = list.addrs[0];
    self.endpoint = try net.EndPoint.fromSocketAddress(&addr.any, @sizeOf(@TypeOf(addr.any)));
    self.connection = try net.Socket.create(.ipv4, .udp);

	self.transaction_id += 1;

	switch(self.connection_type) {
		.UDP => {
			var sendBuf = std.mem.zeroes([16]u8);
			std.mem.writeIntBig(u64, sendBuf[0..][0..8], self.connection_id);
			std.mem.writeIntBig(u32, sendBuf[8..][0..4], @intFromEnum(ActionID.Connect));
			std.mem.writeIntBig(u32, sendBuf[12..][0..4], self.transaction_id);
			
			var sentLen = try self.connection.?.sendTo(self.endpoint, &sendBuf);
			if(sentLen != sendBuf.len) return error.FailedToSendPacket;
			std.log.debug("< Connect [{s}]", .{std.fmt.fmtSliceHexLower(&sendBuf)});
		},
		else => return error.NotImplemented,
	}
}

pub fn disconnect(self: @This()) !void {
	_ = self;
	
}

pub const AnnounceCoroutine = enum(u32) {
	None = 0,
	Completed = 1,
	Started = 2,
	Stopped = 3,
};

pub fn announce(self: *@This(), infohash: [20]u8, peer_id: [20]u8, downloaded: u64, left: u64, uploaded: u64, coroutine: AnnounceCoroutine, ip_address: u32, key: u32, num_want: u32, port: u16) !void {
	switch(self.connection_type) {
		.UDP => {
			self.transaction_id += 1;

			var sendBuf = std.mem.zeroes([98]u8);
			std.mem.writeIntBig(u64, sendBuf[ 0..][0..@sizeOf(u64)], self.connection_id);
			std.mem.writeIntBig(u32, sendBuf[ 8..][0..@sizeOf(u32)], @intFromEnum(ActionID.Announce));
			std.mem.writeIntBig(u32, sendBuf[12..][0..@sizeOf(u32)], self.transaction_id);
			std.mem.copyForwards(u8, sendBuf[16..][0..20], &infohash);
			std.mem.copyForwards(u8, sendBuf[36..][0..20], &peer_id);
			std.mem.writeIntBig(u64, sendBuf[56..][0..@sizeOf(u64)], downloaded);
			std.mem.writeIntBig(u64, sendBuf[64..][0..@sizeOf(u64)], left);
			std.mem.writeIntBig(u64, sendBuf[72..][0..@sizeOf(u64)], uploaded);
			std.mem.writeIntBig(u32, sendBuf[80..][0..@sizeOf(u32)], @intFromEnum(coroutine));
			std.mem.writeIntBig(u32, sendBuf[84..][0..@sizeOf(u32)], ip_address);
			std.mem.writeIntBig(u32, sendBuf[88..][0..@sizeOf(u32)], key);
			std.mem.writeIntBig(u32, sendBuf[92..][0..@sizeOf(u32)], num_want);
			std.mem.writeIntBig(u16, sendBuf[96..][0..@sizeOf(u16)], port);

			var sentLen = try self.connection.?.sendTo(self.endpoint, &sendBuf);
			if(sentLen != sendBuf.len) return error.FailedToSendPacket;
			std.log.debug("< Announce [{s}]", .{std.fmt.fmtSliceHexLower(&sendBuf)});
		},
		else => return error.NotImplemented,
	}
}