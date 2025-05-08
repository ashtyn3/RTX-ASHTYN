const std = @import("std");
const Clock = @import("clock.zig").Clock;
const RegFile = @import("registers.zig").RegisterFile;
const GlobalMemory = @import("memory.zig").GlobalMemory;
const Cluster = @import("cluster.zig").Cluster;
const Core = @import("core.zig").Core;
const Bus = @import("bus.zig").Bus;
const KernelTracker = @import("viz/ins.zig");

registers: *RegFile,
reg_max: u64,
reg_min: u64,
cluster: *Cluster,
core: Core,
id: u64,
done: *Bus(u1, 1),
tracker: ?*KernelTracker,

const Self = @This();

pub fn task(self: *Self) void {
    self.core.exec() catch {
        @panic("Bad kernel");
    };
}

pub const Thread = Self;
