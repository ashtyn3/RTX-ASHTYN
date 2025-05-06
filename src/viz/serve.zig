const std = @import("std");
const tk = @import("tokamak");

const routes: []const tk.Route = &.{
    .get("/", tk.static.file("src/viz/index.html")),
    .get("/*", tk.static.dir("src/viz/", .{ .index = "src/viz/index.html" })),
};

pub fn serve() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var server = tk.Server.init(allocator, routes, .{ .listen = .{ .port = 8080 } }) catch {
        @panic("Failed to init server");
    };
    server.start() catch {
        @panic("Failed to start server");
    };
}
