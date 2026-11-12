//! /folder/* endpoints. Get one with `client.folder()`.

const Folder = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");

client: *Client,

pub const FolderListOptions = struct { id: ?[]const u8 = null, path: ?[]const u8 = null, include_breadcrumbs: bool = false };
/// GET /folder/list
pub fn list(self: Folder, opts: FolderListOptions) !std.json.Parsed(types.FolderList) {
    var buf: [3]Client.Param = undefined;
    var n: usize = 0;

    if (opts.id) |id| {
        buf[n] = .{ .name = "id", .value = id };
        n += 1;
    }
    if (opts.path) |p| {
        buf[n] = .{ .name = "path", .value = p };
        n += 1;
    }
    if (opts.include_breadcrumbs) {
        buf[n] = .{ .name = "includebreadcrumbs", .value = "true" };
        n += 1;
    }

    return self.client.get(types.FolderList, "/folder/list", buf[0..n]);
}

pub const FolderCreateOptions = struct {
    name: []const u8, // Folder name. Required.
    parent_id: ?[]const u8 = null, // Parent folder ID. Optional; defaults to root.
};
/// POST /folder/create
pub fn create(self: Folder, opts: FolderCreateOptions) !std.json.Parsed(types.FolderCreate) {
    var buf: [2]Client.Param = undefined;
    var n: usize = 0;

    if (opts.parent_id) |p_id| {
        buf[n] = .{ .name = "parent_id", .value = p_id };
        n += 1;
    }
    buf[n] = .{ .name = "name", .value = opts.name };
    n += 1;

    return self.client.post(types.FolderCreate, "/folder/create", buf[0..n]);
}

pub const FolderRenameOptions = struct {
    id: []const u8, // Folder ID. Required.
    name: []const u8, // New name. Required.
};
/// POST /folder/rename
pub fn rename(self: Folder, opts: FolderRenameOptions) !std.json.Parsed(types.FolderRename) {
    return self.client.post(types.FolderRename, &.{ .{ .name = "id", .value = opts.id }, .{ .name = "name", .value = opts.name } });
}
