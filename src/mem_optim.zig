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
    // valid: u1,
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

        if (index >= c.lines.len) {
            return false;
        }
        const line = c.lines.get(index);
        if (line.tag == tag) {
            return true;
        }
        return false;
    }
    pub fn write(c: *Cache, address: u64, data: []u8) void {
        const offset_bits = 7; // log2(128)
        const index_bits = 8; // log2(256)
        const offset_mask = (1 << offset_bits) - 1;
        // const index_mask = (1 << index_bits) - 1;

        const offset = address & offset_mask;
        // const index = (address >> offset_bits) & index_mask;
        const tag = address >> (offset_bits + index_bits);
        var buf = [_]u8{0} ** 128;
        @memcpy(buf[offset..(offset + data.len)].ptr, data[0..data.len]);
        // std.log.debug("{any}", .{data});
        c.lines.append(.{ .tag = @intCast(tag), .data = buf }) catch {
            @panic("failed to write cache line");
        };
    }

    pub fn access(c: *Cache, ctx_c: u64, ctx_t: u64, pc: u64, address: u64, n: u8) []u8 {
        // std.log.debug("here", .{});
        const offset_bits = 7; // log2(128)
        const index_bits = 8; // log2(256)
        const offset_mask = (1 << offset_bits) - 1;
        const index_mask = (1 << index_bits) - 1;

        const offset = address & offset_mask;
        const index = (address >> offset_bits) & index_mask;
        const tag = address >> (offset_bits + index_bits);

        // if (index >= c.lines.len) {
        // return .{ 1, &[_]u8{} };
        // }
        if (index < c.lines.len) {
            const line = c.lines.get(index);
            if (line.tag == tag) {
                return @constCast(line.data[offset..(offset + n)]);
            }
            return &[_]u8{};
        }
        const r = c.global.real_read(memory.ReadRecieve{
            .address = address,
            .len = n,
            .cluster_id = ctx_c,
            .thread_id = ctx_t,
            .pc = pc,
        });
        c.write(r.start, r.data);

        const line = c.lines.get(index);

        return @constCast(line.data[offset..(offset + n)]);
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
    for (0..10) |_| {
        const req = self.requests.readItem();
        if (req) |r| {
            if (r.type == .read) {
                _ = self.L1.access(r.data.read.cluster_id, r.data.read.thread_id, r.data.read.pc, r.data.read.address, r.data.read.len);
                self.SM_ctx.clusters[r.data.read.cluster_id].wait.active = 0;
            }
            if (r.type == .write) {
                self.global.send_write(r.data.write);
            }
        }
    }
}

pub fn write(self: *Self, r: Request) void {
    self.requests.writeItem(r) catch {
        @panic("broken write");
    };
}
pub fn read(self: *Self, r: Request, buf: *[]u8) ?[]u8 {
    if (self.L1.has(r.data.read.address)) {
        const data = self.L1.access(r.data.read.cluster_id, r.data.read.thread_id, r.data.read.pc, r.data.read.address, r.data.read.len);
        @memcpy(buf.ptr, data);
        return @constCast(data);
    }

    self.requests.writeItem(r) catch {
        @panic("broken write");
    };
    return null;
}
pub const MemoryOptimizer = Self;
