//! /services/* endpoints. Get one with `client.services()`.
const Services = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
const mock = @import("../testing.zig");
client: *Client,

/// GET /services/list : Returns metadata for every supported service.
pub fn list(self: Services) !std.json.Parsed(types.ServicesList) {
    return self.client.get(types.ServicesList, endpoints.services.list, &.{}, null);
}

test "services/list" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","cache":["s1","s2"],"directdl":["s1"],"queue":["s1","s2"],
        \\ "fairusefactor":{"s1":1,"s2":2.5},
        \\ "aliases":{"s1":["e1.alt"],"s2":["e2.alt","e2.also"]},
        \\ "regexpatterns":{"s1":["^https?://(?:www\\.)?s1\\.com/.*$"],"s2":[]}}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.services().list();
    defer res.deinit();

    try srv.expectGet("GET /api/services/list?apikey=test-key");
    try std.testing.expectEqual(@as(usize, 2), res.value.cache.len);
    try std.testing.expectEqualStrings("s1", res.value.directdl[0]);
    try std.testing.expectEqual(@as(f64, 2.5), res.value.fairusefactor.map.get("s2").?);
    try std.testing.expectEqual(@as(usize, 2), res.value.aliases.map.get("s2").?.len);
    try std.testing.expectEqualStrings("^https?://(?:www\\.)?s1\\.com/.*$", res.value.regexpatterns.map.get("s1").?[0]);
    try std.testing.expectEqual(@as(usize, 0), res.value.regexpatterns.map.get("s2").?.len);
}
