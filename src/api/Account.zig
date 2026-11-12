//! /account/* endpoints. Get one with `client.account()`.
const Account = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
client: *Client,

/// GET /account/info
pub fn info(self: Account) !std.json.Parsed(types.AccountInfo) {
    return self.client.get(types.AccountInfo, endpoints.account.info, &.{});
}
