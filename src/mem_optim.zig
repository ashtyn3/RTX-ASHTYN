const std = @import("std");

const constants = @import("constants.zig").constants;
const memory = @import("memory.zig");
const SM = @import("SM.zig").SM;

pub const Request = struct {
    pub const Type = enum { write, read };
    pub const Data = union(Type) { write: memory.WriteRecieve, read: memory.ReadRecieve };

    type: Type,
    data: Data,
};
pub const CacheLine = struct {
    tag: u49,
    data: [128]u8,
    valid: u1,
};
pub const Cache = struct {
    lines: std.BoundedArray(CacheLine, 256),
    global: *memory.GlobalMemory,

    pub fn init(a: std.mem.Allocator, g: *memory.GlobalMemory) !*Cache {
        var s = try a.create(Cache);
        s.lines = std.BoundedArray(CacheLine, 256){};
        s.global = g;
        return s;
    }
    pub fn has(c: *Cache, address: u64) bool {
        const offset_bits = 7; // log2(128)
        const index_bits = 8; // log2(256)
        // const offset_mask = (1 << offset_bits) - 1;
        const index_mask = (1 << index_bits) - 1;

        // const offset = address & offset_mask;
        const index = (address >> offset_bits) & index_mask;
        const tag = address >> (offset_bits + index_bits);

        const line = c.lines.get(index);
        if (line.tag == tag) {
            return true;
        }
        return false;
    }
    pub fn access(c: *Cache, ctx_c: u64, ctx_t: u64, pc: u64, address: u64, n: u8) struct { u1, []u8 } {
        const offset_bits = 7; // log2(128)
        const index_bits = 8; // log2(256)
        const offset_mask = (1 << offset_bits) - 1;
        const index_mask = (1 << index_bits) - 1;

        const offset = address & offset_mask;
        const index = (address >> offset_bits) & index_mask;
        const tag = address >> (offset_bits + index_bits);

        const line = c.lines.get(index);
        if (line.tag == tag) {
            return .{ 0, @constCast(line.data[offset..(offset + n)]) };
        }
        _ = c.global.read(memory.ReadRecieve{
            .address = address,
            .len = n,
            .cluster_id = ctx_c,
            .thread_id = ctx_t,
            .pc = pc,
        });
        // const data = c.global.read_sending_bus.Q[at];
        // c.lines.set(address, data);
        return .{ 1, &[_]u8{} };
    }
};
const Self = @This();

const Fifo = std.fifo.LinearFifo(Request, .{ .Static = constants.bus_max * 200 });
requests: Fifo,
global: *memory.GlobalMemory,
L1: *Cache,
SM_ctx: *SM,

pub fn init(a: std.mem.Allocator, g: *memory.GlobalMemory, sm: *SM) !*Self {
    var s = try a.create(Self);
    s.L1 = try Cache.init(a, g);
    s.SM_ctx = sm;
    s.global = g;
    s.requests = Fifo.init();
    return s;
}

pub fn proc(self: *Self) void {
    while (self.requests.count != 0) {
        const item = self.requests.readItem();
        if (item) |i| {
            if (i.type == .read) {
                _ = self.L1.access(i.data.read.cluster_id, i.data.read.thread_id, i.data.read.pc, i.data.read.address, i.data.read.len);
            } else {
                _ = self.global.send_write(i.data.write);
            }
        }
    }

    var req_map = std.AutoHashMap(u64, struct { u64, u64 }).init(self.SM_ctx.device.allocator);
    for (self.SM_ctx.clusters) |c| {
        for (0..c.wait.active + 1) |_| {
            const item = c.wait.get();
            const thread = item.@"0";
            const addr = item.@"1";
            req_map.put(thread, .{ c.id, addr }) catch {
                @panic("broken request pipe");
            };
        }
    }

    for (0..self.global.read_sending_bus.active + 1) |i| {
        if (req_map.get(self.global.read_sending_bus.Q[i].thread_id)) |v| {
            _ = self.SM_ctx.clusters[v.@"0"].wait.get();
        }
    }
}

pub fn write(self: *Self, r: Request) void {
    self.requests.writeItem(r) catch {
        @panic("broken write");
    };
}
pub fn read(self: *Self, r: Request) ?[]u8 {
    if (self.L1.has(r.data.read.address)) {
        return self.L1.access(r.data.read.cluster_id, r.data.read.thread_id, r.data.read.pc, r.data.read.address, r.data.read.len).@"1";
    }
    self.requests.writeItem(r) catch {
        @panic("broken write");
    };
    return null;
}
pub const MemoryOptimizer = Self;
