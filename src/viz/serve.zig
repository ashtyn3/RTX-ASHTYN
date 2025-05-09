const std = @import("std");
const tk = @import("tokamak");

var shape: []u8 = &[_]u8{};
fn kernel(_: *tk.Response) []u8 {
    return shape;
}

const routes: []const tk.Route = &.{
    .get("/", tk.static.file("src/viz/index.html")),
    .get("/kernel", kernel),
    .get("/*", tk.static.dir("src/viz/", .{ .index = "src/viz/index.html" })),
};

pub fn serve(kernel_shape: []u8) void {
    shape = kernel_shape;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // var inj = tk.Injector.init(&.{.ref(&kernel_shape)}, null);
    var server = tk.Server.init(allocator, routes, .{ .listen = .{ .port = 8080 } }) catch {
        @panic("Failed to init server");
    };
    server.start() catch {
        @panic("Failed to start server");
    };
}
