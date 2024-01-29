const std = @import("std");

pub fn RangeArray(comptime T: type) type {
	return struct {
		//Ranges need to be in the format [start, end)
		//The start is inclusive, the end it exclusive
		pub const Range = struct {
			start: T,
			end: T,

			pub fn initLen(start: T, len: T) @This() {
				return @This(){
					.start = start,
					.end = start + len,
				};
			}

			pub fn length(self: @This()) T {
				return self.end - self.start;
			}
		};
		allocator: std.mem.Allocator,
		ranges: []Range,
		capacity: usize,

		pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !@This() {
			var array: @This() = undefined;
			array.allocator = allocator;
			array.ranges = try allocator.alloc(Range, initial_capacity);
			array.ranges.len = 0;
			array.capacity = initial_capacity;
			return array;
		}

		pub fn deinit(self: *@This()) void {
			self.ranges.len = self.capacity;
			self.allocator.free(self.ranges);
		}

		fn ensureCapacity(self: *@This(), capacity: usize) !void {
			if(capacity > self.capacity) {
				var old_cap = self.ranges.len;
				self.capacity = capacity;
				self.ranges = try self.allocator.realloc(self.ranges, self.capacity);
				self.ranges.len = old_cap;
			}
		}

		pub fn merge(array: *@This()) !void {
			var i: usize = 0;
			while(i < array.ranges.len - 1) {
				var curr = array.ranges[i];
				var next = array.ranges[i+1];
				if(curr.end == next.start) {
					array.ranges[i].end = next.end;
					if(i < array.ranges.len - 2) {
						std.mem.copyForwards(Range, array.ranges[i+1..], array.ranges[i+2..]);
					}
					array.ranges.len -= 1;
				} else i += 1;
			}
		}

		pub fn add(arg_array: *@This(), arg_start: T, arg_end: T) !void {
			var array = arg_array;
			var start = arg_start;
			var end = arg_end;
			var i: usize = 0;
			while (i < array.ranges.len) {
				if (start >= array.ranges[i].end) {
					i += 1;
				} else if (end <= array.ranges[i].start) {
					try array.ensureCapacity(array.ranges.len+1);
					array.ranges.len += 1;
					std.mem.copyBackwards(Range, array.ranges[i+1..array.ranges.len], array.ranges[i..array.ranges.len-1]);
					array.ranges[i].start = start;
					array.ranges[i].end = end;
					break;
				} else {
					start = if (start < array.ranges[i].start) start else array.ranges[i].start;
					end = if (end > array.ranges[i].end) end else array.ranges[i].end;
					{
						var j: usize = i;
						while (j < (array.ranges.len - 1)) : (j += 1) {
							array.ranges[j] = array.ranges[j+1];
						}
					}
					array.ranges.len -= 1;
				}
			}
			if (i == array.ranges.len) {
				try array.ensureCapacity(array.ranges.len+1);
				array.ranges.len += 1;
				array.ranges[i].start = start;
				array.ranges[i].end = end;
			}
		}

		pub fn remove(arg_array: *@This(), arg_start: T, arg_end: T) !void {
			var array = arg_array;
			var start = arg_start;
			var end = arg_end;
			var i: usize = 0;
			while ((i < array.ranges.len) and (end >= array.ranges[i].start)) {
				if (start >= array.ranges[i].end) {
					i += 1;
				} else if (end <= array.ranges[i].start) {
					break;
				} else {
					if ((start <= array.ranges[i].start) and (end >= array.ranges[i].end)) {
						{
							var j: usize = i;
							while (j < (array.ranges.len - 1)) : (j += 1) {
								array.ranges[j] = array.ranges[j+1];
							}
						}
						array.ranges.len -= 1;
					} else if ((start > array.ranges[i].start) and (end < array.ranges[i].end)) {
						{
							var j: usize = array.ranges.len;
							while (j > (i + 1)) : (j -= 1) {
								array.ranges[j] = array.ranges[j-1];
							}
						}
						try array.ensureCapacity(array.ranges.len+1);
						array.ranges.len += 1;
						array.ranges[i+1].start = end;
						array.ranges[i+1].end = array.ranges[i].end;
						array.ranges[i].end = start;
						i += 1;
					} else if ((start <= array.ranges[i].start) and (end < array.ranges[i].end)) {
						array.ranges[i].start = end;
					} else if ((start > array.ranges[i].start) and (end >= array.ranges[i].end)) {
						array.ranges[i].end = start;
					}
				}
			}
		}

		pub fn split(arg_array: *@This(), arg_value: T) !void {
			var array = arg_array;
			var value = arg_value;
			var i: usize = 0;
			while ((i < array.ranges.len) and !((value >= array.ranges[i].start) and (value <= array.ranges[i].end))) {
				i += 1;
			}
			if (i < array.ranges.len) {
				if ((value > array.ranges[i].start) and (value < array.ranges[i].end)) {
					var new_range: Range = undefined;
					new_range.start = value;
					new_range.end = array.ranges[i].end;
					array.ranges[i].end = value;
					{
						var j: usize = array.ranges.len;
						while (j > (i + 1)) : (j -= 1) {
							array.ranges[j] = array.ranges[j-1];
						}
					}
					try array.ensureCapacity(array.ranges.len+1);
					array.ranges.len += 1;
					array.ranges[i+1] = new_range;
				} else if (value == array.ranges[i].start) {
					return;
				} else if (value == array.ranges[i].end) {
					return;
				}
			}
		}

		pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
			for(value.ranges) |range| {
				try writer.print("[{},{})", .{ range.start, range.end });
			}
		}
	};
}

fn RandomIndex(rand: std.rand.Random, arr: anytype) @TypeOf(arr[0]) {
	const d = rand.intRangeLessThan(usize, 0, arr.len);
	return arr[d];
}

test "Remove front of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(0, 10);
	try ranges.remove(0, 5);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=5, .end=10}, }, ranges.ranges);
}

test "Remove end of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(0, 10);
	try ranges.remove(5, 10);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=0, .end=5}, }, ranges.ranges);
}

test "Remove full range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(0, 10);
	try ranges.remove(0, 10);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{}, ranges.ranges);
}

test "Remove middle of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(0, 10);
	try ranges.remove(3, 7);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=0, .end=3}, RangeT{.start=7, .end=10}, }, ranges.ranges);
}

test "Add to front of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.add(0, 6);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=0, .end=10}, }, ranges.ranges);
}

test "Add touch front of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.add(0, 5);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=0, .end=5}, RangeT{.start=5, .end=10}, }, ranges.ranges);
}

test "Add to back of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.add(9, 15);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=5, .end=15}, }, ranges.ranges);
}

test "Add touch back of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.add(10, 15);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=5, .end=10}, RangeT{.start=10, .end=15}, }, ranges.ranges);
}

test "Add in range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.add(6, 9);
	try ranges.add(5, 9);
	try ranges.add(6, 10);
	try ranges.add(5, 10);
	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=5, .end=10} }, ranges.ranges);
}

test "Add out range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.add(0, 15);
	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=0, .end=15} }, ranges.ranges);
}

test "Slice out range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.split(0);
	try ranges.split(15);
	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=5, .end=10} }, ranges.ranges);
}

test "Slice front of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.split(5);
	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=5, .end=10} }, ranges.ranges);
}

test "Slice back of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.split(10);
	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=5, .end=10} }, ranges.ranges);
}


test "Slice middle of range" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(5, 10);
	try ranges.split(7);
	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=5, .end=7}, RangeT{.start=7, .end=10} }, ranges.ranges);
}

test "Add inbetween" {
	//Yes this was broken at one point
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(1, 2);
	try ranges.add(5, 6);

	try ranges.add(3, 4);

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ 
		RangeT{.start=1, .end=2},
		RangeT{.start=3, .end=4},
		RangeT{.start=5, .end=6}
	}, ranges.ranges);
}

test "Merge Test" {
	var allocator = std.testing.allocator;

	const RangeArrayT = RangeArray(usize);
	const RangeT = RangeArrayT.Range;
	var ranges = try RangeArrayT.init(allocator, 0);
	defer ranges.deinit();
	try ranges.add(0, 100);
	for(1..10) |i| {
		try ranges.split(i*10);
	}
	try ranges.merge();

	try std.testing.expectEqualSlices(RangeT, &[_]RangeT{ RangeT{.start=0, .end=100}, }, ranges.ranges);
}

// test "Downloaded Blocks" {
// 	var allocator = std.testing.allocator;

// 	var prng = std.rand.DefaultPrng.init(blk: {
// 		var longSeed: u128 = @intCast(std.time.nanoTimestamp());
// 		var seed: u64 = @as(u64, @intCast(longSeed >> 64)) | @as(u64, @intCast(longSeed & 0xFFFFFFFFFFFFFFFF));
// 		try std.os.getrandom(std.mem.asBytes(&seed));
// 		break :blk seed;
// 	});
// 	const rand = prng.random();
	
// 	const TORRENT_SIZE = 1111;
// 	const TORRENT_PIECE_SIZE = 203;
// 	const TORRENT_PIECE_COUNT = @divTrunc(TORRENT_SIZE+TORRENT_PIECE_SIZE-1, TORRENT_PIECE_SIZE);
// 	const MAX_BLOCK_LENGTH = 20;
	
// 	var notDownloaded = try RangeArray(usize).init(allocator, TORRENT_PIECE_COUNT);
// 	defer notDownloaded.deinit();
// 	try notDownloaded.add(0, TORRENT_SIZE);
// 	for(0..TORRENT_PIECE_COUNT) |i| {
// 		try notDownloaded.split(i*TORRENT_PIECE_SIZE);
// 	}

// 	while(true) {
// 		var piece_range = RandomIndex(rand, notDownloaded.ranges);
// 		var block_range = if(piece_range.end - piece_range.start > MAX_BLOCK_LENGTH) blk:{
// 			break :blk @TypeOf(piece_range){
// 				.start = piece_range.start,
// 				.end = piece_range.start + MAX_BLOCK_LENGTH,
// 			};
// 		} else piece_range;
// 		var sum1: u64 = 0;
// 		for(notDownloaded.ranges) |range| {
// 			sum1 += range.end - range.start + 1;
// 		}
// 		try notDownloaded.remove(block_range.start, block_range.end);

// 		var sum2: u64 = 0;
// 		for(notDownloaded.ranges) |range| {
// 			sum2 += range.end - range.start + 1;
// 		}
// 		var percent: f32 = 100.0 - (@as(f32, @floatFromInt(sum2)) / TORRENT_SIZE) * 100.0;
// 		std.debug.print("({}/{}) {d:0>.2}%\n", .{sum2, TORRENT_SIZE, percent});

// 		if(sum1 == sum2) {
// 			std.debug.print("block: {}\n", .{block_range});
// 			std.debug.print("pieces: {any}\n\n", .{notDownloaded.ranges});
// 			break;
// 		}
// 		if(sum2 == 0) break;
// 	}
// }

// pub fn main() !void {
//     var gp = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
//     defer _ = gp.deinit();
//     const allocator = gp.allocator();

//     var ranged_array = try RangedArray.init(allocator, 5);
// 	defer ranged_array.deinit();
//     try ranged_array.add_range(5, 12);
//     try ranged_array.add_range(15, 20);
//     try ranged_array.add_range(25, 30);
//     std.debug.print("Original List:\n", .{});
//     for (0..ranged_array.ranges.len) |i| {
// 		std.debug.print("[{d}, {d}]\n", .{ranged_array.ranges[i].start, ranged_array.ranges[i].end});
// 	}
//     ranged_array.split_node_at_value(20);
//     std.debug.print("\nAfter Splitting at 20:\n", .{});
// 	for (0..ranged_array.ranges.len) |i| {
// 		std.debug.print("[{d}, {d}]\n", .{ranged_array.ranges[i].start, ranged_array.ranges[i].end});
// 	}
// }