//! /account/* endpoints. Get one with `client.account()`.
const Account = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
const mock = @import("../testing.zig");
client: *Client,

/// GET /account/info
pub fn info(self: Account) !std.json.Parsed(types.AccountInfo) {
    return self.client.get(types.AccountInfo, endpoints.account.info, &.{});
}

test "account/info" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","customer_id":"941345052","premium_until":1800000000,"limit_used":0.25,"space_used":8142224249}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.account().info();
    defer res.deinit();

    try srv.expectGet("GET /api/account/info?apikey=test-key");
    try std.testing.expectEqualStrings("941345052", res.value.customer_id);
    try std.testing.expectEqual(@as(?i64, 1800000000), res.value.premium_until);
    try std.testing.expectEqual(@as(f64, 0.25), res.value.limit_used);
    try std.testing.expectEqual(@as(f64, 8142224249), res.value.space_used);
}
