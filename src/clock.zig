const Bus = @import("bus.zig").Bus;
const std = @import("std");
const log = std.log.scoped(.Clock);
const constants = @import("constants.zig").constants;

bus: *Bus(u1, 1),
const Self = @This();

pub fn tick(self: *Self) void {
    std.Thread.sleep(if (constants.slow_clock == 1) std.time.ns_per_ms else 1);
    if (self.bus.get() == 0) {
        self.bus.put(1);
        return;
    }
    self.bus.put(0);
    return;
}

pub fn cycle(self: *Self) bool {
    return self.bus.get() == 1;
}

pub fn debug(self: *Self) void {
    log.info("bit={any} signal={s}", .{ self.bus.Q[0], if (self.bus.Q[0] == 1) "high" else "low" });
}

pub const Clock = Self;
