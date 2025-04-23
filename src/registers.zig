const std = @import("std");
const assert = std.debug.assert;
const constants = @import("constants.zig").constants;

registers: [constants.max_register_count][4]u8,

const Self = @This();

pub fn init(a: std.mem.Allocator) !*Self {
    const s = try a.create(Self);
    s.* = .{
        .registers = std.mem.zeroes([constants.max_register_count][4]u8),
    };
    return s;
}

pub fn rname(comptime name: @Type(.enum_literal)) u64 {
    const tag_name = @tagName(name);
    if (std.mem.startsWith(u8, tag_name, "r")) {
        const id = tag_name[1..];
        return std.fmt.parseInt(u64, id, 10) catch {
            @panic("failed to parse register name");
        };
    } else {
        unreachable;
    }
    return 0;
}

pub fn set(self: *Self, place: u64, data: []const u8) void {
    assert(place <= constants.max_register_count);
    assert(data.len <= 4);

    @memcpy(self.registers[place][0..data.len], data);
}

pub fn get(self: *Self, place: u64) [4]u8 {
    assert(place <= constants.max_register_count);
    return self.registers[place];
}

pub fn debug(self: *Self) void {
    for (0..constants.max_register_count) |i| {
        std.log.info("r{any}={any}", .{ i, self.get(i) });
    }
}

pub const RegisterFile = Self;
