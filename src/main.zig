const std = @import("std");
const Torrent = @import("torrent.zig");
const Tracker = @import("tracker.zig");
const TrackerManager = @import("trackerManager.zig");
const Peer = @import("peer.zig");

const http = std.http;
const Client = std.http.Client;

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
    var entry = (try dirIter.next()).?; //blk: while() |entry| { break :blk entry; };
    //if(entry.kind != .file) continue;
    const path = try dir.dir.realpath(entry.name, &path_buffer);
    //try std.fs.realpath(, &path_buffer);

    var torrent = try Torrent.loadFile(allocator, path);
    defer torrent.deinit();
    std.debug.print("Hash: {any}\n", .{torrent.infoHash});
    std.debug.print("Announce: {s}\n", .{torrent.announce});
    if (torrent.announce_list) |announce_list| {
        std.debug.print("Announce-list:\n", .{});
        for (announce_list) |announce| {
            std.debug.print("\t{s}\n", .{announce});
        }
    }

    var tracker: *Tracker = undefined;
    if (torrent.announce_list) |announce_list| {
        for (announce_list) |announce| {
            var uri = try std.Uri.parse(announce);
            tracker = try trackerManager.addTracker(allocator, uri);
            errdefer trackerManager.removeTracker(tracker);

            tracker.connect() catch |err| {
                if (err == error.WouldBlock) continue;
                return err;
            };
            tracker.getPeers(&torrent) catch |err| {
                if (err == error.WouldBlock) continue;
                return err;
            };
            break;
        }
    } else {
        var uri = try std.Uri.parse(torrent.announce);
        tracker = try trackerManager.addTracker(allocator, uri);

        try tracker.connect();
        try tracker.getPeers(&torrent);
    }

    for (tracker.peers.items) |endpoint| {
        std.debug.print("Peer {any}\n", .{endpoint});
        var peer: Peer = Peer.init(allocator, endpoint, 51444, &torrent) catch |err| {
            std.debug.print("Err: [Peer.init] {}\n", .{err});
            continue;
        };
        defer peer.deinit();

        try peer.process();
        try peer.Interested();

        // Iterate 1000 times to process packets until we get the bitfield
        for (0..1000) |_| {
            if (!peer.bitfielded) {
                try peer.process();
                std.time.sleep(50_000_000);
                continue;
            } else break;
        } else {
            if (peer.bitfielded) {
                if (peer.GetBlockCount() == 0) {
                    std.debug.print("Peer never responded, skipping...\n", .{});
                    continue;
                }
            } else {
                std.debug.print("Peer never responded, skipping...\n", .{});
                continue;
            }
        }

        while (true) {
            try peer.process();
            if (peer.localState.Unchoked and !peer.waitingForBlock) {
                try peer.GetNextBlock();
            }
        }
    }

    tracker.deinit();
}

test {
    std.testing.refAllDecls(Torrent);
}
