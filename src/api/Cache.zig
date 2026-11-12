//! /cache/* endpoints. Get one with `client.cache()`.
const Cache = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
client: *Client,
