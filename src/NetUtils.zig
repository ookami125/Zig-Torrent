const std = @import("std");

pub fn bytesAvailable(stream: std.os.socket_t) !bool {
	var poll_fd = std.mem.zeroes([1]std.os.pollfd);
	poll_fd[0].fd = stream;
	poll_fd[0].events = std.os.POLL.IN;
	const ready = try std.os.poll(&poll_fd, 1);
	if(ready == 0) return false;
	return (poll_fd[0].revents & std.os.POLL.IN != 0x0);
}