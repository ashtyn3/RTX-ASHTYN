const std = @import("std");
const ALU = @import("../ALU.zig");
const core = @import("../core.zig");
const utils = @import("../utils.zig");

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
    // const bit_one = &[_]u8{ 1, 0, 0, 0, 0, 0, 0, 0 };
    // const n1 = ALU.wrap(.u64, @constCast(bit_one));
    // const n2 = ALU.wrap(.u64, @constCast(bit_one));
    // const v = n1.add(n2);
    // try std.testing.expectEqual(2, v.value.u64);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    inline for (@typeInfo(core.DataType).@"enum".fields) |f| {
        if (f.name[0] == 'f') {
            const n1 = rand.float(@FieldType(ALU.Value, f.name));
            const n2 = rand.float(@FieldType(ALU.Value, f.name));
            const real_sum = n1 + n2;
            var n1_slice = [_]u8{0} ** @sizeOf(@FieldType(ALU.Value, f.name));
            var n2_slice = [_]u8{0} ** @sizeOf(@FieldType(ALU.Value, f.name));

            // var sum_slice = [_]u8{0} ** @sizeOf(@FieldType(ALU.Value, f.name));

            if (n1_slice.len == 4) {
                std.mem.writeInt(u32, &n1_slice, @as(u32, @bitCast(n1)), .little);
                std.mem.writeInt(u32, &n2_slice, @as(u32, @bitCast(n2)), .little);
                // std.mem.writeInt(u32, &sum_slice, @as(u32, @bitCast(real_sum)), .little);
            }
            if (n1_slice.len == 8) {
                std.mem.writeInt(u64, &n1_slice, @as(u64, @bitCast(n1)), .little);
                std.mem.writeInt(u64, &n2_slice, @as(u64, @bitCast(n2)), .little);
                // std.mem.writeInt(u64, &sum_slice, @as(u64, @bitCast(real_sum)), .little);
            }
            const n1_wrapped = ALU.wrap(@field(core.DataType, f.name), &n1_slice);
            const n2_wrapped = ALU.wrap(@field(core.DataType, f.name), &n2_slice);
            const sum_wrapped = n1_wrapped.add(n2_wrapped);
            const sum_v = @field(sum_wrapped.value, f.name);
            try std.testing.expectEqual(real_sum, sum_v);
        } else if (!std.mem.eql(u8, f.name, "none")) {
            const t = @FieldType(ALU.Value, f.name);
            const n1 = rand.intRangeLessThan(t, 1, std.math.maxInt(t) / 2);
            const n2 = rand.intRangeLessThan(t, 1, std.math.maxInt(t) / 2);
            const real_sum = n1 + n2;
            var n1_slice = [_]u8{0} ** @sizeOf(@FieldType(ALU.Value, f.name));
            var n2_slice = [_]u8{0} ** @sizeOf(@FieldType(ALU.Value, f.name));
            if (n1_slice.len % 2 == 0) {
                std.mem.writeInt(@FieldType(ALU.Value, f.name), &n1_slice, @as(@FieldType(ALU.Value, f.name), n1), .little);
                std.mem.writeInt(@FieldType(ALU.Value, f.name), &n2_slice, @as(@FieldType(ALU.Value, f.name), n2), .little);
                const n1_wrapped = ALU.wrap(@field(core.DataType, f.name), &n1_slice);
                const n2_wrapped = ALU.wrap(@field(core.DataType, f.name), &n2_slice);
                const sum_wrapped = n1_wrapped.add(n2_wrapped);
                const sum_v = @field(sum_wrapped.value, f.name);
                try std.testing.expectEqual(real_sum, sum_v);
            }
        }
    }
}
