const std = @import("std");
const Clock = @import("../clock.zig").Clock;
const Device = @import("../device.zig").Device;
const SM = @import("../SM.zig").SM;

test "SMInit" {
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

    for (0..20) |i| {
        try dev.launch(i);
        try dev.SMs.items[i].launch_threads();
    }
    try std.testing.expectEqual(dev.SMs.items.len, 20);
}

test "SMEmptySchedule" {
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

    for (0..20) |i| {
        try dev.launch(i);
        try dev.SMs.items[i].launch_threads();
    }
    for (0..20) |i| {
        const ts = try std.Thread.spawn(.{}, SM.scheduler, .{dev.SMs.items[i]});
        ts.detach();
    }
    while (dev.signal.get() == 1) {
        if (dev.returned.get() == 20) {
            dev.signal.put(0);
        }
    }
    dev.debug();
}
