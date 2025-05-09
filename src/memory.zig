const std = @import("std");
const Bus = @import("bus.zig").Bus;
const Clock = @import("clock.zig").Clock;
const constants = @import("constants.zig").constants;
const assert = std.debug.assert;

pub const WriteRecieve = struct {
    address: u64,
    thread_id: u64,
    cluster_id: u64,
    pc: u64,
    data: []const u8,
};
pub const ReadRecieve = struct {
    address: u64,
    len: u8,
    thread_id: u64,
    cluster_id: u64,
    pc: u64,
};
pub const ReadSend = struct {
    data: []u8,
    pc: u64,
    thread_id: u64,
    cluster_id: u64,
    start: u64,
    len: u8,
};
clock: *Clock,

contigous: [constants.shared_mem_len]u8,

allocator: std.mem.Allocator,

const Self = @This();

pub fn init(a: std.mem.Allocator, clock: *Clock) !*Self {
    const s = try a.create(Self);
    s.* = .{
        .clock = clock,
        .contigous = std.mem.zeroes([constants.shared_mem_len]u8),
        .allocator = a,
    };
    return s;
}

pub fn send_write(self: *Self, recv: WriteRecieve) void {
    if (recv.data.len != 0) {
        // assert(recv.data.len >= 32);
        const width = recv.address + recv.data.len;
        assert(width <= self.contigous.len);
        @memcpy(self.contigous[recv.address..width], recv.data[0..recv.data.len]);
    }
}

pub fn read(self: *Self, r: ReadRecieve) u32 {
    const request_id = self.read_recieving_bus.active;
    self.read_recieving_bus.put(r);
    return request_id;
}
pub fn real_read(self: *Self, r: ReadRecieve) ReadSend {
    return ReadSend{
        .start = r.address,
        .pc = r.pc,
        .thread_id = r.thread_id,
        .cluster_id = r.cluster_id,
        .len = r.len,
        .data = self.contigous[r.address..(r.address + r.len)],
    };
}
pub fn debug(self: *Self) void {
    var stdout = std.io.getStdOut().writer();
    for (self.contigous, 0..) |value, idx| {
        if (value != 0) {
            stdout.print("0x{x:0>8} ({0}): {1}\n", .{ idx, value }) catch {
                @panic("failed debug");
            };
        }
    }
}

pub const GlobalMemory = Self;
