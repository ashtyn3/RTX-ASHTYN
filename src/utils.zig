pub fn toBytes(comptime t: type, s: *const t) []const u8 {
    return @as([*]const u8, @ptrCast(s))[0..@sizeOf(t)];
}
