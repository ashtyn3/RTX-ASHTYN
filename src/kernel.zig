const std = @import("std");
const constants = @import("constants.zig").constants;
const assert = std.debug.assert;
prog: []const u8,

const Self = @This();

pub fn at(self: *Self, pc: u64) []u8 {
    assert((pc * 16 + 16) <= constants.max_program_len and pc >= 0);

    if ((pc * 16 + 16) > self.prog.len) {
        return &[_]u8{};
    }
    return @constCast(self.prog[(pc * 16)..(pc * 16 + 16)]);
}

pub const Kernel = Self;
