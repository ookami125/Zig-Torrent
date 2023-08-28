const std = @import("std");
const network = @import("network");
const TrackerManager = @import("trackerManager.zig");
const Torrent = @import("torrent.zig");

manager: *TrackerManager,
endpoint: network.EndPoint,
connection_id: u64,
tracker_id: usize,
incoming_port: u16,

fn getPort(uri: std.Uri) u16 {
    if(uri.port != null) return uri.port.?;
    if(std.mem.eql(u8, uri.scheme, "http")) return 80;
    if(std.mem.eql(u8, uri.scheme, "https")) return 443;
    return 25565;
}

pub fn init(self: *@This(), allocator: std.mem.Allocator, uri: std.Uri) !void {
    if (uri.host == null) return error.UnknownHostName;

    const list = try std.net.getAddressList(allocator, uri.host.?, getPort(uri));
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;
    const addr = list.addrs[0];
	self.endpoint = try network.EndPoint.fromSocketAddress(&addr.any, @sizeOf(@TypeOf(addr.any)));
	std.debug.print("Endpoint: {}\n", .{self.endpoint});
	self.connection_id = 0x41727101980;
}

pub fn sendConnect(self: *@This()) !void {
	var sendPacket: [0]u8 = undefined;
	var packet = try self.manager.sendRecv(self.tracker_id, 0, &sendPacket);
	defer packet.deinit();
	self.connection_id = std.mem.readIntBig(u64, packet.data[0..][0..@sizeOf(u64)]);
}

pub fn writeInt(comptime T: type, buf: []u8, pos: usize, val: T) void {
	std.mem.writeIntBig(T, buf[pos..][0..@sizeOf(T)], val);
}

pub fn getPeers(self: *@This(), torrent: *Torrent) !void {
	var sendPacket: [82]u8 = undefined;
	var infoHash: [20]u8 = torrent.infoHash;//.{0xC9, 0xE1, 0x57, 0x63, 0xF7, 0x22, 0xF2, 0x3E, 0x98, 0xA2, 0x9D, 0xEC, 0xDF, 0xAE, 0x34, 0x1B, 0x98, 0xD5, 0x30, 0x56};
	std.mem.copy(u8, sendPacket[0..], &infoHash);
	std.mem.copy(u8, sendPacket[20..], "Hello World!        "); //client ID
	writeInt(u64, &sendPacket, 40, 0); //downloaded
	writeInt(u64, &sendPacket, 48, torrent.info.length); //left
	writeInt(u64, &sendPacket, 56, 0); //uploaded
	writeInt(u32, &sendPacket, 64, 2); //event
	writeInt(u32, &sendPacket, 68, 0); //ip address
	writeInt(u32, &sendPacket, 72, 0); //key?
	writeInt(u32, &sendPacket, 76, 0xffffffff); //num_want
	writeInt(u16, &sendPacket, 80, 0); //port

	var packet = try self.manager.sendRecv(self.tracker_id, 1, &sendPacket);
	defer packet.deinit();
	//std.debug.print("packet: {}\n", .{packet});
	var interval = packet.read(u32, 0);
	var leechers = packet.read(u32, 4);
	var seeders = packet.read(u32, 8);
	std.debug.print("interval: {}\nleechers: {}\nseeders: {}\n", .{interval, seeders, leechers});
	var ipCount = (packet.data.len - 12) / 6;
	std.debug.print("peers({}): \n", .{ipCount});
	for(0..ipCount) |i| {
		var ip0 = packet.read(u8, 12+i*6+0);
		var ip1 = packet.read(u8, 12+i*6+1);
		var ip2 = packet.read(u8, 12+i*6+2);
		var ip3 = packet.read(u8, 12+i*6+3);
		var port = packet.read(u16, 12+i*6+4);
		std.debug.print("    [{}] {}.{}.{}.{}:{}\n", .{i, ip0, ip1, ip2, ip3, port});
	}
}