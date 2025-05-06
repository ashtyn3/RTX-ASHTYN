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
    start: u64,
    len: u8,
};
clock: *Clock,

contigous: [constants.shared_mem_len]u8,

read_recieving_bus: *Bus(ReadRecieve, constants.bus_max),
read_sending_bus: *Bus(ReadSend, constants.bus_max),

write_recieving_bus: *Bus(WriteRecieve, constants.bus_max),
allocator: std.mem.Allocator,

const Self = @This();

pub fn init(a: std.mem.Allocator, clock: *Clock) !*Self {
    const s = try a.create(Self);
    s.* = .{
        .clock = clock,
        .contigous = std.mem.zeroes([constants.shared_mem_len]u8),
        .read_recieving_bus = try .init(a),
        .read_sending_bus = try .init(a),
        .write_recieving_bus = try .init(a),
        .allocator = a,
    };
    return s;
}

pub fn destroy(self: *Self) void {
    self.allocator.destroy(self.read_recieving_bus);
    self.allocator.destroy(self.read_sending_bus);
    self.allocator.destroy(self.write_recieving_bus);
}

pub fn recieve_writes(self: *Self) void {
    for (self.write_recieving_bus.sink()) |recv| {
        if (recv.data.len != 0) {
            assert(recv.data.len <= 32);
            const width = recv.address + recv.data.len;
            assert(width <= self.contigous.len);
            @memcpy(self.contigous[recv.address..width], recv.data[0..recv.data.len]);
        }
    }
}

pub fn send_write(self: *Self, w: WriteRecieve) void {
    self.write_recieving_bus.put(w);
}

pub fn read(self: *Self, r: ReadRecieve) u32 {
    const request_id = self.read_recieving_bus.active;
    self.read_recieving_bus.put(r);
    return request_id;
}
pub fn complete_reads(self: *Self) void {
    for (self.read_recieving_bus.sink()) |recv| {
        if (recv.len != 0) {
            self.read_sending_bus.put(.{
                .start = recv.address,
                .pc = recv.pc,
                .thread_id = recv.thread_id,
                .len = recv.len,
                .data = self.contigous[recv.address..recv.len],
            });
        }
    }
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
