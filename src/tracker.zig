const std = @import("std");
const network = @import("network.zig");
const TrackerManager = @import("trackerManager.zig");
const Torrent = @import("torrent.zig");
const bencode = @import("bencode.zig");

const ConnectionType = enum {
    UNKNOWN,
    UDP,
    HTTP,
    HTTPS,
};

manager: *TrackerManager,
connected: bool,
uri: std.Uri,
endpoint: network.EndPoint,
connection_id: u64,
tracker_id: usize,
incoming_port: u16,
connection_type: ConnectionType,
peer_id: [20]u8,
allocator: std.mem.Allocator,
peers: std.ArrayList(network.EndPoint),

fn getConnectionType(uri: std.Uri) ConnectionType {
    if (uri.port != null) return .UDP;
    if (std.mem.eql(u8, uri.scheme, "http")) return .HTTP;
    if (std.mem.eql(u8, uri.scheme, "https")) return .HTTPS;
    return .UNKNOWN;
}

fn getPort(uri: std.Uri) u16 {
    if (uri.port) |port| return port;
    return switch (getConnectionType(uri)) {
        .UDP => uri.port.?,
        .HTTP => 80,
        .HTTPS => 443,
        else => 25565,
    };
}

pub fn init(self: *@This(), allocator: std.mem.Allocator, uri: std.Uri) !void {
    if (uri.host == null) return error.UnknownHostName;

    self.uri = uri;
    self.connection_type = getConnectionType(uri);
    self.allocator = allocator;
    const list = try std.net.getAddressList(allocator, uri.host.?, getPort(uri));
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;
    const addr = list.addrs[0];
    self.endpoint = try network.EndPoint.fromSocketAddress(&addr.any, @sizeOf(@TypeOf(addr.any)));
    std.debug.print("Endpoint: {}\n", .{self.endpoint});
    self.connection_id = 0x41727101980;

    std.mem.copyForwards(u8, &self.peer_id, "Hello World!        ");
    self.peers = std.ArrayList(network.EndPoint).init(allocator);
}

pub fn deinit(self: *@This()) void {
    self.peers.deinit();
}

pub fn connect(self: *@This()) !void {
    if (self.connected) return error.NotConnected;
    if (self.connection_type == .UDP) {
        if (self.connection_type != .UDP) return error.UnsupportedConnectionProtocol;
        var sendPacket: [0]u8 = undefined;
        var packet = try self.manager.sendRecv(self.tracker_id, 0, &sendPacket);
        defer packet.deinit();
        self.connection_id = std.mem.readIntBig(u64, packet.data[0..][0..@sizeOf(u64)]);
    }
    self.connected = true;
}

fn retFalse(_: u8) bool {
    return false;
}

pub fn writeInt(comptime T: type, buf: []u8, pos: usize, val: T) void {
    std.mem.writeIntBig(T, buf[pos..][0..@sizeOf(T)], val);
}

pub fn getPeers(self: *@This(), torrent: *Torrent) !void {
    try switch (self.connection_type) {
        .UDP => {
            var sendPacket: [82]u8 = undefined;
            var infoHash: [20]u8 = torrent.infoHash; //.{0xC9, 0xE1, 0x57, 0x63, 0xF7, 0x22, 0xF2, 0x3E, 0x98, 0xA2, 0x9D, 0xEC, 0xDF, 0xAE, 0x34, 0x1B, 0x98, 0xD5, 0x30, 0x56};
            std.mem.copy(u8, sendPacket[0..], &infoHash);
            std.mem.copy(u8, sendPacket[20..], &self.peer_id); //client ID
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
            _ = interval;
            var leechers = packet.read(u32, 4);
            _ = leechers;
            var seeders = packet.read(u32, 8);
            _ = seeders;
            //std.debug.print("interval: {}\nleechers: {}\nseeders: {}\n", .{ interval, seeders, leechers });
            var ipCount = (packet.data.len - 12) / 6;
            //std.debug.print("peers({}): \n", .{ipCount});
            for (0..ipCount) |i| {
                var ip0 = packet.read(u8, 12 + i * 6 + 0);
                var ip1 = packet.read(u8, 12 + i * 6 + 1);
                var ip2 = packet.read(u8, 12 + i * 6 + 2);
                var ip3 = packet.read(u8, 12 + i * 6 + 3);
                var port = packet.read(u16, 12 + i * 6 + 4);
                //std.debug.print("    [{}] {}.{}.{}.{}:{}\n", .{ i, ip0, ip1, ip2, ip3, port });
                try self.peers.append(network.EndPoint{
                    .address = .{ .ipv4 = .{ .value = .{ ip0, ip1, ip2, ip3 } } },
                    .port = port,
                });
            }
        },
        .HTTP, .HTTPS => {
            var client = std.http.Client{ .allocator = self.allocator };
            defer client.deinit(); // handled below

            var info_hash = try std.Uri.escapeStringWithFn(self.allocator, &torrent.infoHash, retFalse);
            defer self.allocator.free(info_hash);

            var peer_id = try std.Uri.escapeStringWithFn(self.allocator, &self.peer_id, retFalse);
            defer self.allocator.free(peer_id);

            var listen_port = "6881";
            var uploaded = "0";
            var downloaded = "0";
            var left = "0";
            var compact = "1";
            var event = "started";

            var h = std.http.Headers{ .allocator = self.allocator };
            defer h.deinit();

            const protocol = if (self.connection_type == .HTTP) "http" else "https";
            const location = try std.fmt.allocPrint(self.allocator, "{s}://{s}:{}{s}?info_hash={s}&peer_id={s}&port={s}&uploaded={s}&downloaded={s}&left={s}&compact={s}&event={s}", .{
                protocol,
                self.uri.host.?,
                self.endpoint.port,
                self.uri.path,
                info_hash,
                peer_id,
                listen_port,
                uploaded,
                downloaded,
                left,
                compact,
                event,
            });
            defer self.allocator.free(location);
            const uri = try std.Uri.parse(location);

            std.debug.print("URL: {s}\n", .{location});
            var req = try client.request(.GET, uri, h, .{});
            defer req.deinit();

            try req.start();
            try req.wait();

            const body = try req.reader().readAllAlloc(self.allocator, 8192);
            defer self.allocator.free(body);

            var offset: usize = 0;
            var dict = try bencode.GetDict(body, &offset);
            while (dict.next()) |entry| {
                std.debug.print("{s}: {s}\n", .{ entry.key, entry.value });
            }

            std.debug.print("Body: {s}\n", .{body});
        },
        else => error.OperationNotSupported,
    };
}
