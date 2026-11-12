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
pub fn details(self: Item, opts: ItemDetailsOptions) !std.json.Parsed(types.ItemDetails) {
    return self.client.get(types.ItemDetails, endpoints.item.details, &.{.{ .name = "id", .value = opts.id }});
}

pub const ItemRenameOptions = struct {
    id: []const u8,
    name: []const u8,
};

/// POST /item/rename
/// Renames a file.
pub fn rename(self: Item, opts: ItemRenameOptions) !std.json.Parsed(types.ItemRename) {
    return self.client.post(types.ItemRename, endpoints.item.rename, &.{ .{ .name = "id", .value = opts.id }, .{ .name = "name", .value = opts.name } });
}

pub const ItemDeleteOptions = struct {
    id: []const u8, // File ID
};

/// POST /item/delete : Deletes a file
pub fn delete(self: Item, opts: ItemDeleteOptions) !std.json.Parsed(types.ItemDelete) {
    return self.client.post(types.ItemDelete, endpoints.item.delete, &.{.{ .name = "id", .value = opts.id }});
}

/// GET /item/listall : Returns a flat list of every file the user owns, with full path.
/// Parameters: None.
/// Each files entry has id, name, path (the slash-joined path from root), size (bytes), created_at (Unix timestamp), and mime_type.
pub fn listall(self: Item) !std.json.Parsed(types.ItemListAll) {
    return self.client.post(types.ItemListAll, endpoints.item.listall, &.{});
}
