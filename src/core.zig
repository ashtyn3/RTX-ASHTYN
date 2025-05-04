const std = @import("std");
const Cluster = @import("cluster.zig").Cluster;
const Thread = @import("thread.zig").Thread;
const Kernel = @import("kernel.zig").Kernel;
const RegFile = @import("registers.zig").RegisterFile;
const SM = @import("SM.zig").SM;
const assert = std.debug.assert;
const log = std.log.scoped(.Core);
const utils = @import("utils.zig");
const ALU = @import("ALU.zig");

cluster_ctx: *Cluster,
thread_ctx: *Thread,
SM_ctx: *SM,
register_file: *RegFile,
kernel: *Kernel,

const Self = @This();

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

    mov = 0x03,

    add = 0x04,
    sub = 0x05,
    mul = 0x06,
    div = 0x07,
};

pub const DataType = enum(u4) {
    none = 0x0,
    f32 = 0x2,
    f64 = 0x3,
    b8 = 0x4,
    b16 = 0x5,
    b32 = 0x6,
    b64 = 0x7,
    u8 = 0x8,
    u16 = 0x9,
    u32 = 0xA,
    u64 = 0xB,
    // ptr = 0xC,
    // vec4 = 0xD,
    // custom = 0xF,
};
pub const Modifier = packed struct {
    abs: bool = false,
    neg: bool = false,
    clamp: bool = false,
    omod: u2 = 0, // 0 = none, 1 = *2, 2 = *4, 3 = /2
};
pub const Operand = packed struct {
    kind: enum(u2) { reg, mem, none },
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

    const InstructionSelf = @This();

    pub fn toBytes(self: *const InstructionSelf) []const u8 {
        return utils.toBytes(InstructionSelf, self);
    }
};

pub inline fn intAsSlice(comptime T: type, value: T) []u8 {
    const size = @sizeOf(T);
    var slice = [_]u8{0} ** size;
    std.mem.writeInt(T, &slice, value, .little);
    return &slice;
}

pub fn dtypeAsSlice(dtype: DataType, lit: anytype) []const u8 {
    switch (dtype) {
        .f64 => {
            return intAsSlice(u64, lit);
        },
        .f32 => {
            return intAsSlice(u32, lit);
        },
        .u16 => {
            return intAsSlice(u16, @intCast(lit));
        },
        .u32 => {
            return intAsSlice(u32, lit);
        },
        .u64 => {
            return intAsSlice(u64, lit);
        },
        .u8 => {
            return intAsSlice(u8, @intCast(lit));
        },
        .b64 => {
            return intAsSlice(u64, @intCast(lit));
        },
        .b32 => {
            return intAsSlice(u32, @intCast(lit));
        },
        .b16 => {
            return intAsSlice(u16, @intCast(lit));
        },
        .b8 => {
            return intAsSlice(u8, @intCast(lit));
        },
        .none => {
            unreachable;
        },
    }
    return &[_]u8{};
}

fn getSrcVal(self: *Self, op: Operand) ?[]const u8 {
    if (op.kind == .none) {
        return null;
    }
    if (op.kind == .reg) {
        const r_data = self.register_file.get(self.thread_ctx.reg_min + op.value);
        return r_data;
    }
    return null;
}

fn putRegisterDstVal(self: *Self, ins: Instruction, sl: []const u8) void {
    if (ins.dtype == .f64 or ins.dtype == .b64 or ins.dtype == .u64) {
        assert((ins.dst.value + 1) <= (self.thread_ctx.reg_max - self.thread_ctx.reg_min)); // spread 64 bit numbers into two consecutive registers
        self.register_file.set(self.thread_ctx.reg_min + ins.dst.value, sl[0..1]);
        self.register_file.set(self.thread_ctx.reg_min + ins.dst.value + 1, sl[2..4]);
    } else {
        self.register_file.set(self.thread_ctx.reg_min + ins.dst.value, sl);
    }
}

fn mem_ops(self: *Self, ins: Instruction) !void {
    switch (ins.op) {
        .mov => {
            switch (ins.dst.kind) {
                .reg => {
                    if (ins.src0.kind == .none and ins.src1.kind == .none) { // move literal to register
                        self.putRegisterDstVal(ins, dtypeAsSlice(ins.dtype, ins.literal));
                    } else { // move to other register
                        const src0 = self.getSrcVal(ins.src0);
                        const src1 = self.getSrcVal(ins.src1);
                        if (src0) |s0| {
                            assert(ins.src0.kind == .reg);
                            self.putRegisterDstVal(ins, s0);
                        }
                        if (src1) |s1| {
                            assert(ins.src1.kind == .reg);
                            self.putRegisterDstVal(ins, s1);
                        }
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
pub fn ALU_handle(self: *Self, ins: Instruction) !void {
    if (ins.src0.kind != .none and ins.src1.kind != .none) {
        const arg1 = ALU.wrap(ins.dtype, @constCast(self.getSrcVal(ins.src0).?));
        const arg2 = ALU.wrap(ins.dtype, @constCast(self.getSrcVal(ins.src1).?));

        // std.log.debug("{any} + {any}", .{ arg1, arg2 });
        const v = switch (ins.op) {
            .add => arg1.add(arg2),
            .sub => arg1.sub(arg2),
            .mul => arg1.mul(arg2),
            .div => arg1.div(arg2),
            else => {
                @panic("undefined for ALU");
            },
        };
        switch (arg1.value) {
            inline else => |_, tag| {
                const t = @FieldType(ALU.Value, @tagName(tag));
                var b = try self.SM_ctx.device.allocator.alloc(u8, @sizeOf(t));
                v.unwrap(&b);

                self.putRegisterDstVal(ins, b);
            },
        }
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
    // std.log.debug("id={any} SM={any} pc={any}", .{ self.thread_ctx.id, self.SM_ctx.id, self.cluster_ctx.pc.get() });
    // std.log.debug("id={any} min_reg={any} max_reg={any}", .{ self.thread_ctx.id, self.thread_ctx.reg_min, self.thread_ctx.reg_max });
    // std.log.debug("id={any} SM={any} got={} raw={any}", .{ self.thread_ctx.id, self.SM_ctx.id, v, raw_instr });
    switch (v.format) {
        .MEM => {
            try self.mem_ops(v);
        },
        .ALU => {
            try self.ALU_handle(v);
        },
        else => {
            unreachable;
        },
    }
    self.thread_ctx.done.put(1);
}
pub const Core = Self;
