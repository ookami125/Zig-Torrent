const std = @import("std");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;
const NetUtils = @import("../NetUtils.zig");
const WS = @import("../Websocket.zig");
const WebSocket = WS.WebSocket;
const Bencode = @import("../bencode.zig");
const EventBitfield = Coroutine.EventBitfield;
const EventType = Coroutine.EventType;
const Hash = @import("../torrent.zig").Hash;

const MsgFilename = struct {
	filename: []const u8,
};

fn on_msg(msg: []const u8, ws: *WebSocket) void {
    std.log.debug("msg: ({}) {s}", .{ msg.len, msg });
	_ = ws;
}

const PacketData = union {
	Raw: []const u8,
	UploadedFile: struct {
		filename: []const u8,
		contents: []const u8,
	},
	RemoveTorrent: Hash,
};

const Packet = struct {
	packetType: u32,
	packetData: PacketData,
};

fn on_binary(msg: []const u8, ws: *WebSocket) void {
	var packet: Packet = undefined;
	var packetRaw = Bencode.GetDict(msg, null) catch return;
	while(packetRaw.next()) |pair| {
		if(std.mem.eql(u8, pair.key, "packetType")) {
			packet.packetType = Bencode.GetInt(u32, pair.value, null) catch return;
			continue;
		}
		if(std.mem.eql(u8, pair.key, "packetData")) {
			packet.packetData = .{ .Raw = pair.value };
			continue;
		}
	}
	handlePacket(&packet, ws) catch return;
}

const PacketID = enum(u32) {
	UploadFile = 5,
	RemoveTorrent = 6,
};

fn handlePacket(packet: *Packet, ws: *WebSocket) !void {
	const websocket = @fieldParentPtr(CoroutineWebsocket, "ws", ws);
	const allocator = websocket.packets.allocator;
	switch(packet.packetType) {
		5 => {
			var file: PacketData = .{ .UploadedFile = undefined, };
			var packetData = try Bencode.GetDict(packet.packetData.Raw, null);
			while(packetData.next()) |pair| {
				if(std.mem.eql(u8, pair.key, "filename")) {
					file.UploadedFile.filename = try allocator.dupe(u8, try Bencode.GetString(pair.value, null));
				}
				if(std.mem.eql(u8, pair.key, "contents")) {
					file.UploadedFile.contents = try allocator.dupe(u8, try Bencode.GetString(pair.value, null));
				}
			}
			packet.packetData = file;
			try websocket.packets.append(packet.*);
		},
		6 => {
			var hash: Hash = undefined;
			var packetData = try Bencode.GetDict(packet.packetData.Raw, null);
			while(packetData.next()) |pair| {
				if(std.mem.eql(u8, pair.key, "hash")) {
					const tempHash = try Bencode.GetString(pair.value, null);
					if(tempHash.len != 20) return error.HashIsWrongLength;
					std.mem.copyForwards(u8, &hash, tempHash);
				}
			}
			packet.packetData = .{ .RemoveTorrent = hash, };
			try websocket.packets.append(packet.*);
		},
		else => {},
	}
}

pub const CoroutineWebsocket = struct {
	state: States,
	response: std.http.Server.Response,
	ws: WebSocket,
	packets: std.ArrayList(Packet),

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
			.on_msg = on_binary,
			.on_binary = on_binary,
		};
		switch(self.state) {
			.Unstarted => {
				std.debug.print("Socket Connected!\n", .{});
				// will take the ownership of the response
				self.packets = @TypeOf(self.packets).init(ctx.allocator);
				self.ws = try WebSocket.init(ctx.allocator, &self.response);
				try self.ws.handleOnceInit(ws_events);
				self.state = .Active;

				ctx.subscribe(EventBitfield.initMany(&[_]EventType{
					.eventTorrentAdded,
					.eventTorrentRemoved,
					.eventPeerConnected,
					.eventPeerHave,
					.eventPeerStateChange,
					.eventPeerDisconnected,
				}),
				.coroutineWebsocket,
				self);

				ctx.publish(.{ .eventRequestGlobalState = undefined });
			},
			.Active => {
				while(try NetUtils.bytesAvailable(self.ws.stream.handle)) {
					if(!try self.ws.handleOnce(ws_events)) {
						std.debug.print("Socket Closed!\n", .{});
						self.state = .Done;
						break;
					}
				}
				for(self.packets.items) |packet| {
					switch(@as(PacketID, @enumFromInt(packet.packetType))) {
						PacketID.UploadFile => {
							const file = packet.packetData.UploadedFile;
							try ctx.addCoroutine(try Coroutine.create(ctx.allocator, .coroutineTorrentHandler, .{
								file.filename,
								file.contents
							}));
						},
						PacketID.RemoveTorrent => {
							std.debug.print("Remove torrent!\n", .{});
							ctx.publish(.{
								.eventRequestRemoveTorrent = .{
									.hash = packet.packetData.RemoveTorrent,
								},
							});
						}
					}
				}
				self.packets.clearRetainingCapacity();
			},
			.Done => {
				std.debug.print("Done!\n", .{});
				return true;
			},
		}
		return false;
	}
};