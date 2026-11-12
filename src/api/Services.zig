//! /services/* endpoints. Get one with `client.services()`.
const Services = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
client: *Client,

/// GET /services/list : Returns metadata for every supported service.
pub fn list(self: Services) !std.json.Parsed(types.ServicesList) {
    return self.client.get(types.ServicesList, endpoints.services.list, &.{});
}
