const std = @import("std");
const Torrent = @import("torrent.zig");
const Tracker = @import("tracker.zig");
const TrackerManager = @import("trackerManager.zig");

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();
    
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var trackerManager: TrackerManager = undefined;
    try trackerManager.init(allocator);
    defer trackerManager.deinit();

	const dirpath = try std.fs.realpath("./torrents", &path_buffer); 
	var dir = try std.fs.cwd().openIterableDir(dirpath, .{});
	var dirIter = dir.iterate();
	while(try dirIter.next()) |entry| {
		if(entry.kind != .file) continue;
		const path = try dir.dir.realpath(entry.name, &path_buffer);//try std.fs.realpath(, &path_buffer); 

		var torrent = try Torrent.loadFile(allocator, path);
		defer torrent.deinit();
		std.debug.print("Hash: {any}\n", .{torrent.infoHash});
		std.debug.print("Announce: {s}\n", .{torrent.announce});
		std.debug.print("Announce-list:\n", .{});
		for(torrent.announce_list) |announce| {
			std.debug.print("\t{s}\n", .{announce});
		}

		var selectedAnnounce = torrent.announce_list[0];

		var uri = try std.Uri.parse(selectedAnnounce);
		var tracker = try trackerManager.addTracker(allocator, uri);
		try tracker.sendConnect();
		try tracker.getPeers(&torrent);
	}
}

test {
    std.testing.refAllDecls(Torrent);
}