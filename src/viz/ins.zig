const std = @import("std");
const core = @import("../core.zig");

pub const GraphOp = struct {
    instruction: core.Instruction,
    thread: u64,
    cluster: u64,
    SM: u64,
    pc: u64,
    last_pc: i64,
};

pub const Graph = struct {
    mutex: std.Thread.Mutex,
    nodes: std.ArrayList(GraphOp),
    edges: std.ArrayList(struct { u64, u64 }),
};

pub const KernelTracker = struct {
    kernels: []Graph,

    pub fn init(a: std.mem.Allocator) !KernelTracker {
        const data = try a.alloc(Graph, 1);
        for (data) |*g| {
            g.* = Graph{
                .nodes = std.ArrayList(GraphOp).init(a),
                .edges = std.ArrayList(struct { u64, u64 }).init(a),
                .mutex = .{},
            };
        }
        return KernelTracker{
            .kernels = data,
        };
    }
    pub fn add_node(self: *KernelTracker, id: u8, op: GraphOp) !void {
        self.kernels[id].mutex.lock();
        try self.kernels[id].nodes.append(op);
        self.kernels[id].mutex.unlock();
    }
    pub fn to_json(self: *KernelTracker) ![]u8 {
        var buffer = std.ArrayList(u8).init(std.heap.c_allocator);

        for (self.kernels) |*k| {
            // Group nodes by thread
            var thread_map = std.AutoHashMap(u64, std.ArrayList(GraphOp)).init(std.heap.c_allocator);
            defer thread_map.deinit();

            for (k.nodes.items) |n| {
                if (thread_map.contains(n.thread)) {
                    try thread_map.getPtr(n.thread).?.append(n);
                } else {
                    var arr = std.ArrayList(GraphOp).init(std.heap.c_allocator);
                    try arr.append(n);
                    try thread_map.put(n.thread, arr);
                }
            }

            // Focus on thread 0
            const first_thread_ptr = thread_map.getPtr(0) orelse continue;
            var first_thread = first_thread_ptr.*;

            // Remove duplicate memory ops and build proc list
            var has_mem = std.AutoHashMap(u64, void).init(std.heap.c_allocator);
            defer has_mem.deinit();
            var idx: usize = 0;
            while (idx < first_thread.items.len) {
                const op = first_thread.items[idx];
                if (op.instruction.dst.kind == .mem) {
                    if (has_mem.contains(op.pc)) {
                        _ = first_thread.orderedRemove(idx);
                        continue; // Don't increment idx, as items shift left
                    } else {
                        try has_mem.put(op.pc, {});
                    }
                }
                idx += 1;
            }

            // Build edges: connect sequential instructions on same SM, and memory ops
            k.edges.clearRetainingCapacity();
            for (first_thread.items, 0..) |op_i, i| {
                for (first_thread.items, 0..) |op_j, j| {
                    if (i == j) continue;
                    if (op_i.SM == op_j.SM and op_i.pc + 1 == op_j.pc) {
                        try k.edges.append(.{ i, j });
                    } else if (op_j.instruction.dst.kind == .mem and op_i.pc + 1 == op_j.pc) {
                        try k.edges.append(.{ i, j });
                    }
                }
            }

            // Serialize to JSON
            const e = try k.edges.toOwnedSlice();
            const n = try first_thread.toOwnedSlice();
            try std.json.stringify(.{ .edges = e, .nodes = n }, .{}, buffer.writer());

            // Clean up thread_map arrays
            var it = thread_map.valueIterator();
            while (it.next()) |arr| {
                arr.deinit();
            }
        }

        return try buffer.toOwnedSlice();
    }
};
