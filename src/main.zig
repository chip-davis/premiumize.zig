const std = @import("std");
const httpx = @import("httpx");
const Io = std.Io;

const premiumize_zig = @import("premiumize_zig");

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = Io.Threaded.global_single_threaded.io();

    const args = try init.minimal.args.toSlice(a);
    if (args.len < 2) {
        std.debug.print("usage: {s} <api-key>\n", .{args[0]});
        std.process.exit(2);
    }
    var pm = premiumize_zig.Client.init(a, io, .{ .auth = .{ .api_key = args[1] } });
    defer pm.deinit();

    const info = pm.account().info() catch |err| {
        std.debug.print("{s}: {s}\n", .{ @errorName(err), pm.lastError() orelse "" });
        return;
    };
    std.debug.print("customer {s}, space used {d}\n", .{ info.value.customer_id, info.value.space_used });
}
