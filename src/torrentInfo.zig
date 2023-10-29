const std = @import("std");
pub const bencode = @import("bencode.zig");
const Torrent = @This();

const Info = struct {
    buffer: []const u8,
    length: u64,
    name: []const u8,
    pieceLength: u32,
    pieces: []const [20]u8,
    files: [][]const u8,
};

buffer: []const u8,
announce: []const u8,
announce_list: ?[][]const u8,
createdBy: []const u8,
creationDate: []const u8,
encoding: []const u8,
infoHash: [20]u8,
info: Info,
allocator: std.mem.Allocator,

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !Torrent {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const file_size = (try file.stat()).size;

    var torrent: Torrent = undefined;
    torrent.buffer = try file.readToEndAlloc(allocator, file_size);
    torrent.allocator = allocator;
    var readOffset: usize = 0;
    var dictIter = try bencode.GetDict(torrent.buffer, &readOffset);

    torrent.announce_list = null;

    while (dictIter.next()) |temp| {
        if (std.mem.eql(u8, temp.key, "announce")) {
            torrent.announce = try bencode.GetString(temp.value, null);
        } else if (std.mem.eql(u8, temp.key, "announce-list")) {
            var list = std.ArrayList([]const u8).init(allocator);
            defer list.deinit();
            var blist = try bencode.GetList(temp.value, null);
            var offset: usize = 0;
            while (offset < blist.len) {
                var announceList2 = try bencode.GetList(blist[offset..], &offset);
                var announce: []const u8 = try bencode.GetString(announceList2, null);

                try list.append(announce);
            }
            torrent.announce_list = try list.toOwnedSlice();
        } else if (std.mem.eql(u8, temp.key, "created by")) {
            torrent.createdBy = try bencode.GetString(temp.value, null);
        } else if (std.mem.eql(u8, temp.key, "creation date")) {
            torrent.creationDate = temp.value;
        } else if (std.mem.eql(u8, temp.key, "encoding")) {
            torrent.encoding = try bencode.GetString(temp.value, null);
        } else if (std.mem.eql(u8, temp.key, "info")) {
            var info: Info = std.mem.zeroes(Info);
            info.buffer = temp.value;
            var infoDictIter = try bencode.GetDict(temp.value, null);
            while (infoDictIter.next()) |infoPair| {
                if (std.mem.eql(u8, infoPair.key, "length")) {
                    info.length = try bencode.GetInt(u64, infoPair.value, null);
                } else if (std.mem.eql(u8, infoPair.key, "name")) {
                    info.name = try bencode.GetString(infoPair.value, null);
                } else if (std.mem.eql(u8, infoPair.key, "piece length")) {
                    info.pieceLength = try bencode.GetInt(u32, infoPair.value, null);
                } else if (std.mem.eql(u8, infoPair.key, "pieces")) {
                    var allHashes = try bencode.GetString(infoPair.value, null);
                    var bytes = std.mem.sliceAsBytes(allHashes);
                    info.pieces = std.mem.bytesAsSlice([20]u8, bytes);
                } else if (std.mem.eql(u8, infoPair.key, "files")) {
                    var list = std.ArrayList([]const u8).init(allocator);
                    defer list.deinit();
                    var blist = try bencode.GetList(infoPair.value, null);
                    var offset: usize = 0;
                    while (offset < blist.len) {
                        var files = try bencode.GetDict(blist[offset..], &offset);
                        while (files.next()) |filePair| {
                            if (std.mem.eql(u8, filePair.key, "length")) {
                                info.length += try bencode.GetInt(u64, filePair.value, null);
                            }
                            try list.append(filePair.key);
                        }
                    }
                    torrent.info.files = try list.toOwnedSlice();
                }
            }
            torrent.infoHash = undefined;
            std.crypto.hash.Sha1.hash(temp.value, &torrent.infoHash, .{});
            torrent.info = info;
        }
    }
    return torrent;
}

pub fn deinit(self: @This()) void {
    if (self.announce_list) |announce_list| self.allocator.free(announce_list);
    self.allocator.free(self.info.files);
    self.allocator.free(self.buffer);
}

test {
    std.testing.refAllDecls(@This());
}
