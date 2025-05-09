const std = @import("std");

const Cluster = @import("cluster.zig").Cluster;
const constants = @import("constants.zig").constants;
const Core = @import("core.zig").Core;
const Device = @import("device.zig").Device;
const GlobalMemory = @import("memory.zig").GlobalMemory;
const RegFile = @import("registers.zig").RegisterFile;
const Thread = @import("thread.zig").Thread;
const KernelTracker = @import("viz/ins.zig").KernelTracker;
const MemOptim = @import("mem_optim.zig").MemoryOptimizer;

const SMState = enum {
    Active,
    Ready,
    NOP,
};

const Self = @This();
id: u64,
register_file: *RegFile,
state: SMState,
clusters: []*Cluster,
global_memory_controller: *GlobalMemory,
device: *Device,
tracker: ?KernelTracker,
mem: *MemOptim,

pub fn launch_threads(self: *Self) !void {
    for (self.clusters) |c| {
        for (0..self.device.thread_size.get()) |i| {
            var t = try self.device.allocator.create(Thread);
            t.cluster = c;
            t.core = Core{
                .cluster_ctx = c,
                .kernel = self.device.kernel,
                .register_file = self.register_file,
                .thread_ctx = t,
                .SM_ctx = self,
                .last_pc = try .init(self.device.allocator),
            };
            t.core.last_pc.put(-1);
            t.id = self.device.thread_count;
            t.reg_min = i * 10;
            t.reg_max = (i * 10) + 9;
            t.registers = self.register_file;
            t.done = try .init(self.device.allocator);
            try c.threads.append(t);
            self.device.thread_count += 1;
        }
    }
}

pub fn destroy(self: *Self) void {
    self.device.allocator.destroy(self.register_file);
    for (self.clusters) |c| {
        for (c.threads.items) |t| {
            self.device.allocator.destroy(t.done);
            t.core.destroy();
            self.device.allocator.destroy(t);
        }
        c.threads.deinit();
        self.device.allocator.destroy(c.done);
        self.device.allocator.destroy(c.pc);
        self.device.allocator.destroy(c.signal);
        self.device.allocator.destroy(c);
    }
    self.device.allocator.free(self.clusters);
    self.device.allocator.destroy(self);
}

pub fn tasker(self: *Self) !void {
    if (self.device.signal.get() == 1) {
        var pool: std.Thread.Pool = undefined;
        try pool.init(std.Thread.Pool.Options{
            .allocator = self.device.allocator,
            .n_jobs = self.clusters.len * self.clusters[0].threads.items.len, // Number of worker threads
        });
        defer pool.deinit();
        var wg = std.Thread.WaitGroup{};

        if (self.device.clock.cycle()) {
            for (self.clusters) |cluster| {
                for (cluster.threads.items) |t| {
                    if (t.done.get() != 1) {
                        pool.spawnWg(&wg, Thread.task, .{t});
                        // tt.join();
                    }
                }
            }
        }
        wg.wait();
    }
}

pub fn scheduler(self: *Self) !void {
    while (self.device.signal.get() == 1) {
        if (self.device.clock.cycle()) {
            // const tt = try std.Thread.spawn(.{}, Self.tasker, .{self});
            // tt.detach();
            // const tw = try std.Thread.spawn(.{}, GlobalMemory.recieve_writes, .{self.global_memory_controller});
            // const tr = try std.Thread.spawn(.{}, GlobalMemory.complete_reads, .{self.global_memory_controller});
            // tw.join();
            // tr.join();
            try self.tasker();
            const pr = try std.Thread.spawn(.{}, MemOptim.proc, .{self.mem});
            pr.join();

            var done: u8 = 0;
            for (self.clusters) |cluster| {
                cluster.sync();
                if (cluster.wait.active != 0) {
                    continue;
                }
                const pc = cluster.pc.get();
                if (cluster.threads.items.len == cluster.done.get()) {
                    if (cluster.threads.items[0].core.kernel.at(pc).len != 0) {
                        cluster.pc.put(pc + 1);
                        for (self.clusters) |c| {
                            for (c.threads.items) |t| {
                                t.done.put(0);
                            }
                        }
                    } else {
                        done += 1;
                    }
                }
            }
            if (self.clusters.len == done) {
                self.device.returned.put(self.device.returned.get() + 1);
                break;
            }
        }
        self.device.clock.tick();
    }
}

pub fn store_memory(self: *Self, ctx_cluster_id: u64, ctx_thread_id: u64, ctx_pc: u64, addr: u64, data: []u8) void {
    self.mem.write(.{
        .type = .write,
        .data = .{
            .write = .{
                .thread_id = ctx_thread_id,
                .cluster_id = ctx_cluster_id,
                .pc = ctx_pc,
                .address = addr,
                .data = data,
            },
        },
    });
}
pub fn read_memory(self: *Self, ctx_cluster_id: u64, ctx_thread_id: u64, ctx_pc: u64, addr: u64, len: u8) void {
    self.mem.read(.{
        .type = .write,
        .data = .{
            .write = .{
                .thread_id = ctx_thread_id,
                .cluster_id = ctx_cluster_id,
                .pc = ctx_pc,
                .address = addr,
                .len = len,
            },
        },
    });
}
pub const SM = Self;
