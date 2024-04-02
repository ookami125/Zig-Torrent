const std = @import("std");
const Torrent = @import("torrent.zig");
const Peer = @import("Peer.zig");
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
		const _coroutine = context.coroutineQueue.orderedRemove(0);
		var coroutine: *Coroutine = _coroutine;
		const done = switch(coroutine.coroutine) {
			inline else => |*ev| ev.process(&context) catch |err| blk: {
				std.debug.print("ERROR: {}\n", .{err});
				if(@hasField(@TypeOf(ev.*), "state")) {
					ev.state = .Done;
					break :blk false;
				}
				break :blk true;
			},
		};
		if(!done) {
			try context.addCoroutine(coroutine);
		} else {
			switch(coroutine.coroutine) {
				inline else => |*ev| {
					ev.deinit(&context);
				},		
			}
			context.coroutineQueue.allocator.destroy(coroutine);
		}
	}
}

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();
	//const allocator = std.heap.page_allocator;

	context = try Coroutine.CoroutineContext.init(allocator);
	defer context.deinit();

	// var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    // const dirpath = try std.fs.realpath("./torrents", &path_buffer);
    // var dir = try std.fs.cwd().openDir(dirpath, .{ .iterate = true, });
    // var dirIter = dir.iterate();
    // const entry = (try dirIter.next()).?;
    // const path: []const u8 = try dir.realpath(entry.name, &path_buffer);

	// const coroutine = try Coroutine.create(allocator, .coroutineLoadTorrent, .{path});
	// try context.coroutineQueue.append(coroutine);

	//var torrent = try Torrent.loadFile(allocator, path);

	//const coroutinePeer = try Coroutine.create(allocator, .coroutinePeerHandler, .{
	//	&torrent,
	//	[20]u8{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
	//	try std.net.Address.parseIp4("127.0.0.1", 58241)
	//});
	//try context.coroutineQueue.append(coroutinePeer);

	const coroutineLogger = try Coroutine.create(allocator, .coroutineLogger, .{});
	try context.addCoroutine(coroutineLogger);

	const coroutineWebserver = try Coroutine.create(allocator, .coroutineWebserver, .{});
	try context.addCoroutine(coroutineWebserver);

	defer {
		std.debug.print("Shutting down...\n", .{});
	}
	
	return processingLoop();
}

test {
    std.testing.refAllDecls(Torrent);
}
