const std = @import("std");
const core = @import("core.zig");
const utils = @import("utils.zig");

pub const Value = union(core.DataType) {
    none: u1,
    f32: f32,
    f64: f64,
    b8: i8,
    b16: i16,
    b32: i32,
    b64: i64,
    u8: u8,
    u16: u16,
    u32: u32,
    u64: u64,
    // ptr: u64,
    // vec4 = 0xD,
    // custom = 0xF,
};

pub const WrappedValue = struct {
    dtype: core.DataType,
    value: Value,
    const Self = @This();
    pub fn add(self: Self, rhs: WrappedValue) WrappedValue {
        return switch (self.value) {
            inline else => |x, tag| .{
                .dtype = self.dtype,
                .value = @unionInit(Value, @tagName(tag), x + @field(rhs.value, @tagName(tag))),
            },
        };
    }

    pub fn sub(self: Self, rhs: WrappedValue) WrappedValue {
        return switch (self.value) {
            inline else => |x, tag| .{
                .dtype = self.dtype,
                .value = @unionInit(Value, @tagName(tag), x - @field(rhs.value, @tagName(tag))),
            },
        };
    }
    pub fn mul(self: Self, rhs: WrappedValue) WrappedValue {
        return switch (self.value) {
            inline else => |x, tag| .{
                .dtype = self.dtype,
                .value = @unionInit(Value, @tagName(tag), x * @field(rhs.value, @tagName(tag))),
            },
        };
    }

    pub fn div(self: Self, rhs: WrappedValue) WrappedValue {
        return switch (self.value) {
            inline else => |x, tag| .{
                .dtype = self.dtype,
                .value = @unionInit(Value, @tagName(tag), @divExact(x, @field(rhs.value, @tagName(tag)))),
            },
        };
    }
    // pub fn unwrap(self: Self) []const u8 {
    //     if (self.value == .f32) {
    //         const b = core.intAsSlice(u32, @as(u32, @bitCast(self.value.f32)));
    //         const f = std.mem.readInt(u32, @ptrCast(b.ptr), .little);
    //         std.log.debug("HERE: {any}, {any}", .{ b, @as(f32, @bitCast(f)) });
    //         return &[_]u8{};
    //     }
    //     return &[_]u8{};
    // }
    pub fn unwrap(self: Self, buffer: *[]u8) void {
        const T = @TypeOf(self.value);
        const info = @typeInfo(T);
        inline for (info.@"union".fields) |field| {
            if (self.value == @field(T, field.name)) {
                // Handle each type
                switch (field.type) {
                    u8, i8 => {
                        const v = @constCast(&[_]u8{@bitCast(@field(self.value, field.name))});
                        @memcpy(buffer.ptr, v);
                    },
                    u16, i16 => {
                        const val = @field(self.value, field.name);
                        const v = @constCast(@as([2]u8, @bitCast(val))[0..]);
                        @memcpy(buffer.ptr, v);
                    },
                    f32 => {
                        const val = core.intAsSlice(u32, @as(u32, @bitCast(self.value.f32)));
                        @memcpy(buffer.ptr, val);
                        // const f = std.mem.readInt(u32, @ptrCast(val.ptr), .little);
                        // std.log.debug("HERE: {any} {any}", .{ val, @as(f32, @bitCast(f)) });
                    },
                    u32, i32 => {
                        const val = @field(self.value, field.name);
                        const v = @constCast(@as([4]u8, @bitCast(val))[0..]);
                        @memcpy(buffer.ptr, v);
                    },
                    u64, i64, f64 => {
                        const val = @field(self.value, field.name);
                        const v = @constCast(@as([8]u8, @bitCast(val))[0..]);
                        @memcpy(buffer.ptr, v);
                    },
                    else => {
                        @panic("reached bad type");
                    },
                }
            }
        }
    }
};

pub fn wrap(dtype: core.DataType, slice: []u8) WrappedValue {
    return switch (dtype) {
        inline else => |tag| {
            // Get the union type info at comptime
            const union_info = @typeInfo(Value).@"union";
            // Find the field type for this tag at comptime
            const idx = comptime blk: {
                var i: usize = 0;
                while (i < union_info.fields.len) : (i += 1) {
                    if (std.mem.eql(u8, union_info.fields[i].name, @tagName(tag))) break :blk i;
                }
                unreachable;
            };
            const field_type = union_info.fields[idx].type;
            return WrappedValue{
                .dtype = dtype,
                .value = @unionInit(Value, @tagName(tag), utils.fromBytes(field_type, slice)),
            };
        },
    };
}
