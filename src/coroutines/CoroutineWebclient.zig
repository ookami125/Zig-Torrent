const std = @import("std");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;
const NetUtils = @import("../NetUtils.zig");

// Handle an individual request.
fn handleRequest(response: *std.http.Server.Response, allocator: std.mem.Allocator) !void {

    // Log the request details.
    std.log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    // Read the request body.
    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    // Set "connection" header to "keep-alive" if present in request headers.
    // if (response.request.headers.contains("connection")) {
    //     try response.headers.append("connection", "keep-alive");
    // }

	var target = response.request.target;
	if(std.mem.startsWith(u8, target, "/")) {
		if(std.mem.endsWith(u8, target, "/")) {
			var ntarget = try allocator.alloc(u8, target.len + 11);
			ntarget[0] = '.';
			std.mem.copyForwards(u8, ntarget[1..], target);
			std.mem.copyForwards(u8, ntarget[target.len+1..], "index.html");
			target = ntarget;
		} else {
			var ntarget = try allocator.alloc(u8, target.len + 1);
			ntarget[0] = '.';
			std.mem.copyForwards(u8, ntarget[1..], target);
			target = ntarget;
		}
	}
	defer if(target.ptr != response.request.target.ptr) allocator.free(target);

	std.debug.print("modified path: {s}\n", .{target});

    // Check if the request target starts with "/get".
	const publicDir = try std.fs.cwd().openDir("www", .{});
	const file = publicDir.openFile(target, .{}) catch {
		std.debug.print("file not found: {s}\n", .{target});
		// Set the response status to 404 (not found).
		response.status = .not_found;
		try response.send();
		try response.finish();
		return;
	};
	defer file.close();

	const data = try file.readToEndAlloc(allocator, 2_000_000_000);
	defer allocator.free(data);

	if (std.mem.indexOf(u8, response.request.target, "?chunked") != null) {
		response.transfer_encoding = .chunked;
	} else {
		response.transfer_encoding = .{ .content_length = data.len };
	}

	// Set "content-type" header to "text/plain".
	if(std.mem.endsWith(u8, target, ".js")) {
		try response.headers.append("content-type", "text/javascript");
	} else {
		try response.headers.append("content-type", "text/html");
	}

	// Write the response body.
	try response.send();
	if (response.request.method != .HEAD) {
		try response.writeAll(data);
	}
	try response.finish();
}

pub const CoroutineWebclient = struct {
	state: States,
	client: std.http.Server.Response,
	dontDeinit: bool,

	const States = enum {
		Unstarted,
		Active,
		Done,
	};
	
	pub fn init(client: std.http.Server.Response) !@This() {
		var self: @This() = undefined;
		self.state = .Unstarted;
		self.client = client;
		self.dontDeinit = false;
		return self;
	}

	pub fn deinit(self: *@This(), ctx: *CoroutineContext) void {
		_ = ctx;
		if(self.dontDeinit) return;
		self.client.deinit();
	}

	pub fn process(self: *@This(), ctx: *CoroutineContext) !bool {
		switch(self.state) {
			.Unstarted => {
				self.state = .Active;
				std.debug.print("Webclient: Starting\n", .{});
			},
			.Active => blk: {
				while(try NetUtils.bytesAvailable(self.client.connection.stream.handle)) {
					std.debug.print("Webclient: Running\n", .{});
					self.client.wait() catch |err| switch (err) {
						error.HttpHeadersInvalid => break :blk,
						error.EndOfStream => {
							self.state = .Done;
							break :blk;
						},
						else => return err,
					};

					const upgrade = self.client.request.headers.getFirstValue("upgrade");

					if(upgrade != null and std.mem.eql(u8, upgrade.?, "websocket")) {
						try ctx.addCoroutine(try Coroutine.create(ctx.allocator, .coroutineWebsocket, .{
							self.client
						}));
						self.dontDeinit = true;
						self.state = .Done;
						break :blk;
					}
					try handleRequest(&self.client, ctx.allocator);
					_ = self.client.reset();
				}
			},
			.Done => {
				return true;
			},
		}
		return false;
	}
};