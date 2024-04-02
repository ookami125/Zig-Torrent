const std = @import("std");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;
const NetUtils = @import("../NetUtils.zig");
const WS = @import("../Websocket.zig");
const WebSocket = WS.WebSocket;
const json = @import("../json.zig");
const EventBitfield = Coroutine.EventBitfield;
const EventType = Coroutine.EventType;

fn on_msg(msg: []const u8, ws: *WebSocket) void {
    std.log.debug("msg: ({}) {s}", .{ msg.len, msg });
    ws.send(msg) catch unreachable;
}

fn on_binary(msg: []const u8, ws: *WebSocket) void {
	const websocket = @fieldParentPtr(CoroutineWebsocket, "ws", ws);
	const allocator = websocket.uploaded_files.allocator;
	const dupe_msg = allocator.dupe(u8, msg) catch return;
	errdefer allocator.free(dupe_msg);
	websocket.uploaded_files.append(dupe_msg) catch return;
}

pub const UITracker = struct {
	url: []const u8,
};

pub const UIPeer = struct {
	peerName: []const u8,
	peerIp: []const u8,
};

pub const UITorrent = struct {
	trackers: []UITracker,
};

pub const UIData = struct {
	torrents: []UITorrent,
};

pub const CoroutineWebsocket = struct {
	state: States,
	response: std.http.Server.Response,
	ws: WebSocket,
	uploaded_files: std.ArrayList([]const u8),

	const States = enum {
		Unstarted,
		Active,
		Done,
	};
	
	pub fn init(response: std.http.Server.Response) !@This() {
		var self: @This() = undefined;
		self.state = .Unstarted;
		self.response = response;
		return self;
	}

	pub fn deinit(self: *@This(), ctx: *CoroutineContext) void {
		//_ = ctx;
		//self.response.deinit();
		self.ws.deinit();
		ctx.unsubscribe(.coroutineWebsocket, self);
	}

	pub fn send(self: *@This(), message_id: u32, data: anytype) !void {
		const _json = try std.json.stringifyAlloc(self.ws.allocator, .{
			.id = message_id,
			.data = data,
		}, .{});
		defer self.ws.allocator.free(_json);
		try self.ws.send(_json);
	}

	pub fn message(self: *@This(), ctx: *CoroutineContext, eventData: Coroutine.EventData) void {
		_ = ctx;
		switch (eventData) {
			inline else => |data| self.send(@intFromEnum(eventData), data) catch {},
			//.eventPeerUpdated => |data| self.updatePeer(ctx.allocator, data.*),
			//else => {},
		}
	}

	pub fn process(self: *@This(), ctx: *CoroutineContext) !bool {
		const ws_events = WS.WsEvents{
			.on_msg = on_msg,
			.on_binary = on_binary,
		};
		switch(self.state) {
			.Unstarted => {
				std.debug.print("Socket Connected!\n", .{});
				// will take the ownership of the response
				self.uploaded_files = @TypeOf(self.uploaded_files).init(ctx.allocator);
				self.ws = try WebSocket.init(ctx.allocator, &self.response);
				try self.ws.handleOnceInit(ws_events);
				self.state = .Active;

				ctx.subscribe(EventBitfield.initMany(&[_]EventType{
					.eventPeerConnected,
					.eventPeerHave,
					.eventPeerStateChange,
					.eventPeerDisconnected,
				}),
				.coroutineWebsocket,
				self);

				ctx.publish(.{ .eventRequestPeersConnected = undefined });
			},
			.Active => {
				while(try NetUtils.bytesAvailable(self.ws.stream.handle)) {
					if(!try self.ws.handleOnce(ws_events)) {
						std.debug.print("Socket Closed!\n", .{});
						self.state = .Done;
					}
				}
				if(self.uploaded_files.items.len > 0) {
					const file = self.uploaded_files.orderedRemove(0);
					defer ctx.allocator.free(file);
					const tempfile = try std.fs.cwd().createFile("temp.torrent", .{});
					_ = try tempfile.write(file);
					const path = try std.fs.cwd().realpathAlloc(ctx.allocator, "./temp.torrent");
					//defer ctx.allocator.free(path);
					try ctx.coroutineQueue.append(try Coroutine.create(ctx.allocator, .coroutineLoadTorrent, .{
						path
					}));
				}
			},
			.Done => {
				std.debug.print("Done!\n", .{});
				return true;
			},
		}
		return false;
	}
};