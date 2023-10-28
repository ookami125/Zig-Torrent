const std = @import("std");
const Torrent = @import("torrent.zig");
const network = @import("network.zig");
const RndGen = std.rand.DefaultPrng;

const Self = @This();

const PeerState = packed struct {
    Unchoked: bool,
    Interested: bool,
};

const TBitfield = std.packed_int_array.PackedIntSliceEndian(u1, std.builtin.Endian.Big);

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
scratchOffset: usize,
scratch: []u8,
//ringBuffer: RingBuffer,

//temp
file: std.fs.File,
//recvFile: std.fs.File,
count: u32 = 0,
waitingForBlock: bool = false,

pub fn init(allocator: std.mem.Allocator, endpoint: network.EndPoint, bind_port: u16, torrent: *const Torrent) !Self {
    var self: Self = undefined;

    self.allocator = allocator;

    self.torrent = torrent;

    self.sock = try network.Socket.create(.ipv4, .tcp);
    try self.sock.enablePortReuse(true);
    try self.sock.bindToPort(bind_port);
    try self.sock.setReadTimeout(1);
    try self.sock.setWriteTimeout(1_000_000);
    try self.sock.connect(endpoint);

    self.handshake = false;
    self.bitfielded = false;

    self.pieceByteCount = try allocator.alloc(u32, torrent.info.pieces.len);
    for (0..self.pieceByteCount.len) |i| {
        self.pieceByteCount[i] = 0;
    }
    var bitfieldBytes = try allocator.alloc(u8, try std.math.divCeil(usize, torrent.info.pieces.len, 8));
    @memset(bitfieldBytes, 0);
    self.bitfield = TBitfield.init(bitfieldBytes, torrent.info.pieces.len);
    for (0..torrent.info.pieces.len) |i| {
        self.bitfield.set(i, 0);
    }

    var remoteBitfieldBytes = try allocator.alloc(u8, try std.math.divCeil(usize, torrent.info.pieces.len, 8));
    @memset(remoteBitfieldBytes, 0);
    self.remoteBitfield = TBitfield.init(remoteBitfieldBytes, torrent.info.pieces.len);

    self.localState = .{ .Unchoked = false, .Interested = false };
    self.remoteState = .{ .Unchoked = false, .Interested = false };

    var rnd = RndGen.init(0);
    var fileid: u16 = rnd.random().int(u16);

    var filename = try std.fmt.allocPrint(allocator, "torrent-{}.bin", .{fileid});

    self.file = try std.fs.cwd().createFile(
        filename,
        .{ .read = false },
    );

    allocator.free(filename);

    // self.recvFile = try std.fs.cwd().createFile(
    // 	"recv.bin",
    // 	.{ .read = false },
    // );

    //Attempt handshake and connection
    const protocol: []const u8 = "BitTorrent protocol";
    var sendBuf = std.mem.zeroes([49 + protocol.len]u8);
    sendBuf[0] = protocol.len;
    std.mem.copyForwards(u8, sendBuf[1..], protocol);
    std.mem.copyForwards(u8, sendBuf[(1 + 8 + protocol.len)..], &torrent.infoHash);
    std.mem.copyForwards(u8, sendBuf[(1 + 8 + protocol.len + 20)..], &torrent.infoHash);
    _ = try self.sock.send(&sendBuf);

    //var scratch = std.mem.zeroes([49+255]u8);
    //var recvInfo = try self.sock.receive(&scratch);
    //std.debug.print("{any}\n", .{scratch[0..recvInfo]});

    self.scratch = try allocator.alloc(u8, 1000000);

    self.scratchOffset = 0;
    @memset(self.scratch[0..], 0);

    //self.ringBuffer.init();

    self.count = 0;

    return self;
}

pub fn deinit(self: *@This()) void {
    //self.pieceBitset.deinit();
	self.allocator.free(self.bitfield.bytes);
	self.bitfield = undefined;
	self.allocator.free(self.remoteBitfield.bytes);
	self.remoteBitfield = undefined;
    self.sock.close();
}

pub fn parsePacket(self: *@This(), data: []const u8) !usize {
    if (self.handshake == false) {
        if (data.len < 1) return 0;
        var protocolNameLen = data[0];
        if (data.len < 49 + protocolNameLen) return 0;
        var protocolName = data[1..][0..protocolNameLen];
        if (!std.mem.eql(u8, protocolName, "BitTorrent protocol")) return error.OperationNotSupported;
        var infoHash = data[(1 + protocolNameLen + 8)..][0..20];
        if (!std.mem.eql(u8, infoHash, &self.torrent.infoHash)) return error.OperationNotSupported;
        var peerId = data[(1 + protocolNameLen + 8 + 20)..][0..20];
        std.debug.print("Protocol Name: {s}\n", .{protocolName});
        std.debug.print("Info Hash: {any}\n", .{infoHash});
        std.debug.print("Peer ID: {any}\n", .{peerId});
        self.handshake = true;
        return 49 + protocolNameLen;
    }
    var size: u32 = std.mem.readIntBig(u32, data[0..4]);
    if (size == 0) {
        std.debug.print("keep alive!\n", .{});
        _ = try self.sock.send("\x00\x00\x00\x00");
        return 4;
    }
    switch (data[4]) {
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
            self.remoteBitfield.bytes[pieceIdx] = 1;
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
            std.debug.print("piece ({}, {}, {})\n", .{ pieceIdx, beginOffset, size });
            self.pieceByteCount[pieceIdx] = beginOffset + size - 9;
            if (self.pieceByteCount[pieceIdx] == self.torrent.info.pieceLength) {
                self.bitfield.set(pieceIdx, 1);
                try self.Have(pieceIdx);
            }
            self.waitingForBlock = false;
            try self.file.pwriteAll(data[13..], beginOffset + pieceIdx * self.torrent.info.pieceLength);
            try self.file.sync();
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

pub fn GetBlock(self: *@This(), piece: u32, offset: u32) !void {
    std.debug.print("Send Get Block ({d}, {d}) ", .{ piece, offset });
    var pieceLen = self.torrent.info.pieceLength;
    var length: u32 = 1 << 14;
    if (offset + length > pieceLen) {
        length = pieceLen - offset;
    }
    std.debug.print("[Length: {d}]\n", .{length});
    var data: [17]u8 = undefined;
    std.mem.copyForwards(u8, data[0..], "\x00\x00\x00\x0d\x06");
    std.mem.writeIntBig(u32, data[5..][0..4], piece);
    std.mem.writeIntBig(u32, data[9..][0..4], offset);
    std.mem.writeIntBig(u32, data[13..][0..4], length);
    _ = try self.sock.send(&data);
    self.waitingForBlock = true;
}

pub fn GetNextBlock(self: *@This()) !void {
    var pieces = try AndNot(self.allocator, self.remoteBitfield, self.bitfield);
    var piece: u32 = 0;
    var offset: u32 = 0;
    for (self.pieceByteCount, 0..) |bytes, i| {
        if (pieces.get(i) == 0) continue;
        var pieceLen = self.torrent.info.pieceLength;
        if (i == self.torrent.info.pieces.len - 1) {
            pieceLen = @intCast(self.torrent.info.length - self.torrent.info.pieceLength * (self.torrent.info.pieces.len - 1));
        }
        if (bytes < pieceLen) {
            piece = @intCast(@as(u64, i));
            offset = bytes;
            break;
        }
    } else {
        return error.NoPieceLeft;
    }
    try self.GetBlock(piece, offset);
}

pub fn GetBlockCount(self: *@This()) usize {
    var count: usize = 0;
    for (self.pieceByteCount, 0..) |_, i| {
        count += self.remoteBitfield.get(i);
    }
    return count;
}

pub fn AndNot(alloctor: std.mem.Allocator, left: TBitfield, right: TBitfield) !TBitfield {
    var resultBytes = try alloctor.alloc(u8, left.bytes.len);
    var result = TBitfield.init(resultBytes, left.len);
    for (0..result.len) |i| {
        result.set(i, @intFromBool((left.get(i) == 1) and !(right.get(i) == 1)));
    }
    return result;
}

pub fn recieve(self: *@This()) !void {
    //Limit packets to 1000
    for (0..1000) |_| {
        self.scratchOffset += self.sock.receive(self.scratch[self.scratchOffset..]) catch |err| {
            if (err == network.Socket.ReceiveError.WouldBlock) {
                return;
            }
            return err;
        };
    }
}

fn validPacket(self: *@This(), bytes: []const u8) bool {
    if (self.handshake == false) {
        if (bytes.len < 1) return false;
        var protocolNameLen = bytes[0];
        if (bytes.len < protocolNameLen + 49) return false;
        return true;
    }
    if (bytes.len < 4) return false;
    var sizeU32 = self.scratch[0..4];
    var size: u32 = std.mem.readIntBig(u32, sizeU32);
    if (bytes.len < 4 + size) return false;
    return true;
}

pub fn process(self: *@This()) !void {
    try self.recieve();

    while (true) {
        if (self.scratchOffset < 4) return;

        var packet: []const u8 = self.scratch;
        if (!self.validPacket(packet[0..self.scratchOffset])) {
            return;
        }
        var packetSize: usize = try self.parsePacket(packet);
        self.scratchOffset -= packetSize;
        std.mem.copyForwards(u8, self.scratch, self.scratch[packetSize..]);
    }
}
