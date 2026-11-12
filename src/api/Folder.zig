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
