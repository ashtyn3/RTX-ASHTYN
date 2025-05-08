const ops = @import("build_options");
const std = @import("std");
const log = std.log.scoped(.Constants);

const config = struct {
    bus_max: u64 = ops.BUS_MAX,
    shared_mem_len: u64 = ops.SHARED_MEM_LEN,
    // maximum registers (register = 4 bytes)
    max_register_count: u64 = ops.MAX_REGISTER_COUNT,
    // maximum program lenth in bytes
    max_program_len: u64 = ops.MAX_PROGRAM_LEN,

    // cluster count
    sm_size: u64 = ops.SM_SIZE,
    // sm count
    sm_count: u64 = ops.SM_COUNT,
    slow_clock: u64 = ops.SLOW_CLOCK,
    viz: u64 = ops.VIZ,
};

pub const constants: config = .{};

pub fn debug() void {
    inline for (std.meta.fields(@TypeOf(constants))) |f| {
        log.info(f.name ++ "={any}", .{@as(f.type, @field(constants, f.name))});
    }
}
