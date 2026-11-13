const Item = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
const mock = @import("../testing.zig");

client: *Client,

pub const ItemDetailsOptions = struct {
    id: []const u8, // File ID
};

/// GET /item/details
/// Returns full metadata for a single file. Folder IDs are not accepted; pass a file ID only.
pub fn details(self: Item, opts: ItemDetailsOptions) !std.json.Parsed(types.ItemDetails) {
    return self.client.get(types.ItemDetails, endpoints.item.details, &.{.{ .name = "id", .value = opts.id }}, null);
}

pub const ItemRenameOptions = struct {
    id: []const u8,
    name: []const u8,
};

/// POST /item/rename
/// Renames a file.
pub fn rename(self: Item, opts: ItemRenameOptions) !void {
    return self.client.postOk(endpoints.item.rename, &.{ .{ .name = "id", .value = opts.id }, .{ .name = "name", .value = opts.name } }, null);
}

pub const ItemDeleteOptions = struct {
    id: []const u8, // File ID
};

/// POST /item/delete : Deletes a file
pub fn delete(self: Item, opts: ItemDeleteOptions) !void {
    return self.client.postOk(endpoints.item.delete, &.{.{ .name = "id", .value = opts.id }}, null);
}

/// GET /item/listall : Returns a flat list of every file the user owns, with full path.
/// Parameters: None.
/// Each files entry has id, name, path (the slash-joined path from root), size (bytes), created_at (Unix timestamp), and mime_type.
pub fn listAll(self: Item) !std.json.Parsed(types.ItemListAll) {
    return self.client.get(types.ItemListAll, endpoints.item.listall, &.{}, null);
}

test "item/details" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","id":"f1","name":"video.mkv","size":123456789,"created_at":1700000000,
        \\ "folder_id":"d1","mime_type":"video/x-matroska","link":"https://dl/x"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.item().details(.{ .id = "f1" });
    defer res.deinit();

    try srv.expectGet("GET /api/item/details?apikey=test-key&id=f1");
    try std.testing.expectEqualStrings("video.mkv", res.value.name);
    try std.testing.expectEqual(@as(u64, 123456789), res.value.size);
    try std.testing.expectEqualStrings("d1", res.value.folder_id);
}

test "item/rename" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    try c.item().rename(.{ .id = "f1", .name = "new.mkv" });

    try srv.expectPost("POST /api/item/rename?apikey=test-key", "id=f1&name=new.mkv");
}

test "item/delete" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    try c.item().delete(.{ .id = "f1" });

    try srv.expectPost("POST /api/item/delete?apikey=test-key", "id=f1");
}

test "item/listall" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","files":[
        \\  {"id":"f1","name":"video.mkv","path":"folder/sub/video.mkv","size":5000000000,"created_at":1700000000,"mime_type":"video/x-matroska"},
        \\  {"id":"f2","name":"x","path":"x","size":0,"created_at":1700000000}
        \\]}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.item().listAll();
    defer res.deinit();

    try srv.expectGet("GET /api/item/listall?apikey=test-key");
    try std.testing.expectEqual(@as(usize, 2), res.value.files.len);
    try std.testing.expectEqualStrings("folder/sub/video.mkv", res.value.files[0].path);
    try std.testing.expectEqual(@as(u64, 5000000000), res.value.files[0].size);
    try std.testing.expectEqual(@as(?[]const u8, null), res.value.files[1].mime_type);
}
