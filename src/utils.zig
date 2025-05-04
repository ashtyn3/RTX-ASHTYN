const std = @import("std");

pub fn toBytes(comptime t: type, s: *const t) []const u8 {
    return @as([*]const u8, @ptrCast(s))[0..@sizeOf(t)];
}

pub fn fromBytes(comptime t: type, bytes: []const u8) t {
    return std.mem.bytesToValue(t, bytes);
}
