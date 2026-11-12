const Item = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");

client: *Client,

pub const ItemDetailsOptions = struct {
    id: []const u8, // File ID
};

/// GET /item/details
/// Returns full metadata for a single file. Folder IDs are not accepted; pass a file ID only.
pub fn details(self: Item, opts: ItemDetailsOptions) std.json.Parsed(types.ItemDetails) {
    return self.client.get(types.ItemDetails, endpoints.item.details, &.{.{ .name = "id", .value = opts.id }});
}
