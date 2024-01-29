const std = @import("std");
const TorrentInfo = @import("torrentInfo.zig");
const TBitfield = std.packed_int_array.PackedIntSliceEndian(u1, std.builtin.Endian.Big);
const RndGen = std.rand.DefaultPrng;
const Torrent = @This();
const RangeArray = @import("RangeArray.zig").RangeArray;

allocator: std.mem.Allocator,
file: TorrentInfo,
bitfield: TBitfield,
requestBitfield: TBitfield,
outfile: std.fs.File,
notDownloaded: RangeArray(usize),
downloaded: RangeArray(usize),

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

	var name = std.fs.path.basename(path);
	var dirname = try std.fmt.allocPrint(allocator, "downloads/{s}", .{name});
	var outdir = std.fs.cwd().makeOpenPath(dirname, .{}) catch |err| blk: {
		if(err != std.os.MakeDirError.PathAlreadyExists) return err;
		break :blk try std.fs.cwd().openDir(dirname, .{});
	};
    allocator.free(dirname);
	
	self.outfile = try outdir.createFile("file.bin", .{ .read = false });
	
	var extractFile = try outdir.createFile("extractor.sh", .{ .read = false });
	
	_ = try extractFile.write("#!/bin/bash\n");
	_ = try extractFile.write("mkdir \"output\"\n");
	var offset: u64 = 0;
	for(self.file.info.files) |file| {
		std.debug.print("filename: {s}\n", .{file.path});
		try std.fmt.format(extractFile.writer(), "dd if=file.bin of=\"output/{s}\" skip={}B count={}B\n", .{file.path, offset, file.length});
		offset += file.length;
	}

    //self.writelist = .{
    //    .next = null,
    //    .prev = null,
    //    .start = 0,
    //    .end = self.file.info.length,
    //};

	self.notDownloaded = try RangeArray(usize).init(allocator, self.file.info.pieces.len);
	//defer notDownloaded.deinit();
	try self.notDownloaded.add(0, self.getSize());
	for(0..self.file.info.pieces.len) |i| {
		try self.notDownloaded.split(i*self.file.info.pieceLength);
	}

	self.downloaded = try RangeArray(usize).init(allocator, self.file.info.pieces.len);

    return self;
}

pub fn deinit(self: @This()) void {
    self.outfile.close();
    self.allocator.free(self.bitfield.bytes);
    self.allocator.free(self.requestBitfield.bytes);
    self.file.deinit();
}

pub fn getSize(self: @This()) u64 {
	return self.file.info.length;
}