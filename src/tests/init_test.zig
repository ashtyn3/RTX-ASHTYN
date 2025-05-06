const std = @import("std");
const Clock = @import("../clock.zig").Clock;
const Device = @import("../device.zig").Device;

test "deviceInit" {
    var allocator = std.testing.allocator;
    const clock = try allocator.create(Clock);
    clock.* = .{ .bus = try .init(allocator) };
    const dev = try Device.init(allocator, clock);

    defer allocator.destroy(dev);
    defer dev.destroy();

    dev.setSignal();
    const prog = std.ArrayList(u8).init(allocator);
    dev.kernel.prog = prog.items;

    dev.clock.tick();
    dev.setThreads(1);
    dev.clock.tick();

    dev.clock.tick();
    dev.killSignal();
    dev.clock.tick();

    try std.testing.expectEqual(dev.signal.get(), 0);
}
