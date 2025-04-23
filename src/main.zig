const std = @import("std");
const Bus = @import("bus.zig").Bus;
const Clock = @import("clock.zig").Clock;
const Device = @import("device.zig").Device;
const Memory = @import("memory.zig").GlobalMemory;
const SM = @import("SM.zig").SM;
const RegFile = @import("registers.zig").RegisterFile;
const Core = @import("core.zig").Core;
const constants = @import("constants.zig");

fn toBytes(comptime t: type, s: *const t) []const u8 {
    return @as([*]const u8, @ptrCast(s))[0..@sizeOf(t)];
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const clock = try allocator.create(Clock);
    clock.* = .{ .bus = try .init(allocator) };

    const dev = try Device.init(allocator, clock);
    dev.setSignal();

    var prog = std.ArrayList(u8).init(allocator);
    const in = Core.Instruction{
        .format = .MEM,
        .op = .st,
        .dtype = .i8,
        .dst = .{ .kind = .reg, .value = 6 },
        .src0 = .{ .kind = .none, .value = 0 },
        .src1 = .{ .kind = .none, .value = 0 },
        .literal = 90,
        .mod = .{},
        .flags = .{},
    };
    const in2 = Core.Instruction{
        .format = .MEM,
        .op = .st,
        .dtype = .i8,
        .dst = .{ .kind = .reg, .value = 1 },
        .src0 = .{ .kind = .none, .value = 0 },
        .src1 = .{ .kind = .none, .value = 0 },
        .literal = 250,
        .mod = .{},
        .flags = .{},
    };
    try prog.appendSlice(toBytes(Core.Instruction, &in));
    try prog.appendSlice(toBytes(Core.Instruction, &in2));
    // try prog.appendSlice(&[_]u8{ 24, 4, 192, 0, 128, 1, 128, 1, 0, 180, 0, 0, 0, 0, 0, 0 });
    // try prog.appendNTimes(0, 13);

    dev.kernel.prog = prog.items;

    dev.clock.tick();
    dev.setThreads(5);
    dev.clock.tick();

    for (0..constants.constants.sm_count) |i| {
        dev.launch(i);
        try dev.SMs.items[i].launch_threads();
    }

    for (0..constants.constants.sm_count) |i| {
        const ts = try std.Thread.spawn(.{}, SM.scheduler, .{dev.SMs.items[i]});
        ts.detach();
    }
    while (dev.signal.get() == 1) {
        if (dev.returned.get() == constants.constants.sm_count) {
            dev.signal.put(0);
        }
    }
    dev.debug();
    std.Thread.sleep(50);
    // dev.SMs.items[0].register_file.debug();
    // std.log.info("==========================", .{});
    // dev.SMs.items[1].register_file.debug();
    // dev.clock.debug();

    // const mem = try Memory.init(allocator, clock);
    //
    // mem.send_write(.{
    //     .address = 0,
    //     .cluster_id = 0,
    //     .data = &[_]u8{ 9, 9, 9, 9 },
    //     .pc = 0,
    //     .thread_id = 0,
    // });
    // mem.recieve_writes();
    //
    // const id = mem.read(.{ .address = 0, .len = 4 });
    // const id2 = mem.read(.{ .address = 0, .len = 2 });
    //
    // mem.read_complete();
    //
    // std.log.info("{any}", .{mem.read_sending_bus.Q[id]});
    // std.log.info("{any}", .{mem.read_sending_bus.Q[id2]});
    //
    // mem.read_recieving_bus.debug();
    //
    // while (dev.signal.get() == 1) {
    //     clock.tick();
    //     dev.killSignal();
    //     dev.clock.debug();
    // }

    // while (true) {
    //     clock.tick();
    //     if (clock.cycle()) {
    //         std.log.info("ticked", .{});
    //     }
    // }
}
