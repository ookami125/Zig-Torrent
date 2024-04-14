const std = @import("std");
pub const bencode = @import("bencode.zig");
const Torrent = @This();
pub const Hash = [20]u8;

const FileInfo = struct {
	length: u64,
	name: []const u8,
	path: []const u8,
	file: ?std.fs.File,
};

const Info = struct {
    buffer: []const u8,
    length: u64,
    name: []const u8,
    pieceLength: u64,
    pieces: []const Hash,
    files: []FileInfo,
};

buffer: []const u8,
announce: []const u8,
announce_list: ?[][]const u8,
createdBy: []const u8,
creationDate: []const u8,
encoding: []const u8,
infoHash: Hash,
info: Info,
allocator: std.mem.Allocator,

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !Torrent {
    const torrent_file = try std.fs.openFileAbsolute(path, .{});
    defer torrent_file.close();
	
	const name = std.fs.path.basename(path);
    const file_size = (try torrent_file.stat()).size;

    const buffer = try torrent_file.readToEndAlloc(allocator, file_size);
    
    return loadRaw(allocator, name, buffer);
}

pub fn loadRaw(allocator: std.mem.Allocator, filename: []const u8, data: []const u8) !Torrent {
    var torrent: Torrent = undefined;
    torrent.allocator = allocator;

	const dirname = try std.fmt.allocPrint(allocator, "downloads/{s}", .{filename});
    defer allocator.free(dirname);

    torrent.buffer = data;
    var readOffset: usize = 0;
    var dictIter = try bencode.GetDict(torrent.buffer, &readOffset);

    torrent.announce_list = null;

    while (dictIter.next()) |temp| {
        if (std.mem.eql(u8, temp.key, "announce")) {
            torrent.announce = try bencode.GetString(temp.value, null);
        } else if (std.mem.eql(u8, temp.key, "announce-list")) {
            var list = std.ArrayList([]const u8).init(torrent.allocator);
            //defer list.deinit();
            var blist = try bencode.GetList(temp.value, null);
            var offset: usize = 0;
            while (offset < blist.len) {
                const announceList2 = try bencode.GetList(blist[offset..], &offset);
                const announce: []const u8 = try bencode.GetString(announceList2, null);

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
                    const allHashes = try bencode.GetString(infoPair.value, null);
                    const bytes = std.mem.sliceAsBytes(allHashes);
                    info.pieces = std.mem.bytesAsSlice(Hash, bytes);
                }
				else if (std.mem.eql(u8, infoPair.key, "files")) {
					var list = std.ArrayList(FileInfo).init(torrent.allocator);
                    defer list.deinit();
					var blist = try bencode.GetList(infoPair.value, null);
                    var offset: usize = 0;
                    while (offset < blist.len) {
					    var files = try bencode.GetDict(blist[offset..], &offset);
						var fileinfo: FileInfo = undefined;
						fileinfo.path = try std.fs.path.join(allocator, &[2][]const u8{
							dirname,
							info.name,
						});
						fileinfo.name = info.name;
                        while (files.next()) |filePair| {
							if (std.mem.eql(u8, filePair.key, "length")) {
								const length = try bencode.GetInt(u64, filePair.value, null);
					            info.length += length;
								fileinfo.length = length;
								continue;
                            }
							if (std.mem.eql(u8, filePair.key, "path")) {
								var flist = try bencode.GetList(filePair.value, null);
								var flist_offset: usize = 0;
								var file = try bencode.GetString(flist[flist_offset..], &flist_offset);
                    			while (flist_offset < flist.len) {
                    				const pathname = file;
									file = try bencode.GetString(flist[flist_offset..], &flist_offset);
									const temppath = fileinfo.path;
									defer allocator.free(temppath);
									fileinfo.path = try std.fs.path.join(allocator, &[2][]const u8{
										fileinfo.path,
										pathname,
									});
								}
								fileinfo.name = try allocator.dupe(u8, file);
								continue;
                            }
                        }
						try list.append(fileinfo);
                    }
					info.files = try list.toOwnedSlice();
                }
            }
            torrent.infoHash = undefined;
            std.crypto.hash.Sha1.hash(temp.value, &torrent.infoHash, .{});
			if(info.files.len == 0) {
				var fileinfo: []FileInfo = try allocator.alloc(FileInfo, 1);
				fileinfo[0].path = try std.fs.path.join(allocator, &[2][]const u8{
					dirname,
					info.name,
				});
				fileinfo[0].name = info.name;
				fileinfo[0].length = info.length;
				info.files = fileinfo;
			}
            torrent.info = info;
        }
    }
    return torrent;
}

pub fn deinit(self: @This()) void {
    if (self.announce_list) |announce_list| self.allocator.free(announce_list);
    for (self.info.files) |file| self.allocator.free(file.path);
    self.allocator.free(self.info.files);
    self.allocator.free(self.buffer);
}

test {
    std.testing.refAllDecls(@This());
}
