const constants = @import("./constants.zig").constants;
const std = @import("std");
const assert = std.debug.assert;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const log = std.log.scoped(.Bus);

pub fn Bus(Msg: type, width: ?u8) type {
    const w = width orelse constants.bus_max;
    assert(w <= constants.bus_max);
    return struct {
        Q: [w]Msg,
        active: u32 = 0,
        mut: Mutex = .{},

        const Self = @This();

        pub fn init(a: std.mem.Allocator) !*Self {
            assert(@sizeOf(Msg) <= 64);
            var s = try a.create(Self);
            s.Q = std.mem.zeroes([w]Msg);
            s.active = 0;
            s.mut = .{};
            return s;
        }
        pub fn put(self: *Self, msg: Msg) void {
            self.mut.lock();
            errdefer self.mut.unlock();
            self.Q[self.active] = msg;
            if (w != 1) {
                self.active += 1;
            }
            self.mut.unlock();
        }

        pub fn get(self: *Self) Msg {
            self.mut.lock();
            errdefer self.mut.unlock();
            if (self.active == 0) {
                self.mut.unlock();
                return self.Q[0];
            }
            assert(self.active - 1 >= 0);
            const value = self.Q[self.active - 1];
            self.active -= 1;
            self.mut.unlock();
            return value;
        }

        pub fn sink(self: *Self) []Msg {
            self.mut.lock();
            self.active = 0;
            const copy = self.Q;
            self.Q = std.mem.zeroes([w]Msg);
            self.mut.unlock();
            return @constCast(&copy);
        }

        pub fn debug(self: *Self) void {
            log.info("type={any} width={any} at={any} data={any}", .{ Msg, w, self.active, self.Q });
        }
    };
}
