const std = @import("std");
const TorrentInfo = @import("torrentInfo.zig");
const Writelist = @import("writelist.zig");
const TBitfield = std.packed_int_array.PackedIntSliceEndian(u1, std.builtin.Endian.Big);
const RndGen = std.rand.DefaultPrng;
const Torrent = @This();

allocator: std.mem.Allocator,
file: TorrentInfo,
bitfield: TBitfield,
requestBitfield: TBitfield,
outfile: std.fs.File,
writelist: Writelist,

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !Torrent {
    var self: Torrent = undefined;

    self.allocator = allocator;
    self.file = try TorrentInfo.loadFile(allocator, path);

    var byteCount = TBitfield.bytesRequired(self.file.info.pieces.len);

    var bitfieldBytes = try allocator.alloc(u8, byteCount);
    @memset(bitfieldBytes, 0);
    self.bitfield = TBitfield.init(bitfieldBytes, self.file.info.pieces.len);

    var requestBitfieldBytes = try allocator.alloc(u8, byteCount);
    @memset(requestBitfieldBytes, 0);
    self.requestBitfield = TBitfield.init(requestBitfieldBytes, self.file.info.pieces.len);

    var rnd = RndGen.init(@bitCast(std.time.milliTimestamp()));
    var fileid: u16 = rnd.random().int(u16);
    var filename = try std.fmt.allocPrint(allocator, "torrent-{}.bin", .{fileid});
    self.outfile = try std.fs.cwd().createFile(
        filename,
        .{ .read = false },
    );
    allocator.free(filename);

    self.writelist = .{
        .next = null,
        .prev = null,
        .start = 0,
        .end = self.file.info.length,
    };

    return self;
}

pub fn deinit(self: @This()) void {
    //self.writelist.deinit(self.allocator);
    self.outfile.close();
    self.allocator.free(self.bitfield.bytes);
    self.allocator.free(self.requestBitfield.bytes);
    self.file.deinit();
}
