const std = @import("std");
const Clock = @import("clock.zig").Clock;
const Bus = @import("bus.zig").Bus;
const SM = @import("SM.zig").SM;
const Cluster = @import("cluster.zig").Cluster;
const GlobalMemory = @import("memory.zig").GlobalMemory;
const RegFile = @import("registers.zig").RegisterFile;
const Thread = @import("thread.zig").Thread;
const Kernel = @import("kernel.zig").Kernel;
const KernelTracker = @import("viz/ins.zig").KernelTracker;
const MemOptim = @import("mem_optim.zig").MemoryOptimizer;
const constants = @import("constants.zig").constants;

clock: *Clock,
signal: *Bus(u1, 1),
thread_size: *Bus(u8, 1),
allocator: std.mem.Allocator,
SMs: std.ArrayList(*SM),
returned: *Bus(u8, 1),
kernel: *Kernel,
thread_count: u64,
global_memory: *GlobalMemory,
kernel_tracker: ?KernelTracker,

const Self = @This();

pub fn init(a: std.mem.Allocator, clock: *Clock) !*Self {
    const s = try a.create(Self);
    const k = try a.create(Kernel);
    const gmem = try GlobalMemory.init(a, clock);

    const sms = std.ArrayList(*SM).init(a);
    s.* = .{
        .clock = clock,
        .signal = try .init(a),
        .thread_size = try .init(a),
        .allocator = a,
        .SMs = sms,
        .kernel = k,
        .thread_count = 0,
        .returned = try .init(a),
        .global_memory = gmem,
        .kernel_tracker = null,
    };
    if (constants.viz == 1) {
        s.kernel_tracker = try KernelTracker.init(a);
    }
    return s;
}

pub fn launch(self: *Self, id: u64) !void {
    const sm = self.allocator.create(SM) catch {
        @panic("Failed to create root SM");
    };

    const regfile = RegFile.init(self.allocator) catch {
        @panic("Failed to launch reguister files");
    };
    var cls = std.ArrayList(*Cluster).init(self.allocator);
    for (0..constants.sm_size) |i| {
        const c = self.allocator.create(Cluster) catch {
            @panic("Failed to launch clusters");
        };
        c.* = Cluster{
            .id = i,
            .done = Bus(u8, 1).init(self.allocator) catch {
                @panic("bad cluster state");
            },
            .pc = Bus(u64, 1).init(self.allocator) catch {
                @panic("bad pc state");
            },
            .threads = std.ArrayList(*Thread).init(self.allocator),
            .signal = Bus(u1, 1).init(self.allocator) catch {
                @panic("bad cluster signal state");
            },
            .wait = Bus(struct { u64, u64 }, 33).init(self.allocator) catch {
                @panic("bad wait signal state");
            },
        };
        cls.append(c) catch {
            @panic("failed cls");
        };
    }
    sm.* = .{
        .id = id,
        .clusters = try cls.toOwnedSlice(),
        .device = self,
        .global_memory_controller = self.global_memory,
        .register_file = regfile,
        .state = .Ready,
        .tracker = null,
        .mem = undefined,
    };
    sm.mem = try MemOptim.init(self.allocator, self.global_memory, sm);
    if (constants.viz == 1) {
        sm.tracker = self.kernel_tracker;
    }

    self.SMs.append(sm) catch {
        @panic("failed new SM");
    };
    // sm.scheduler();
}
pub fn destroy(self: *Self) void {
    self.allocator.destroy(self.clock.bus);
    self.allocator.destroy(self.clock);
    self.allocator.destroy(self.kernel);
    self.allocator.destroy(self.returned);
    self.allocator.destroy(self.signal);
    self.allocator.destroy(self.thread_size);
    self.global_memory.destroy();
    self.allocator.destroy(self.global_memory);
    for (self.SMs.items) |s| {
        s.destroy();
        // self.allocator.destroy(s.global_memory_controller);
        // self.allocator.destroy(s.register_file);
    }
    self.SMs.deinit();
}

pub fn setSignal(self: *Self) void {
    self.signal.put(1);
}

pub fn killSignal(self: *Self) void {
    while (!self.clock.cycle()) {}
    self.signal.put(0);
}

pub fn setThreads(self: *Self, size: u8) void {
    while (!self.clock.cycle()) {}
    self.thread_size.put(size);
}

pub fn resetThreads(self: *Self) void {
    while (!self.clock.cycle()) {}
    self.thread_size.put(0);
}
pub fn debug(self: *Self) void {
    std.log.info("SM_count={any}, thread_size={any} thread_count={any}", .{ self.SMs.items.len, self.thread_size.get(), self.thread_size.get() * self.SMs.items.len * self.SMs.items[0].clusters.len });
}

pub const Device = Self;
