const std = @import("std");
const assert = std.debug.assert;

const ALU = @import("ALU.zig");
const Bus = @import("bus.zig").Bus;
const Cluster = @import("cluster.zig").Cluster;
const constants = @import("constants.zig").constants;
const Kernel = @import("kernel.zig").Kernel;
const RegFile = @import("registers.zig").RegisterFile;
const SM = @import("SM.zig").SM;
const Thread = @import("thread.zig").Thread;
const MemOptim = @import("mem_optim.zig").MemoryOptimizer;
const utils = @import("utils.zig");

const log = std.log.scoped(.Core);
cluster_ctx: *Cluster,
thread_ctx: *Thread,
SM_ctx: *SM,
register_file: *RegFile,
kernel: *Kernel,
last_pc: *Bus(i64, 1),

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
    kind: enum(u2) { reg, sys_reg, mem, none },
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
            return intAsSlice(u32, @intCast(lit));
        },
        .u16 => {
            return intAsSlice(u16, @intCast(lit));
        },
        .u32 => {
            return intAsSlice(u32, @intCast(lit));
        },
        .u64 => {
            return intAsSlice(u64, lit);
        },
        .u8 => {
            return intAsSlice(u8, @intCast(lit));
        },
        .b64 => {
            return intAsSlice(i64, @intCast(lit));
        },
        .b32 => {
            return intAsSlice(i32, @intCast(lit));
        },
        .b16 => {
            return intAsSlice(i16, @intCast(lit));
        },
        .b8 => {
            return intAsSlice(i8, @intCast(lit));
        },
        .none => {
            unreachable;
        },
    }
    return &[_]u8{};
}

fn getSrcVal(self: *Self, dtype: DataType, op: Operand) ?[]const u8 {
    if (op.kind == .none) {
        return null;
    }
    if (op.kind == .reg) {
        if (ALU.sizeOf(dtype) == 8) {
            const r_data = self.register_file.get(self.thread_ctx.reg_min + op.value);
            const r_data2 = self.register_file.get(self.thread_ctx.reg_min + op.value + 1);
            const data = self.SM_ctx.device.allocator.alloc(u8, 8) catch {
                @panic("broken");
            };
            @memcpy(data[0..4].ptr, r_data[0..4]);
            @memcpy(data[4..8].ptr, r_data2[0..4]);
            return data;
        }
        const r_data = self.register_file.get(self.thread_ctx.reg_min + op.value);
        // var data = [_]u8{0} ** 4;
        // @memcpy(data[0..4].ptr, r_data[0..4]);
        return r_data;
    }
    if (op.kind == .sys_reg) {
        switch (op.value) {
            0 => return dtypeAsSlice(.u64, self.thread_ctx.id),
            else => {
                @panic("bad system register");
            },
        }
    }
    if (op.kind == .mem) {
        const r_data = self.register_file.get(self.thread_ctx.reg_min + op.value);
        const r_data2 = self.register_file.get(self.thread_ctx.reg_min + op.value + 1);
        var data = [_]u8{0} ** 8;
        @memcpy(data[0..4].ptr, r_data[0..4]);
        @memcpy(data[4..8].ptr, r_data2[0..4]);
        return &data;
    }
    return null;
}

fn putRegisterDstVal(self: *Self, ins: Instruction, sl: []const u8) void {
    if (ins.dtype == .f64 or ins.dtype == .b64 or ins.dtype == .u64) {
        assert((ins.dst.value + 1) <= (self.thread_ctx.reg_max - self.thread_ctx.reg_min)); // spread 64 bit numbers into two consecutive registers
        self.register_file.set(self.thread_ctx.reg_min + ins.dst.value, sl[0..4]);
        self.register_file.set(self.thread_ctx.reg_min + ins.dst.value + 1, sl[5..8]);
    } else {
        self.register_file.set(self.thread_ctx.reg_min + ins.dst.value, sl);
    }
}
pub fn destroy(self: *Self) void {
    self.SM_ctx.device.allocator.destroy(self.last_pc);
}

fn mem_ops(self: *Self, ins: Instruction) !void {
    switch (ins.op) {
        .mov => {
            switch (ins.dst.kind) {
                .reg => {
                    if (ins.src0.kind == .none and ins.src1.kind == .none) { // move literal to register
                        self.putRegisterDstVal(ins, dtypeAsSlice(ins.dtype, ins.literal));
                    } else { // move to other register
                        const src0 = self.getSrcVal(ins.dtype, ins.src0);
                        const src1 = self.getSrcVal(ins.dtype, ins.src1);
                        if (src0) |s0| {
                            assert(ins.src0.kind == .reg or ins.src0.kind == .sys_reg);
                            self.putRegisterDstVal(ins, s0);
                        }
                        if (src1) |s1| {
                            assert(ins.src1.kind == .reg or ins.src1.kind == .sys_reg);
                            self.putRegisterDstVal(ins, s1);
                        }
                    }
                },
                else => {
                    unreachable;
                },
            }
        },
        .st => {
            const src0 = self.getSrcVal(ins.dtype, ins.src0);
            assert(ins.src1.kind == .none);
            const dst = self.getSrcVal(.u64, ins.dst);
            const addr = ALU.wrap(.u64, @constCast(dst.?)).value.u64;
            if (src0) |data| {
                self.SM_ctx.store_memory(self.cluster_ctx.id, self.thread_ctx.id, self.cluster_ctx.pc.get(), addr, @constCast(data));
                // self.cluster_ctx.wait.put(.{ self.cluster_ctx.id, addr });
            }
        },
        .ld => {
            const src0 = self.getSrcVal(ins.dtype, ins.src0);
            if (src0) |s| {
                assert(ins.src1.kind == .none);
                const addr = ALU.wrap(.u64, @constCast(s)).value.u64;
                var temp = std.heap.c_allocator.alloc(u8, ALU.sizeOf(ins.dtype)) catch {
                    @panic("broken temp");
                };
                const r_res = self.SM_ctx.mem.read(MemOptim.Request{
                    .type = .read,
                    .data = .{
                        .read = .{
                            .address = addr,
                            .cluster_id = self.cluster_ctx.id,
                            .thread_id = self.thread_ctx.id,
                            .len = ALU.sizeOf(ins.dtype),
                            .pc = self.cluster_ctx.pc.get(),
                        },
                    },
                }, &temp);
                if (r_res) |_| {
                    self.putRegisterDstVal(ins, temp);
                } else {
                    self.cluster_ctx.wait.put(.{ self.thread_ctx.id, addr });
                }
            }
            // self.putRegisterDstVal(ins, sl: []const u8);
        },
        else => {
            unreachable;
        },
    }
}
pub fn ALU_handle(self: *Self, ins: Instruction) !void {
    if (ins.src0.kind != .none and ins.src1.kind != .none) {
        const arg1 = ALU.wrap(ins.dtype, @constCast(self.getSrcVal(ins.dtype, ins.src0).?));
        const arg2 = ALU.wrap(ins.dtype, @constCast(self.getSrcVal(ins.dtype, ins.src1).?));

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
    // if (self.last_pc.get() == pc) {
    // self.thread_ctx.done.put(1);
    // return;
    // }
    if (raw_instr.len == 0) {
        self.thread_ctx.done.put(1);
        return;
    }
    if (self.cluster_ctx.wait.active != 0) {
        return;
    }
    const v = std.mem.bytesToValue(Instruction, raw_instr);
    // std.log.debug("{any}", .{self.thread_ctx.id});
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
    if (self.cluster_ctx.wait.active == 0) {
        self.thread_ctx.done.put(1);
    }
    // self.cluster_ctx.wait.debug();
    self.last_pc.put(@intCast(pc));
    if (constants.viz == 1) {
        try self.SM_ctx.tracker.?.add_node(0, .{
            .SM = self.SM_ctx.id,
            .cluster = self.cluster_ctx.id,
            .thread = self.cluster_ctx.id,
            .instruction = v,
            .last_pc = self.last_pc.get(),
            .pc = pc,
        });
    }
}
pub const Core = Self;
