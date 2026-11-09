const std = @import("std");
const httpx = @import("httpx");
const Io = std.Io;

const premiumize_zig = @import("premiumize_zig");
const API_BASE = "https://www.premiumize.me/api/";

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = Io.Threaded.global_single_threaded.io();
    const env = init.environ_map;
    if (!env.contains("API_KEY")) {
        std.debug.print("Error: API_KEY is not set.", .{});
        std.process.exit(1);
    }
    var client = httpx.Client.init(arena, io, .{});
    defer client.deinit();

    var response = client.fetch(API_BASE ++ "account/info", .{
        .bearerAuth = env.get("API_KEY"),
        .timeoutMs = 10_000,
    }) catch |err| {
        std.debug.print("request failed: {s}\n", .{@errorName(err)});
        return;
    };
    defer response.deinit();
    std.debug.print("{d}: {s}\n", .{ response.status, response.bytes() });
}
