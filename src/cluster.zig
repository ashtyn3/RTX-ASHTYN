const std = @import("std");
const Bus = @import("bus.zig").Bus;
const Thread = @import("thread.zig").Thread;

threads: std.ArrayList(*Thread),
id: u64,
pc: *Bus(u64, 1),
done: *Bus(u8, 1),
signal: *Bus(u1, 1),
wait: *Bus(struct { u64, u64 }, 32),

const Self = @This();

pub fn sync(self: *Self) void {
    if (self.wait.active == 0) {
        self.done.put(0);
        for (self.threads.items) |t| {
            if (t.done.get() == 1) {
                self.done.put(self.done.get() + 1);
            }
        }
    }
}

pub const Cluster = Self;
