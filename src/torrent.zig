const std = @import("std");
const Peer = @import("Peer.zig");
const TorrentInfo = @import("torrentInfo.zig");
pub const TBitfield = std.packed_int_array.PackedIntSliceEndian(u1, std.builtin.Endian.big);
const RndGen = std.rand.DefaultPrng;
const Torrent = @This();
const RangeArray = @import("RangeArray.zig").RangeArray;
pub const Hash = TorrentInfo.Hash;

allocator: std.mem.Allocator,
file: TorrentInfo,
bitfield: TBitfield,
notDownloaded: RangeArray(usize),
downloaded: RangeArray(usize),

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !Torrent {
    var self: Torrent = undefined;

    self.allocator = allocator;
    self.file = try TorrentInfo.loadFile(allocator, path);

    const byteCount = TBitfield.bytesRequired(self.file.info.pieces.len);

    const bitfieldBytes = try allocator.alloc(u8, byteCount);
    @memset(bitfieldBytes, 0);
    self.bitfield = TBitfield.init(bitfieldBytes, self.file.info.pieces.len);

	self.notDownloaded = try RangeArray(usize).init(allocator, self.file.info.pieces.len);
	try self.notDownloaded.add(0, self.getSize());
	for(0..self.file.info.pieces.len) |i| {
		try self.notDownloaded.split(i*self.file.info.pieceLength);
	}

	self.downloaded = try RangeArray(usize).init(allocator, self.file.info.pieces.len);

    return self;
}

pub fn loadRaw(allocator: std.mem.Allocator, filename: []const u8, contents: []const u8) !Torrent {
    var self: Torrent = undefined;

    self.allocator = allocator;
    self.file = try TorrentInfo.loadRaw(allocator, filename, contents);

    const byteCount = TBitfield.bytesRequired(self.file.info.pieces.len);

    const bitfieldBytes = try allocator.alloc(u8, byteCount);
    @memset(bitfieldBytes, 0);
    self.bitfield = TBitfield.init(bitfieldBytes, self.file.info.pieces.len);

	self.notDownloaded = try RangeArray(usize).init(allocator, self.file.info.pieces.len);
	try self.notDownloaded.add(0, self.getSize());
	for(0..self.file.info.pieces.len) |i| {
		try self.notDownloaded.split(i*self.file.info.pieceLength);
	}

	self.downloaded = try RangeArray(usize).init(allocator, self.file.info.pieces.len);

	return self;
}

pub fn deinit(self: *@This()) void {
    self.allocator.free(self.bitfield.bytes);
    //self.allocator.free(self.requestBitfield.bytes);
	self.downloaded.deinit();
	self.notDownloaded.deinit();
    self.file.deinit();
}

pub fn getSize(self: @This()) u64 {
	return self.file.info.length;
}

pub fn getDownloaded(self: @This()) u64 {
	var sum: u64 = 0;
	for(self.downloaded.ranges) |range| {
		sum += range.length();
	}
	return sum;
}

pub fn writePieceFile(i: u64, data: []const u8) !void {
	var file_path_raw: [32]u8 = undefined;
	const file_path = try std.fmt.bufPrint(&file_path_raw, "{}.piece", .{i});
	const dir = try std.fs.cwd().openDir("downloads/pieces-zig/", .{});
	const file = try dir.createFile(file_path, .{});
	try file.writeAll(data);
}

pub fn pieceCheck(i: u64, data: []const u8, pieceHash: Torrent.Hash) bool {
	_ = i;
	var buff: Torrent.Hash = undefined;
	std.crypto.hash.Sha1.hash(data, &buff, .{});

	const result = std.mem.eql(u8, &pieceHash, &buff);

	return result;
}