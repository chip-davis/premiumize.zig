//! /cache/* endpoints. Get one with `client.cache()`.
const Cache = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
client: *Client,

pub const CacheCheckOptions = struct {
    items: []const []const u8, // Links to check. Required.
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

    return self.client.post(types.CacheCheck, endpoints.cache.check, params.items);
}
