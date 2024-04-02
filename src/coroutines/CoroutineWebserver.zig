const std = @import("std");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;
const NetUtils = @import("../NetUtils.zig");

pub const CoroutineWebserver = struct {
	state: States,
	server: ?std.http.Server,

	const States = enum {
		Unstarted,
		WaitForConnection,
		Done,
	};
	
	pub fn init() !@This() {
		var self: @This() = undefined;
		self.state = .Unstarted;
		self.server = null;
		return self;
	}

	pub fn deinit(self: *@This(), ctx: *CoroutineContext) void {
		_ = ctx;
		if(self.server) |*server| server.deinit();
	}

	pub fn process(self: *@This(), ctx: *CoroutineContext) !bool {
		switch(self.state) {
			.Unstarted => {
				self.server = std.http.Server.init(ctx.allocator, .{ .reuse_address = true });

				const addr = try std.net.Address.parseIp("127.0.0.1", 8080);
				try self.server.?.listen(addr);
				std.log.info("server started in port: http://127.0.0.1:{}/", .{8080});
				
				self.state = .WaitForConnection;
			},
			.WaitForConnection => {
				if(try NetUtils.bytesAvailable(self.server.?.socket.sockfd.?)) {
					std.debug.print("Found web client...\n", .{});
					const client = try self.server.?.accept(.{ .allocator = ctx.allocator, });
					std.debug.print("Accepted web client...\n", .{});
					try ctx.coroutineQueue.append(try Coroutine.create(ctx.allocator, .coroutineWebclient, .{
						client
					}));
					std.debug.print("Appended web client...\n", .{});
				}
			},
			.Done => {

			},
		}
		return false;
	}
};