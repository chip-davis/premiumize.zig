//! /cache/* endpoints. Get one with `client.cache()`.
const Cache = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
const mock = @import("../testing.zig");
client: *Client,

pub const CacheCheckOptions = struct {
    items: []const []const u8, // Links to check. Required.
    diag: ?*Client.Diagnostics = null, // Filled with error details on failure. Optional.
};

/// POST /cache/check : Tests whether links are already in the cache.
/// Response is parallel arrays indexed by request order.
pub fn check(self: Cache, opts: CacheCheckOptions) !std.json.Parsed(types.CacheCheck) {
    if (opts.items.len == 0) return Client.Error.InvalidArgument;

    const a = self.client.allocator;
    var params: std.ArrayList(Client.Param) = .empty;
    defer params.deinit(a);

    try params.ensureTotalCapacity(a, opts.items.len);

    for (opts.items) |i| params.appendAssumeCapacity(.{ .name = "items[]", .value = i });

    return self.client.post(types.CacheCheck, endpoints.cache.check, params.items, opts.diag);
}

test "cache/check" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","response":[true,false],"filename":["My.Transfer.Name",null],"filesize":["12345678901",0]}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.cache().check(.{ .items = &.{ "magnet:?xt=a", "https://h/b" } });
    defer res.deinit();

    try srv.expectPost("POST /api/cache/check?apikey=test-key", "items%5B%5D=magnet%3A%3Fxt%3Da&items%5B%5D=https%3A%2F%2Fh%2Fb");
    try std.testing.expectEqualSlices(bool, &.{ true, false }, res.value.response);
    try std.testing.expectEqualStrings("My.Transfer.Name", res.value.filename[0].?);
    try std.testing.expectEqual(@as(?[]const u8, null), res.value.filename[1]);
    try std.testing.expectEqual(@as(u64, 12345678901), res.value.filesize[0].bytes);
    try std.testing.expectEqual(@as(u64, 0), res.value.filesize[1].bytes);
}

test "cache/check requires items" {
    var c = Client.init(std.testing.allocator, undefined, .{ .auth = .{ .api_key = mock.api_key } });
    try std.testing.expectError(error.InvalidArgument, c.cache().check(.{ .items = &.{} }));
}
