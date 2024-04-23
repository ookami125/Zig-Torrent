const std = @import("std");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;

pub const CoroutineLogger = struct {
	start: i64,
	timer: u64,
	
	pub fn init() !@This() {
		var self: @This() = undefined;
		self.start = std.time.milliTimestamp();
		self.timer = 0;
		return self;
	}

	pub fn deinit(self: *@This(), ctx: *CoroutineContext) void {
		_ = ctx;
		_ = self;
	}

	pub fn process(self: *@This(), ctx: *CoroutineContext) !bool {
		
		if(self.timer < std.time.milliTimestamp()) {
			const timestamp: u64 = @intCast(std.time.milliTimestamp() - self.start);
			const hours = @divTrunc(timestamp % std.time.ms_per_day, std.time.ms_per_hour);
			const mins = @divTrunc(timestamp % std.time.ms_per_hour, std.time.ms_per_min);
			const secs = @divTrunc(timestamp % std.time.ms_per_min, std.time.ms_per_s);
			std.debug.print("[{d}:{d:0>2}:{d:0>2}] Running Coroutines: {}\n", .{hours, mins, secs, ctx.coroutineQueue.items.len});
			var counts = std.EnumArray(Coroutine.CoroutineType, u32).initFill(0);
			for(ctx.coroutineQueue.items) |item| {
				counts.set(item.coroutine, counts.get(item.coroutine) + 1);
			}
			for(counts.values, 0..) |v, i| {
				std.debug.print("[{}] {}\n", .{@as(Coroutine.CoroutineType, @enumFromInt(i)), v});
			}
			std.debug.print("Torrents:\n", .{});
			for(ctx.torrents.items) |torrent| {
				std.debug.print("[{s}] {d:0.2}%\n", .{torrent.file.info.name, 100.0 * @as(f32, @floatFromInt(torrent.getDownloaded())) / @as(f32, @floatFromInt(torrent.getSize()))});
			}
			self.timer = @as(u64, @intCast(std.time.milliTimestamp())) + 10_000;
		}
		return ctx.coroutineQueue.items.len == 0;
	}
};