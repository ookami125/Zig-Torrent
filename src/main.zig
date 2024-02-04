const std = @import("std");
const Torrent = @import("torrent.zig");
const Peer = @import("peer.zig");
const Tracker = @import("Tracker.zig");
const network = @import("network.zig");
const RangeArray = @import("RangeArray.zig").RangeArray;

const http = std.http;
const Client = std.http.Client;

const Coroutine = @import("Coroutine.zig");
var context: Coroutine.CoroutineContext = undefined;
var quit = false;

pub fn processingLoop() !void {
	while(!quit) {
		if(context.coroutineQueue.items.len == 0) break;
		var _coroutine = context.coroutineQueue.orderedRemove(0);
		var coroutine: *Coroutine = _coroutine;
		var done = switch(coroutine.coroutine) {
			inline else => |*ev| ev.process(&context) catch true,
		};
		if(!done) {
			try context.coroutineQueue.append(coroutine);
		} else {
			switch(coroutine.coroutine) {
				inline else => |*ev| ev.deinit(&context),
			}
			context.coroutineQueue.allocator.destroy(coroutine);
		}
	}
}

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();

	context = try Coroutine.CoroutineContext.init(allocator);
	defer context.deinit();

	var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const dirpath = try std.fs.realpath("./torrents", &path_buffer);
    var dir = try std.fs.cwd().openIterableDir(dirpath, .{});
    var dirIter = dir.iterate();
    var entry = (try dirIter.next()).?;
    const path: []const u8 = try dir.dir.realpath(entry.name, &path_buffer);

	var coroutine = try Coroutine.create(allocator, 0, .coroutineLoadTorrent, .{path});
	try context.coroutineQueue.append(coroutine);

	var coroutineLogger = try Coroutine.create(allocator, 0, .coroutineLogger, .{});
	try context.coroutineQueue.append(coroutineLogger);

	defer {
		std.debug.print("Shutting down...\n", .{});
	}
	
	return processingLoop();
}

test {
    std.testing.refAllDecls(Torrent);
}
