const std = @import("std");
const Torrent = @import("../torrent.zig");
const Coroutine = @import("../Coroutine.zig");
const CoroutineContext = Coroutine.CoroutineContext;
const EventBitfield = Coroutine.EventBitfield;
const EventType = Coroutine.EventType;

// pub extern fn open(__file: [*c]const u8, __oflag: c_int, ...) c_int;
// pub const __off_t = c_long;
// pub extern fn ftruncate(__fd: c_int, __length: __off_t) c_int;
// pub extern fn mmap(__addr: ?*anyopaque, __len: usize, __prot: c_int, __flags: c_int, __fd: c_int, __offset: __off_t) ?*anyopaque;
// pub const MappedFile = extern struct {
//     fd: c_int = @import("std").mem.zeroes(c_int),
//     location: u64 = @import("std").mem.zeroes(u64),
//     contents: [*c]u8 = @import("std").mem.zeroes([*c]u8),
//     contents_length: usize = @import("std").mem.zeroes(usize),

// 	pub fn mapFile(arg_filename: [*c]const u8, file_size: c_ulonglong, arg_mapped_file: [*c]MappedFile) !void {
// 		var filename = arg_filename;
// 		_ = &filename;
// 		var mapped_file = arg_mapped_file;
// 		_ = &mapped_file;
// 		mapped_file.*.fd = open(filename, @as(c_int, 2) | @as(c_int, 64), @as(c_int, 256) | @as(c_int, 128));
// 		if (mapped_file.*.fd == -@as(c_int, 1)) {
// 			return error.FailedToOpenFile;
// 		}
// 		mapped_file.*.contents_length = @as(usize, @bitCast(file_size));
// 		if (ftruncate(mapped_file.*.fd, @as(__off_t, @bitCast(mapped_file.*.contents_length))) == -@as(c_int, 1)) {
// 			return error.FailedToTruncateFile;
// 		}
// 		mapped_file.*.contents = @as([*c]u8, @ptrCast(@alignCast(mmap(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))), mapped_file.*.contents_length, @as(c_int, 1) | @as(c_int, 2), @as(c_int, 1), mapped_file.*.fd, @as(__off_t, @bitCast(@as(c_long, @as(c_int, 0))))))));
// 		if (mapped_file.*.contents == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(0xffffffffffffffff)))))) {
// 			return error.FailedToMapFile;
// 		}
// 	}
// };

pub const MappedFile = struct {
	fileDescriptor: ?std.os.fd_t,
	location: u64,
	contents: ?[]u8,

	pub fn init(location: u64) @This() {
		return .{
			.fileDescriptor = null,
			.location = location,
			.contents = null,
		};
	}

	pub fn mapFile(self: *@This(), file_path: []const u8, ptr: ?[*]align(std.mem.page_size)u8, length: usize) !void {
		self.fileDescriptor = try std.os.open(file_path, std.os.O.RDWR | std.os.O.CREAT, std.os.S.IRUSR | std.os.S.IWUSR);
		try std.os.ftruncate(self.fileDescriptor.?, length);
		self.contents = try std.os.mmap(ptr, length, std.os.PROT.READ | std.os.PROT.WRITE, std.os.MAP.SHARED, self.fileDescriptor.?, 0);
	}

	pub fn sync(self: *@This()) !void {
		return std.os.msync(self.contents.?, std.os.MSF.SYNC);
	}

	pub fn unmapFile(self: *@This()) void {
		std.os.munmap(self.contents);
	}
};

pub const CoroutineTorrentHandler = struct {
	filename: []const u8,
	contents: []const u8,
	torrent: *Torrent,
	files: []MappedFile,
	state: States,
	pieceCheckOffset: u64,

	const States = enum {
		Unloaded,
		CheckingPieces,
		ContactingAnnounce,
		Loaded,
		Done,
	};

	pub fn init(filename: []const u8, contents: []const u8) !@This() {
		var self: @This() = undefined;
		self.filename = filename;
		self.contents = contents;
		self.state = .Unloaded;
		self.torrent = undefined;
		return self;
	}

	pub fn deinit(self: *@This(), ctx: *CoroutineContext) void {
		ctx.unsubscribe(.coroutineTorrentHandler, self);
		ctx.allocator.free(self.filename);
		ctx.allocator.free(self.contents);
	}

	fn createOrOpenFile(path: []const u8, name: []const u8) !std.fs.File {
		const cwd = std.fs.cwd();
		const dir = cwd.openDir(path, .{}) catch blk: {
			break :blk try cwd.makeOpenPath(path, .{});
		};
		const file = dir.openFile(name, .{.mode = .read_write, }) catch blk: {
			break :blk try dir.createFile(name, .{.read = true, .truncate = false, });
		};
		return file;
	}

	fn search(array: []MappedFile, _start_idx: usize, _end_idx: usize, search_val: u64) usize {
		var left = _start_idx;
		var right = _end_idx;

		while(left < right)
		{
			const mid = (left + right) / 2;

			if(array[mid].location < search_val + 1) {
				left = mid + 1;
			} else {
				right = mid;
			}
		}

		if(left == 0) return 0;
		return left - 1;
	}

	fn getFile(self: @This(), allocator: std.mem.Allocator, i: usize) !void
	{
		if(self.files[i].contents == null) {
			const file = self.torrent.file.info.files[i];
			const fullPath = try std.fs.path.join(allocator, &[2][]const u8{
				file.path, file.name
			});
			defer allocator.free(fullPath);
			const cwd = std.fs.cwd();
			var dir = cwd.openDir(file.path, .{}) catch blk: {
				break :blk try cwd.makeOpenPath(file.path, .{});
			};
			dir.close();
			try self.files[i].mapFile(fullPath, null, file.length);
		}
	}

	//FIXME: This code is broken somehow, verified via downloading using an external
	// client and having this run a piece check afterwards.
	fn writeToFiles(self: *@This(), allocator: std.mem.Allocator, _byteOffset: u64, _data: []const u8) !void {
		var byteOffset = _byteOffset;
		var data = _data;

		const data2 = try allocator.alloc(u8, _data.len);
		defer allocator.free(data2);
		try self.readFromFiles(allocator, _byteOffset, data2);

		const fileIdx : usize = search(self.files, 0, self.files.len, byteOffset);
		std.debug.assert(self.files[fileIdx].location <= byteOffset);

		byteOffset -= self.files[fileIdx].location;

		for(self.torrent.file.info.files[fileIdx..], fileIdx..) |file, i| {
			const write_length = @min(file.length - byteOffset, data.len);
			
			try self.getFile(allocator, i);
			std.mem.copyForwards(u8, 
				self.files[i].contents.?[byteOffset..(byteOffset+write_length)],
				data[0..write_length],
			);
			if(write_length < data.len) {
				data = data[write_length..];
				byteOffset = 0;
			}
			else break;
		}
	}

	fn readFromFiles(self: *@This(), allocator: std.mem.Allocator, _byteOffset: u64, _data: []u8) !void {
		var byteOffset = _byteOffset;
		var data = _data;

		const fileIdx : usize = search(self.files, 0, self.files.len, byteOffset);
		std.debug.assert(self.files[fileIdx].location <= byteOffset);

		byteOffset -= self.files[fileIdx].location;

		for(self.torrent.file.info.files[fileIdx..], fileIdx..) |file, i| {
			const write_length = @min(file.length - byteOffset, data.len);
			
			try self.getFile(allocator, i);
			const destSlice = data[0..write_length];
			const srcSlice = self.files[i].contents.?[byteOffset..(byteOffset+write_length)];
			std.mem.copyForwards(u8, 
				destSlice,
				srcSlice,
			);
			if(write_length < data.len) {
				data = data[write_length..];
				byteOffset = 0;
			}
			else break;
		}
	}

	fn popCountArray(data: []const u8) u64 {
		var count: u64 = 0;
		for(data) |elem| {
			count += @popCount(elem);
		}
		return count;
	}

	pub fn completed(bitfield: Torrent.TBitfield) u64 {
		return popCountArray(bitfield.bytes);
	}

	pub fn message(self: *@This(), ctx: *CoroutineContext, eventData: Coroutine.EventData) void {
		switch (eventData) {
			.eventRequestGlobalState => |data| {
				ctx.publishDirect(data.requester, .{
					.eventTorrentAdded = .{
						.hash = self.torrent.file.infoHash,
						.pieces = self.torrent.file.info.pieces.len,
						.completed = completed(self.torrent.bitfield),
					}
				});
			},
			.eventBlockReceived => |block| {
				if(!std.mem.eql(u8, &block.hash, &self.torrent.file.infoHash)) {
					return;
				}
				const start: u64 = block.pieceIdx * self.torrent.file.info.pieceLength + block.blockOffset;
				self.writeToFiles(ctx.allocator, start, block.data) catch {};
			},
			.eventRequestReadBlock => |block| {
				if(!std.mem.eql(u8, &block.hash, &self.torrent.file.infoHash)) {
					return;
				}
				const start: u64 = block.pieceIdx * self.torrent.file.info.pieceLength;
				self.readFromFiles(ctx.allocator, start, block.data) catch {};
			},
			.eventRequestRemoveTorrent => |block| {
				if(!std.mem.eql(u8, &block.hash, &self.torrent.file.infoHash)) {
					return;
				}
				self.state = .Done;
			},
			else => {},
		}
	}

	fn writePieceFile(path: []const u8, i: u64, data: []const u8) !void {
		var file_path_raw: [32]u8 = undefined;
		const file_path = try std.fmt.bufPrint(&file_path_raw, "{}.piece", .{i});
		const dir = try std.fs.cwd().openDir(path, .{});
		const file = try dir.createFile(file_path, .{});
		try file.writeAll(data);
	}
	
	fn processInternal(self: *@This(), ctx: *CoroutineContext) !bool {
		switch(self.state) {
			.Unloaded => {
				self.torrent = try ctx.allocator.create(Torrent);
				std.debug.print("torrent path: {s}\n", .{self.filename});
				self.torrent.* = try Torrent.loadRaw(ctx.allocator, self.filename, self.contents);
				try ctx.torrents.append(self.torrent);

				self.files = try ctx.allocator.alloc(MappedFile, self.torrent.file.info.files.len);
				var fileOffset: u64 = 0;
				for(self.torrent.file.info.files, 0..) |file, i| {
					self.files[i] = MappedFile.init(fileOffset);
					fileOffset += file.length;
				}

				ctx.subscribe(EventBitfield.initMany(&[_]EventType{
					.eventRequestGlobalState,
					.eventBlockReceived,
					.eventRequestReadBlock,
					.eventRequestRemoveTorrent,
				}),
				.coroutineTorrentHandler,
				self);

				ctx.publish(.{
					.eventTorrentAdded = .{
						.hash = self.torrent.file.infoHash,
						.pieces = self.torrent.file.info.pieces.len,
						.completed = 0,
					}
				});

				self.state = .CheckingPieces;
				self.pieceCheckOffset = 0;
			},
			.CheckingPieces => {
				// TODO: Need to implement already downloaded piece checking.
				// Shouldn't be to hard, just need to wire in the existing checking code.
				const temp = try ctx.allocator.alloc(u8, self.torrent.file.info.pieceLength);
				const temp2 = try ctx.allocator.alloc(u8, self.torrent.file.info.pieceLength);
				//for(0..temp.len) |i| temp[i] = 0;
				defer ctx.allocator.free(temp);
				defer ctx.allocator.free(temp2);
				const startPiece = self.pieceCheckOffset;
				const endPiece = @min(startPiece + 10, self.torrent.file.info.pieces.len);
				for(self.torrent.file.info.pieces[startPiece..endPiece], startPiece..endPiece) |piece_hash, i| {
					const start: u64 = i * self.torrent.file.info.pieceLength;
					const end: u64 = @min((i+1) * self.torrent.file.info.pieceLength, self.torrent.file.info.length);
					//try self.torrent.outfile.seekTo(start);
					//const len = try self.torrent.outfile.readAll(temp);
					//if(len < (end-start)) {
					//	std.debug.print("PIECE NOT OF CORRECT LENGTH! {}\n", .{i});
					//	continue;
					//}
					self.readFromFiles(ctx.allocator, start, temp2[0..(end-start)]) catch |err| {
						std.debug.print("ERROR: {}\n", .{err});
						std.debug.print("FAILED TO READ PIECE FROM FILES! {}\n", .{i});
						continue;
					};
					//if(!std.mem.eql(u8, temp[0..len], temp2[0..len])) {
					//	std.debug.print("SINGLE AND MULTIFILE CONTENTS NOT EQUAL! {}\n", .{i});
					//	writePieceFile("downloads/zig-piece-fails/", i, temp2) catch {};
					//	continue;
					//}
					// for(piece_hash) |b|
					// 	std.debug.print("{x:0>2}", .{b});
					// std.debug.print(" - ", .{});
					// var buff: Torrent.Hash = undefined;
					// std.crypto.hash.Sha1.hash(temp, &buff, .{});
					// for(buff) |b|
					// 	std.debug.print("{x:0>2}", .{b});
					// std.debug.print("\n", .{});
					if(Torrent.pieceCheck(i, temp2[0..(end-start)], piece_hash)) {
						//std.debug.print("completed: {}\n", .{i});
						self.torrent.bitfield.set(i, 1);
						try self.torrent.notDownloaded.remove(start, end);
						try self.torrent.downloaded.add(start, end);
					}
					//else
					//{
					//	std.debug.print("not completed: {}\n", .{i});
					//}
				}
				self.pieceCheckOffset = endPiece;
				if(endPiece == self.torrent.file.info.pieces.len) {
					self.state = .ContactingAnnounce;
				}

				ctx.publish(.{
					.eventTorrentAdded = .{
						.hash = self.torrent.file.infoHash,
						.pieces = self.torrent.file.info.pieces.len,
						.completed = completed(self.torrent.bitfield),
					}
				});
			},
			.ContactingAnnounce => {
				const announces = if(self.torrent.file.announce_list) |announce_list| announce_list else @as([*][]const u8, @ptrCast(&self.torrent.file.announce))[0..1];
				for(announces) |announce| {
					try ctx.addCoroutine(try Coroutine.create(ctx.allocator, .coroutineConnectTracker, .{
						try std.Uri.parse(announce),
						self.torrent
					}));
				}
				self.state = .Loaded;
			},
			.Loaded => {
				//TODO: Idles here and never gets removed, there should be conditions or events to handle this.
			},
			.Done => {
				const idx : usize = std.mem.indexOfScalar(*Torrent, ctx.torrents.items, self.torrent) orelse { return true; };
				_ = ctx.torrents.orderedRemove(idx);
				ctx.publish(.{ .eventTorrentRemoved = .{
					.hash = self.torrent.file.infoHash,
				}});
				return true;
			}
		}
		return false;
	}

	pub fn process(self: *@This(), ctx: *CoroutineContext) !bool {
		return processInternal(self, ctx) catch {
			self.state = .Done;
			return false; 
		};
	}
};