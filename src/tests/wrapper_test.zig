const std = @import("std");
const ALU = @import("../ALU.zig");

test "wrap" {
    const wrap_one = ALU.wrap(.u64, @constCast(&[_]u8{ 1, 0, 0, 0, 0, 0, 0, 0 }));
    try std.testing.expectEqual(1, wrap_one.value.u64);
}

test "unwrap" {
    const bit_one = &[_]u8{ 1, 0, 0, 0, 0, 0, 0, 0 };
    const wrap_one = ALU.wrap(.u64, @constCast(bit_one));

    var buffer = try std.testing.allocator.alloc(u8, 8);
    defer std.testing.allocator.free(buffer);
    wrap_one.unwrap(&buffer);

    try std.testing.expectEqualSlices(u8, buffer, bit_one);
}

test "wrapped_add" {
    const bit_one = &[_]u8{ 1, 0, 0, 0, 0, 0, 0, 0 };
    const n1 = ALU.wrap(.u64, @constCast(bit_one));
    const n2 = ALU.wrap(.u64, @constCast(bit_one));
    const v = n1.add(n2);
    try std.testing.expectEqual(2, v.value.u64);
    // TODO test floats
}
