const std = @import("std");
const Cluster = @import("cluster.zig").Cluster;
const Thread = @import("thread.zig").Thread;
const Kernel = @import("kernel.zig").Kernel;
const RegFile = @import("registers.zig").RegisterFile;
const SM = @import("SM.zig").SM;
const assert = std.debug.assert;
const log = std.log.scoped(.Core);

cluster_ctx: *Cluster,
thread_ctx: *Thread,
SM_ctx: *SM,
register_file: *RegFile,
kernel: *Kernel,

const Self = @This();

// pub const MemLayer = enum(u4) {
//     none = 0x0,
//     shared = 0x1,
//     local = 0x2,
//     global = 0x3,
//     constant = 0x4,
//     param = 0x5,
// };

pub const Format = enum(u3) {
    ALU = 0x0, // 2 or 3 operand math
    MEM = 0x1, // load/store/atomic
    CTRL = 0x2, // branches, traps, etc.
    VEC = 0x3, // packed math, dot, etc.
    DUAL = 0x4, // dual-issue (like VOPD)
    CLAUSE = 0x5, // clause start
    SYS = 0x6, // system messages
    EXT = 0x7, // extended (64/96-bit)
};

pub const Operation = enum(u7) {
    ld = 0x01,
    st = 0x02,

    add = 0x03,
    sub = 0x04,
    mul = 0x05,
    div = 0x06,
};

pub const DataType = enum(u4) {
    none = 0x0,
    f16 = 0x1,
    f32 = 0x2,
    f64 = 0x3,
    i8 = 0x4,
    i16 = 0x5,
    i32 = 0x6,
    i64 = 0x7,
    u8 = 0x8,
    u16 = 0x9,
    u32 = 0xA,
    u64 = 0xB,
    ptr = 0xC,
    vec4 = 0xD,
    custom = 0xF,
};

pub const Modifier = packed struct {
    abs: bool = false,
    neg: bool = false,
    clamp: bool = false,
    omod: u2 = 0, // 0 = none, 1 = *2, 2 = *4, 3 = /2
};
pub const Operand = packed struct {
    kind: enum(u2) { reg, mem, imm, none },
    value: u16,
};

pub const Flags = packed struct {
    trace: bool = false,
};

pub const Instruction = packed struct {
    format: Format,
    op: Operation,
    dtype: DataType,
    mod: Modifier,
    flags: Flags,
    dst: Operand,
    src0: Operand,
    src1: Operand,
    literal: u32,
};

fn intAsSlice(comptime T: type, value: T) ![]u8 {
    const size = @sizeOf(T);
    var slice = [_]u8{0} ** size;
    std.mem.writeInt(T, &slice, value, .little);
    return &slice;
}

fn dtypeAsSlice(dtype: DataType, lit: anytype) ![]u8 {
    switch (dtype) {
        .i32 => {
            return try intAsSlice(u32, @intCast(lit));
        },
        .i16 => {
            return try intAsSlice(u16, @intCast(lit));
        },
        .i8 => {
            return try intAsSlice(u8, @intCast(lit));
        },
        else => {},
    }
    return &[_]u8{};
}

fn mem_ops(self: *Self, ins: Instruction) !void {
    switch (ins.op) {
        .st => {
            switch (ins.dst.kind) {
                .reg => {
                    if (ins.src0.kind == .none and ins.src1.kind == .none) {
                        if (ins.dtype == .f64 or ins.dtype == .i64) {
                            @panic("Bad data type size for register");
                        } else {
                            const sl = try dtypeAsSlice(ins.dtype, ins.literal);
                            self.register_file.set(self.thread_ctx.reg_min + ins.dst.value, sl);
                        }
                    } else {
                        unreachable;
                    }
                },
                else => {
                    unreachable;
                },
            }
        },
        else => {
            unreachable;
        },
    }
}
pub fn exec(self: *Self) !void {
    const pc = self.cluster_ctx.pc.get();
    const raw_instr = self.kernel.at(pc);
    if (self.thread_ctx.done.get() == 1) {
        return;
    }
    if (raw_instr.len == 0) {
        self.thread_ctx.done.put(1);
        return;
    }
    const v = std.mem.bytesToValue(Instruction, raw_instr);
    // _ = ins_head;
    // std.log.debug("id={any} SM={any} pc={any}", .{ self.thread_ctx.id, self.SM_ctx.id, self.cluster_ctx.pc.get() });
    // std.log.debug("id={any} min_reg={any} max_reg={any}", .{ self.thread_ctx.id, self.thread_ctx.reg_min, self.thread_ctx.reg_max });
    std.log.debug("id={any} SM={any} got={} raw={any}", .{ self.thread_ctx.id, self.SM_ctx.id, v, raw_instr });
    switch (v.format) {
        .MEM => {
            try self.mem_ops(v);
        },
        else => {
            unreachable;
        },
    }
    self.thread_ctx.done.put(1);
}
pub const Core = Self;
