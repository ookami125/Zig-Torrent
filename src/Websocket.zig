const std = @import("std");
const Request = std.http.Server.Request;
const Response = std.http.Server.Response;

const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const WS_VERSION = "13";

/// removes any trilling or leading whitespace
///
/// returns a slice of the passed slice aka you don't own the slice it's just ref from the passed
/// slice
fn remove_whitespace(str: []const u8) []const u8 {
    var leading_whitespace: u8 = 0;
    var trailing_whitespace: u8 = 0;
    var last_char: u8 = ' ';
    var i: usize = 0;

    // count leading whitespace
    while (i < str.len) {
        if (str[i] != ' ') break;

        leading_whitespace += 1;
        last_char = ' ';
        i += 1;
    }

    // count trilling whitespace
    i = str.len - 1;
    while (i > 0) {
        if (str[i] != ' ') break;

        trailing_whitespace += 1;
        last_char = ' ';
        i -= 1;
    }

    return str[leading_whitespace .. str.len - trailing_whitespace];
}

fn switch_endian(comptime T: type, value: T) T {
    comptime {
        std.debug.assert(T == u16 or T == u64);
    }

    if (T == u16) {
        return (value >> 8) | (value << 8);
    } else {
        var swapped_value = value;
        swapped_value = (swapped_value & 0x00000000ffffffff) << 32 | (swapped_value & 0xffffffff00000000) >> 32;
        swapped_value = (swapped_value & 0x0000ffff0000ffff) << 16 | (swapped_value & 0xffff0000ffff0000) >> 16;
        swapped_value = (swapped_value & 0x00ff00ff00ff00ff) << 8 | (swapped_value & 0xff00ff00ff00ff00) >> 8;
        return swapped_value;
    }
}

/// verifies request and make sure it have the needed fileds with the appropriate data
/// it doesn't care about the origin header cus it's required from browser clients but not
/// other non-browser clients
///
/// more on the requirements here: [spec section 4.1](https://datatracker.ietf.org/doc/html/rfc6455#section-4.1)
fn is_valid_req(req: *const Request) !void {
    const Error = error{
        not_get_request,
        invalid_http_version,
        no_host_header,
        no_upgrade_header,
        no_connection_header,
        no_client_secret,
        no_websocket_version,
    };

    const eql = std.mem.eql;

    if (req.method != .GET) {
        return Error.not_get_request;
    }

    if (req.version != .@"HTTP/1.1") {
        return Error.invalid_http_version;
    }

    //  FIXME: should make sure it's a valid URI
    if (!req.headers.contains("Host")) {
        return Error.no_host_header;
    }

    if (req.headers.getFirstValue("Upgrade")) |header| {
        if (!eql(u8, remove_whitespace(header), "websocket")) return Error.no_upgrade_header;
    } else return Error.no_upgrade_header;

    if (req.headers.getFirstValue("Connection")) |header| {
        if (!eql(u8, remove_whitespace(header), "Upgrade")) return Error.no_connection_header;
    } else return Error.no_connection_header;

    if (req.headers.getFirstValue("Sec-WebSocket-Key")) |header| {
        const encoder = std.base64.standard.Encoder;
        // the spec states it should be a base64 encoding of a random 16-byte value
        if (remove_whitespace(header).len != encoder.calcSize(16)) return Error.no_client_secret;
    } else return Error.no_client_secret;

    if (req.headers.getFirstValue("Sec-WebSocket-Version")) |header| {
        if (!eql(u8, remove_whitespace(header), WS_VERSION)) return Error.no_websocket_version;
    } else return Error.no_websocket_version;
}

/// write the handshake response but doesn't send it
fn write_handshake(res: *Response) !void {
    const req = res.request;
    const client_sec = remove_whitespace(req.headers.getFirstValue("Sec-WebSocket-Key").?);

    // 512byte should be more than enough since it's the base64
    // encoding of a 16-byte
    //
    // "The value of this header field MUST be a
    //  nonce consisting of a randomly selected 16-byte value that has
    //  been base64-encoded"
    var buf: [512]u8 = undefined;
    const total_len = client_sec.len + WS_GUID.len;
    var concat_sec: []u8 = buf[0..total_len];
    @memcpy(concat_sec[0..client_sec.len], client_sec);
    @memcpy(concat_sec[client_sec.len..], WS_GUID);

    // sha1 output will always be 20b
    var sha1_output: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(concat_sec, &sha1_output, .{});

    // base64 encode the sha1 output
    const encoder = std.base64.standard.Encoder;
    const basae64_output_size = encoder.calcSize(sha1_output.len);

    // reusing the concat buffer
    const base64_output = buf[0..basae64_output_size];
    _ = encoder.encode(base64_output, &sha1_output);

    res.status = .switching_protocols;
    res.transfer_encoding = .{ .content_length = 0 };
    try res.headers.append("Upgrade", "websocket");
    try res.headers.append("Connection", "Upgrade");
    try res.headers.append("Sec-WebSocket-Accept", base64_output);
    try res.send();
}

/// op codes according to the [spec](https://datatracker.ietf.org/doc/html/rfc6455#section-11.8)
pub const Opcode = enum(u4) {
    op_continue = 0x0,
    text = 0x1,
    binary = 0x2,
    rsv3 = 0x3,
    rsv4 = 0x4,
    rsv5 = 0x5,
    rsv6 = 0x6,
    rsv7 = 0x7,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    rsvB = 0xB,
    rsvC = 0xC,
    rsvD = 0xD,
    rsvE = 0xE,
    rsvF = 0xF,

    pub fn is_control(opcode: Opcode) bool {
        return @intFromEnum(opcode) & 0x8 != 0;
    }
};

/// representation for the websocket header in revers
/// to account for the network byte order
const WsFrameHeader = packed struct {
    const Self = @This();

    // first byte
    opcode: Opcode,
    rsv3: u1 = 0,
    rsv2: u1 = 0,
    rsv1: u1 = 0,
    final: bool = true,

    // second byte
    size: u7,
    masked: bool = false,

    const mask_size = 4;
    const header_size = 2;
    const max_frame_size = mask_size + header_size + @sizeOf(u64);

    /// returns the size bytes count of the payload
    pub fn payload_size_bytes_count(self: *const Self) usize {
        return switch (self.size) {
            0...125 => 0,
            126 => @sizeOf(u16),
            127 => @sizeOf(u64),
        };
    }

    /// checks if it's a control frame aka close or ping or pong
    pub fn is_control(self: *const Self) bool {
        return switch (self.opcode) {
            .close, .ping, .pong => true,
            else => false,
        };
    }

    /// check if it's a valid frame rserved bits should be 0
    /// control frames can't fragmented and should be of size 125 max
    pub fn is_valid(self: *const Self) bool {
        var valid = (self.rsv3 | self.rsv2 | self.rsv1) == 0;

        if (self.is_control()) {
            valid = valid and self.final;
            valid = valid and self.size <= 125;
        }

        return valid;
    }

    comptime {
        // making sure the struct is always 2 bytes
        std.debug.assert(@sizeOf(@This()) == 2);
    }
};

/// struct to be passed by the user contains the callbacks
pub const WsEvents = struct {
    /// called whenever a message recived
    on_msg: ?fn ([]const u8, *WebSocket) void = null,
    /// called whenever a binary message recived
    on_binary: ?fn ([]const u8, *WebSocket) void = null,
    /// called after writing the response headers and before sending it
    on_upgrade: ?fn (*Response, *WebSocket) void = null,
    /// called when recived a close frame
    on_close: ?fn (?CloseStatus, ?[]const u8, *WebSocket) void = null,
    /// called when pinged
    on_ping: ?fn ([]const u8, *WebSocket) void = null,
    /// called when ponged
    on_pong: ?fn ([]const u8, *WebSocket) void = null,
};

/// close status .. it doesn't repsent nor respect the user_defined codes treat them all as 3000
pub const CloseStatus = enum(u16) {
    /// 1000 indicates a normal closure, meaning that the purpose for
    /// which the connection was established has been fulfilled.
    noraml = 1000,

    /// 1001 indicates that an endpoint is "going away", such as a server
    /// going down or a browser having navigated away from a page.
    going_away = 1001,

    /// 1002 indicates that an endpoint is terminating the connection due
    /// to a protocol error.
    protocol_error = 1002,

    // 1003 indicates that an endpoint is terminating the connection
    // because it has received a type of data it cannot accept (e.g., an
    // endpoint that understands only text data MAY send this if it
    // receives a binary message).
    unkown_data_type = 1003,

    /// 1007 indicates that an endpoint is terminating the connection
    /// because it has received data within a message that was not
    /// consistent with the type of the message (e.g., non-UTF-8 [RFC3629]
    /// data within a text message).
    wrong_data_type = 1007,

    /// 1008 indicates that an endpoint is terminating the connection
    /// because it has received a message that violates its policy.  This
    /// is a generic status code that can be returned when there is no
    /// other more suitable status code (e.g., 1003 or 1009) or if there
    /// is a need to hide specific details about the policy.
    policy_violation = 1008,

    /// 1009 indicates that an endpoint is terminating the connection
    /// because it has received a message that is too big for it to
    /// process.
    too_big_message = 1009,

    /// 1010 indicates that an endpoint (client) is terminating the
    /// connection because it has expected the server to negotiate one or
    /// more extension, but the server didn't return them in the response
    /// message of the WebSocket handshake.  The list of extensions that
    /// are needed SHOULD appear in the /reason/ part of the Close frame.
    /// Note that this status code is not used by the server, because it
    /// can fail the WebSocket handshake instead.
    requested_ext_not_avaliable = 1010,

    /// 1011 indicates that a server is terminating the connection because
    /// it encountered an unexpected condition that prevented it from
    /// fulfilling the request.
    unexpected_condition = 1011,

    //  FIXME: should respect the status code,
    // currently it's always 3000 it should be a range from 3000-4999
    /// defined by the user 3000 - 4999
    other = 3000,

    pub fn from_int(int: u16) !CloseStatus {
        return switch (int) {
            1000...1003, 1007...1011 => @enumFromInt(int),
            3000...4999 => CloseStatus.other,
            else => error.unkown_int,
        };
    }
};

/// the main struct proccess frames and manages fragmentations
pub const WebSocket = struct {
    const Self = @This();
    const Error = error{
        action_without_active_connection,
    };

    allocator: std.mem.Allocator,
    res: *Response,
    stream: *std.net.Stream,
    active: bool = false,
    frag_buff: std.ArrayList(u8),
    frag_op: ?Opcode = null,
    reciving_fragments: bool = false,

    /// init the object and checks if the request is a valid handshake request
    /// the request is data is included in the response object
    ///
    /// takes the ownership of the res object
    /// will handle cleaning the response object and closing the TCP conn
    pub fn init(allocator: std.mem.Allocator, res: *Response) !Self {
        // try is_valid_req(&res.request);

        const ws = Self{
            .allocator = allocator,
            .res = res,
            .stream = &res.connection.stream,
            .frag_buff = std.ArrayList(u8).init(allocator),
        };

        return ws;
    }

    pub fn deinit(self: *Self) void {
        self.frag_buff.deinit();
    }

    /// handle handshaking and proccess data frames
    /// don't use this inside WsEvents callbacks
    pub fn handle(self: *Self, comptime events: WsEvents) !void {
        self.handleOnceInit(events);
        while (try self.handleOnce(events)) {}
        self.handleOnceDeinit();
    }

	pub fn handleOnceInit(self: *Self, comptime events: WsEvents) !void {
        try write_handshake(self.res);

        if (events.on_upgrade) |on_upgrade|
            on_upgrade(self.res, self);

        try self.res.finish();
        self.active = true;
	}

	pub fn handleOnceDeinit(self: *Self) !void {
        self.res.deinit();
	}

    pub fn handleOnce(self: *Self, comptime events: WsEvents) !bool {
		if(!self.active) return false;

		var stream_reader = self.stream.reader();

		const frame_header = try stream_reader.readStruct(WsFrameHeader);

		// make sure it's valid
		if (!frame_header.is_valid()) {
			try self.close(.protocol_error, "unvalid header");
			return self.active;
		}

		// make sure it doesn't recive a non controle frame
		// until the current fragment ends
		if (self.reciving_fragments) {
			if (!frame_header.is_control() and
				frame_header.final and frame_header.opcode != .op_continue)
			{
				try self.close(.protocol_error, "invalid fragment");
				return self.active;
			}
		}

		// reading frame size
		var frame_payload_size: u64 = 0;
		const payload_size_bytes_count = frame_header.payload_size_bytes_count();

		if (payload_size_bytes_count == 0) {
			// defined in header
			frame_payload_size = frame_header.size;
		} else {
			// defined in payload
			if (payload_size_bytes_count == @sizeOf(u16)) {
				var buf: [@sizeOf(u16)]u8 = undefined;
				_ = try stream_reader.read(&buf);
				frame_payload_size = switch_endian(u16, std.mem.bytesAsValue(u16, &buf).*);
			} else {
				var buf: [@sizeOf(u64)]u8 = undefined;
				_ = try stream_reader.read(&buf);
				frame_payload_size = switch_endian(u64, std.mem.bytesAsValue(u64, &buf).*);
			}
		}

		// reading mask
		var mask: [WsFrameHeader.mask_size]u8 = undefined;
		if (frame_header.masked)
			_ = try stream_reader.readAtLeast(&mask, WsFrameHeader.mask_size);

		// reading frame payload
		var frame_payload = try self.allocator.alloc(u8, frame_payload_size);
		defer self.allocator.free(frame_payload);

		_ = try stream_reader.readAtLeast(frame_payload, frame_payload_size);

		// unmasking data
		if (frame_header.masked) {
			// unmasking according to the spec
			for (0.., frame_payload) |i, char| {
				frame_payload[i] = char ^ mask[i % 4];
			}
		}

		// handle frags
		if (!frame_header.final) {
			if (frame_header.opcode != .op_continue) {
				// fragments start
				self.frag_buff.clearRetainingCapacity();
				self.frag_op = frame_header.opcode;
				self.reciving_fragments = true;
			} else if (!self.reciving_fragments) {
				// a continuation without starting a fragments
				// should end conn
				try self.close(.protocol_error, "nothing to continue");
				return self.active;
			}

			// appending the fragments
			try self.frag_buff.appendSlice(frame_payload);
			return self.active;
		}

		// final output after assmpling fragments
		var opcode: Opcode = undefined;
		var payload: []u8 = undefined;

		if (frame_header.final == true and frame_header.opcode == .op_continue) {
			opcode = self.frag_op orelse {
				try self.close(.protocol_error, "there's nothing to continue");
				return self.active;
			};

			// append last payload
			try self.frag_buff.appendSlice(frame_payload);
			payload = self.frag_buff.items;

			self.reciving_fragments = false;
		} else {
			opcode = frame_header.opcode;
			payload = frame_payload;
		}

		switch (opcode) {
			.text => {
				if (!std.unicode.utf8ValidateSlice(payload)) {
					try self.close(.wrong_data_type, "invalid utf-8");
					return self.active;
				}

				if (events.on_msg) |on_msg|
					on_msg(payload, self);
			},
			.binary => {
				if (events.on_binary) |on_binary|
					on_binary(payload, self);
			},
			.close => {
				if (payload.len == 0) {
					if (events.on_close) |on_close|
						on_close(null, null, self);

					try self.close(null, null);
					return self.active;
				}

				if (payload.len < @sizeOf(u16)) {
					try self.close(.protocol_error, "payload w/o status code");
					return self.active;
				}

				if (!std.unicode.utf8ValidateSlice(payload[2..])) {
					try self.close(.protocol_error, "invalid utf-8, close frames payload must be valid utf-8");
					return self.active;
				}

				var status_raw = std.mem.bytesAsValue(u16, payload[0..@sizeOf(u16)]).*;
				status_raw = switch_endian(u16, status_raw);
				var status_code = CloseStatus.from_int(status_raw) catch {
					try self.close(.protocol_error, "invalid status code");
					return self.active;
				};

				// FIXME: defaulting to normal status code when recived application status code
				if (status_code == .other) status_code = .noraml;

				const msg = payload[@sizeOf(u16)..];
				if (events.on_close) |on_close|
					on_close(status_code, msg, self);

				try self.close(status_code, msg);
			},
			.ping => {
				try self.pong(payload);

				if (events.on_ping) |on_ping|
					on_ping(payload, self);
			},
			.pong => {
				if (events.on_pong) |on_pong|
					on_pong(payload, self);
			},
			else => {
				try self.close(.protocol_error, "unkown_opcode");
			},
		}
		return self.active;
    }

    /// sending close frame and closing the connection
    pub fn close(self: *Self, status_code: ?CloseStatus, msg: ?[]const u8) !void {
        if (!self.active) return Error.action_without_active_connection;

        if (msg) |msg_unwrapped| {
            const status_code_unwrapped = status_code orelse return error.message_without_status_code;

            var sent_message = try self.allocator.alloc(u8, msg_unwrapped.len + @sizeOf(CloseStatus));
            defer self.allocator.free(sent_message);

            var status_code_num = switch_endian(u16, @intFromEnum(status_code_unwrapped));
            @memcpy(sent_message[0..@sizeOf(u16)], std.mem.asBytes(&status_code_num));
            @memcpy(sent_message[@sizeOf(u16)..], msg_unwrapped);

            try self.write(.close, sent_message);
        } else {
            try self.write(.close, "");
        }

        self.active = false;
    }

    /// send unmasked message as the server should according to the spec
    pub fn send(self: *Self, msg: []const u8) !void {
        if (!self.active) return Error.action_without_active_connection;

        try self.write(.text, msg);
    }

    /// send binary message unmasked
    pub fn send_binary(self: *Self, msg: []const u8) !void {
        if (!self.active) return Error.action_without_active_connection;

        try self.write(.binary, msg);
    }

    /// send ping frame
    pub fn ping(self: *Self, msg: []const u8) !void {
        if (!self.active) return Error.action_without_active_connection;

        try self.write(.ping, msg);
    }

    /// send pong frame
    pub fn pong(self: *Self, msg: []const u8) !void {
        if (!self.active) return Error.action_without_active_connection;

        try self.write(.pong, msg);
    }

    /// internal writes the connection stream
    fn write(self: *Self, opcode: Opcode, payload: []const u8) !void {
        var total_size: usize = 0;

        const frame_header_size: u7 = switch (payload.len) {
            0...125 => @truncate(payload.len),
            126...65535 => 126,
            else => 127,
        };

        total_size += WsFrameHeader.header_size;
        var reply = WsFrameHeader{
            .size = frame_header_size,
            .opcode = opcode,
        };

        const payload_size_bytes = reply.payload_size_bytes_count();
        total_size += payload_size_bytes;
        total_size += payload.len;

        var data_frame = try self.allocator.alloc(u8, total_size);
        defer self.allocator.free(data_frame);

        var i: usize = 0;
        const header = std.mem.asBytes(&reply);
        @memcpy(data_frame[i..WsFrameHeader.header_size], header);
        i += WsFrameHeader.header_size;

        if (payload_size_bytes == @sizeOf(u16)) {
            const size: u16 = @truncate(payload.len);
            // swap endiannes for the network
            const swapped_size = switch_endian(u16, size);
            @memcpy(
                data_frame[i .. i + @sizeOf(u16)],
                std.mem.asBytes(&swapped_size),
            );
            i += @sizeOf(u16);
        } else if (payload_size_bytes == @sizeOf(u64)) {
            const size: u64 = @truncate(payload.len);
            // swap endiannes for the network
            const swapped_size = switch_endian(u64, size);
            @memcpy(
                data_frame[WsFrameHeader.header_size .. WsFrameHeader.header_size + @sizeOf(u64)],
                std.mem.asBytes(&swapped_size),
            );
            i += @sizeOf(u64);
        }

        @memcpy(data_frame[i .. i + payload.len], payload);
        _ = try self.stream.writeAll(data_frame);
    }
};
