const std = @import("std");
const network = @import("network");
const Tracker = @import("tracker.zig");
const TrackerManager = @This();

const TransactionID = u32;
const Packet = struct {
	manager: *TrackerManager,
	transactionId: TransactionID,
	data: []u8,

	pub fn deinit(self: *@This()) void {
		self.manager.allocator.free(self.data);
	}

	pub fn read(self: *@This(), comptime T: type, offset: usize) T {
		return std.mem.readIntBig(T, self.data[offset..][0..@sizeOf(T)]);
	}

	pub fn write(self: *@This(), comptime T: type, offset: usize, val: T) T {
		return std.mem.writeIntBig(T, self.data[offset..][0..@sizeOf(T)], val);
	}
};

sock: network.Socket,
allocator: std.mem.Allocator,
trackers: [1]Tracker,
packetList: std.AutoArrayHashMap(TransactionID, Packet),
//tempBuffer: [65535]u8,
rnd: std.rand.DefaultPrng,

pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
	try network.init();

	self.sock = try network.Socket.create(.ipv4, .udp);
    try self.sock.enablePortReuse(true);

	self.packetList = std.AutoArrayHashMap(TransactionID, Packet).init(allocator);

	const RndGen = std.rand.DefaultPrng;
    self.rnd = RndGen.init(0);

	self.allocator = allocator;

	try self.sock.setReadTimeout(30_000_000);
}

pub fn deinit(self: *@This()) void {
    defer network.deinit();
	defer self.packetList.deinit();
}

pub fn loop(self: *@This()) !void {
	_ = self;
	
}

pub fn sendTo(self: *@This(), tracker_id: usize, action: u32, packet: []const u8) !TransactionID {
	var transaction_id = self.rnd.random().int(u32);
	var tempBuffer = try self.allocator.alloc(u8, packet.len + 16);
	defer self.allocator.free(tempBuffer);
	std.mem.copyForwards(u8, tempBuffer[16..], packet);
	std.mem.writeIntBig(u64, tempBuffer[0..][0..@sizeOf(u64)], self.trackers[tracker_id].connection_id);
	std.mem.writeIntBig(u32, tempBuffer[8..][0..@sizeOf(u32)], action);
	std.mem.writeIntBig(u32, tempBuffer[12..][0..@sizeOf(u32)], transaction_id);
	_ = try self.sock.sendTo(self.trackers[tracker_id].endpoint, tempBuffer);
	return transaction_id;
}

pub fn receiveFrom(self: *@This(), transactionID: TransactionID) !Packet {
	var buf: [65535]u8 = undefined;
	while(true) {
		var kv = self.packetList.fetchSwapRemove(transactionID);
		if(kv != null) {
			return kv.?.value;
		}
		var recvd = try self.sock.receiveFrom(&buf);
		_ = std.mem.readIntBig(u32, buf[0..][0..@sizeOf(u32)]);
		var tID: TransactionID = std.mem.readIntBig(TransactionID, buf[4..][0..@sizeOf(TransactionID)]);
		var data: []u8 = try self.allocator.alloc(u8, recvd.numberOfBytes - 8);
		std.mem.copyForwards(u8, data, buf[8..recvd.numberOfBytes]);
		try self.packetList.put(tID, .{
			.manager = self,
			.transactionId = tID,
			.data = data,
		});
	}
}

pub fn sendRecv(self: *@This(), tracker_id: usize, action: u32, packet: []const u8) !Packet {	
	var tId = try self.sendTo(tracker_id, action, packet);
	return try self.receiveFrom(tId);
}

pub fn addTracker(self: *@This(), allocator: std.mem.Allocator, uri: std.Uri) !*Tracker {
	var idx: usize = 0;
	self.trackers[idx] = undefined;
	try self.trackers[idx].init(allocator, uri);
	self.trackers[idx].manager = self;
	self.trackers[idx].tracker_id = idx;
	return &self.trackers[idx];
}