const std = @import("std");
const Bus = @import("bus.zig").Bus;
const Clock = @import("clock.zig").Clock;
const Device = @import("device.zig").Device;
const Memory = @import("memory.zig").GlobalMemory;
const SM = @import("SM.zig").SM;
const RegFile = @import("registers.zig").RegisterFile;
const Core = @import("core.zig").Core;
const constants = @import("constants.zig");
const serve = @import("viz/serve.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const clock = try allocator.create(Clock);
    clock.* = .{ .bus = try .init(allocator) };

    const dev = try Device.init(allocator, clock);
    dev.setSignal();

    var prog = std.ArrayList(u8).init(allocator);
    try prog.appendSlice((Core.Instruction{
        .format = .MEM,
        .op = .mov,
        .dtype = .u64,
        .dst = .{ .kind = .reg, .value = 1 },
        .src0 = .{ .kind = .sys_reg, .value = 0 },
        .src1 = .{ .kind = .none, .value = 0 },
        .literal = 0,
        .mod = .{},
        .flags = .{},
    }).toBytes());
    try prog.appendSlice((Core.Instruction{
        .format = .MEM,
        .op = .mov,
        .dtype = .u32,
        .dst = .{ .kind = .reg, .value = 3 },
        .src0 = .{ .kind = .none, .value = 0 },
        .src1 = .{ .kind = .none, .value = 0 },
        .literal = 4,
        .mod = .{},
        .flags = .{},
    }).toBytes());
    try prog.appendSlice((Core.Instruction{
        .format = .ALU,
        .op = .mul,
        .dtype = .u32,
        .dst = .{ .kind = .reg, .value = 5 },
        .src0 = .{ .kind = .reg, .value = 1 },
        .src1 = .{ .kind = .reg, .value = 3 },
        .literal = 0,
        .mod = .{},
        .flags = .{},
    }).toBytes());
    try prog.appendSlice((Core.Instruction{
        .format = .MEM,
        .op = .st,
        .dtype = .u32,
        .dst = .{ .kind = .reg, .value = 5 },
        .src0 = .{ .kind = .reg, .value = 1 },
        .src1 = .{ .kind = .none, .value = 0 },
        .literal = 0,
        .mod = .{},
        .flags = .{},
    }).toBytes());
    // try prog.appendSlice(&[_]u8{ 24, 4, 192, 0, 128, 1, 128, 1, 0, 180, 0, 0, 0, 0, 0, 0 });
    // try prog.appendNTimes(0, 13);

    dev.kernel.prog = prog.items;

    dev.clock.tick();
    dev.setThreads(32);
    dev.clock.tick();

    for (0..constants.constants.sm_count) |i| {
        try dev.launch(i);
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

    // std.log.debug("{any}", .{dev.SMs.items[0].register_file.get(15)});
    if (constants.constants.viz == 1) {
        const tracker_json = try dev.kernel_tracker.?.to_json();
        std.log.info("viz on: http://localhost:8080", .{});
        serve.serve(tracker_json);
    }
    // std.log.debug("{any}", .{dev.SMs.items[0].register_file});
    // const sl = dev.SMs.items[0].register_file.get(2);
    // const v = std.mem.readInt(u32, @ptrCast(sl.ptr), .little);
    // std.log.debug("{d}", .{@as(u32, @bitCast(v))});
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
