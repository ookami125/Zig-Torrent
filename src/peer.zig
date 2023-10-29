const std = @import("std");
const Torrent = @import("torrent.zig");
const network = @import("network.zig");

const Self = @This();

const PeerState = packed struct {
    Unchoked: bool,
    Interested: bool,
};

const TBitfield = std.packed_int_array.PackedIntSliceEndian(u1, std.builtin.Endian.Big);

allocator: std.mem.Allocator,
torrent: *Torrent,
sock: network.Socket,
handshake: bool,
bitfielded: bool,
id: ?[]u8,
pieceByteCount: []u32,
//bitfield: TBitfield,
remoteBitfield: TBitfield,
remoteState: PeerState, //instructions sent to remote
localState: PeerState, //instructions sent to self
scratchOffset: usize,
scratch: []u8,
//ringBuffer: RingBuffer,

//temp
//recvFile: std.fs.File,
waitingForBlock: bool = false,
requestingPiece: ?u32 = null,

pub fn init(allocator: std.mem.Allocator, endpoint: network.EndPoint, bind_port: u16, torrent: *Torrent) !Self {
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

    self.pieceByteCount = try allocator.alloc(u32, torrent.file.info.pieces.len);
    for (0..self.pieceByteCount.len) |i| {
        self.pieceByteCount[i] = 0;
    }

    var byteCount = TBitfield.bytesRequired(self.torrent.file.info.pieces.len);
    var remoteBitfieldBytes = try allocator.alloc(u8, byteCount);
    @memset(remoteBitfieldBytes, 0);
    self.remoteBitfield = TBitfield.init(remoteBitfieldBytes, torrent.file.info.pieces.len);

    self.localState = .{ .Unchoked = false, .Interested = false };
    self.remoteState = .{ .Unchoked = false, .Interested = false };
    // self.recvFile = try std.fs.cwd().createFile(
    // 	"recv.bin",
    // 	.{ .read = false },
    // );

    //Attempt handshake and connection
    const protocol: []const u8 = "BitTorrent protocol";
    var sendBuf = std.mem.zeroes([49 + protocol.len]u8);
    sendBuf[0] = protocol.len;
    std.mem.copyForwards(u8, sendBuf[1..], protocol);
    std.mem.copyForwards(u8, sendBuf[(1 + 8 + protocol.len)..], &torrent.file.infoHash);
    std.mem.copyForwards(u8, sendBuf[(1 + 8 + protocol.len + 20)..], &torrent.file.infoHash);
    _ = try self.sock.send(&sendBuf);

    //var scratch = std.mem.zeroes([49+255]u8);
    //var recvInfo = try self.sock.receive(&scratch);
    //std.debug.print("{any}\n", .{scratch[0..recvInfo]});

    self.scratch = try allocator.alloc(u8, 1000000);

    self.scratchOffset = 0;
    @memset(self.scratch[0..], 0);

    //self.ringBuffer.init();

    self.requestingPiece = null;

    self.id = null;

    return self;
}

pub fn deinit(self: *@This()) void {
    if (self.id) |id| self.allocator.free(id);
    self.allocator.free(self.pieceByteCount);
    self.allocator.free(self.remoteBitfield.bytes);
    self.allocator.free(self.scratch);
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
        if (!std.mem.eql(u8, infoHash, &self.torrent.file.infoHash)) return error.OperationNotSupported;

        var peerId = data[(1 + protocolNameLen + 8 + 20)..][0..20];
        self.id = try std.Uri.escapeString(self.allocator, peerId);

        self.handshake = true;
        return 49 + protocolNameLen;
    }
    var size: u32 = std.mem.readIntBig(u32, data[0..4]);
    if (size == 0) {
        std.debug.print("[{?s}] keep alive!\n", .{self.id});
        _ = try self.sock.send("\x00\x00\x00\x00");
        return 4;
    }

	//std.debug.print("[{?s}] packet: {any}\n", .{self.id, data[0..size+4]});

    size -= 1;
    var op = data[4];
    var args = data[5..];
    switch (op) {
        0 => { //choke
            std.debug.print("[{?s}] choke\n", .{self.id});
            self.localState.Unchoked = false;
        },
        1 => { //unchoke
            std.debug.print("[{?s}] unchoke\n", .{self.id});
            self.localState.Unchoked = true;
        },
        2 => { //interested
            std.debug.print("[{?s}] interested\n", .{self.id});
            self.localState.Interested = true;
        },
        3 => { //not interested
            std.debug.print("[{?s}] not interested\n", .{self.id});
            self.localState.Interested = false;
        },
        4 => { //have
            std.debug.print("[{?s}] have\n", .{self.id});
            var pieceIdx = std.mem.readIntBig(u32, args[0..4]);
            self.remoteBitfield.set(pieceIdx, 1);
        },
        5 => { //bitfield
            if (self.bitfielded) return error.BitfieldAlreadyRecvd;
            self.bitfielded = true;
            std.debug.print("[{?s}] bitfield ({d})({any})\n", .{ self.id, args[0..size].len, args[0..size] });
            std.mem.copyForwards(u8, self.remoteBitfield.bytes, args[0..size]);
        },
        6 => { //request
            std.debug.print("[{?s}] request\n", .{self.id});
        },
        7 => { //piece
            var pieceIdx = std.mem.readIntBig(u32, args[0..4]);
            var beginOffset = std.mem.readIntBig(u32, args[4..8]);
            std.debug.print("[{?s}] piece ({}, {}, {})\n", .{ self.id, pieceIdx, beginOffset, size-8 });
            self.pieceByteCount[pieceIdx] = beginOffset + size - 8;
            if (self.pieceByteCount[pieceIdx] >= self.torrent.file.info.pieceLength) {
                self.torrent.bitfield.set(pieceIdx, 1);
                try self.Have(pieceIdx);
                self.requestingPiece = null;
            }
            self.waitingForBlock = false;
            var fileOffset = beginOffset + pieceIdx * self.torrent.file.info.pieceLength;
            var writeData = args[8..size];
            try self.torrent.outfile.pwriteAll(writeData, fileOffset);
            //try self.torrent.writelist.write(self.allocator, fileOffset, fileOffset + writeData.len);
        },
        8 => { //cancel
            std.debug.print("[{?s}] cancel\n", .{self.id});
        },
        else => return error.InvalidPacketID,
    }
    return size + 5;
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
    var pieceLen = self.torrent.file.info.pieceLength;
    var length: u32 = 1 << 14;
    if (offset + length > pieceLen) {
		std.debug.print("{} {} {}\n", .{offset, length, pieceLen});
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
    self.torrent.requestBitfield.set(piece, 1);
    self.requestingPiece = piece;
}

pub fn GetNextBlock(self: *@This()) !void {
    var piece: u32 = blk: {
        if (self.requestingPiece) |i| break :blk i;
        for (self.pieceByteCount, 0..) |bytes, i| {
            if (self.torrent.bitfield.get(i) == 1) continue;
            if (self.remoteBitfield.get(i) == 0) continue;
            if (self.torrent.requestBitfield.get(i) == 1) continue;
            var pieceLen = self.torrent.file.info.pieceLength;
            if (i == self.torrent.file.info.pieces.len - 1) {
                pieceLen = @intCast(self.torrent.file.info.length - self.torrent.file.info.pieceLength * (self.torrent.file.info.pieces.len - 1));
            }
            if (bytes < pieceLen) {
                break :blk @intCast(@as(u64, i));
            }
        } else {
            return error.NoPieceLeft;
        }
        break :blk 0;
    };
    try self.GetBlock(piece, self.pieceByteCount[piece]);
}

pub fn GetBlockCount(self: *@This()) usize {
    var count: usize = 0;
    for (self.pieceByteCount, 0..) |_, i| {
        count += self.remoteBitfield.get(i);
    }
    return count;
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
	var temp: usize = bytes.len;
	_ = temp;
	//std.debug.print("{d}\n", .{bytes[0..temp]});
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
