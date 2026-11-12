//! /folder/* endpoints. Get one with `client.folder()`.

const Folder = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");

client: *Client,

pub const FolderListOptions = struct { id: ?[]const u8 = null, path: ?[]const u8 = null, include_breadcrumbs: bool = false };
/// GET /folder/list : Lists the contents of a folder. If neither id nor path is passed, the root folder is returned.
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

    return self.client.get(types.FolderList, endpoints.folder.list, buf[0..n]);
}

pub const FolderCreateOptions = struct {
    name: []const u8, // Folder name. Required.
    parent_id: ?[]const u8 = null, // Parent folder ID. Optional; defaults to root.
};
/// POST /folder/create : Creates a folder.
pub fn create(self: Folder, opts: FolderCreateOptions) !std.json.Parsed(types.FolderCreate) {
    var buf: [2]Client.Param = undefined;
    var n: usize = 0;

    if (opts.parent_id) |p_id| {
        buf[n] = .{ .name = "parent_id", .value = p_id };
        n += 1;
    }
    buf[n] = .{ .name = "name", .value = opts.name };
    n += 1;

    return self.client.post(types.FolderCreate, endpoints.folder.create, buf[0..n]);
}

pub const FolderRenameOptions = struct {
    id: []const u8, // Folder ID. Required.
    name: []const u8, // New name. Required.
};
/// POST /folder/rename : Renames a folder.
pub fn rename(self: Folder, opts: FolderRenameOptions) !std.json.Parsed(types.FolderRename) {
    return self.client.post(types.FolderRename, endpoints.folder.rename, &.{ .{ .name = "id", .value = opts.id }, .{ .name = "name", .value = opts.name } });
}

pub const FolderDeleteOptions = struct {
    id: []const u8, // Folder ID. Required.
};
/// POST /folder/delete : Deletes a folder and its contents.
pub fn delete(self: Folder, opts: FolderDeleteOptions) !std.json.Parsed(types.FolderDelete) {
    return self.client.post(types.FolderDelete, endpoints.folder.delete, &.{.{ .name = "id", .value = opts.id }});
}

/// At least one of files[] or folders[] is required.
pub const FolderPasteOptions = struct {
    id: []const u8, // Target folder ID.
    files: []const []const u8 = &.{}, // File IDs to move. Optional
    folders: []const []const u8 = &.{}, // Folder IDs to move. Optional.
};
/// POST /folder/paste : Moves files and/or folders into a target folder.
pub fn paste(self: Folder, opts: FolderPasteOptions) !std.json.Parsed(types.FolderPaste) {
    if (opts.files.len == 0 and opts.folders.len == 0) return Client.Error.InvalidArgument;

    const a = self.client.allocator;
    var params: std.ArrayList(Client.Param) = .empty;
    defer params.deinit(a);

    try params.ensureTotalCapacity(a, 1 + opts.files.len + opts.folders.len);

    params.appendAssumeCapacity(.{ .name = "id", .value = opts.id });

    for (opts.files) |f| params.appendAssumeCapacity(.{ .name = "files[]", .value = f });
    for (opts.folders) |f| params.appendAssumeCapacity(.{ .name = "folders[]", .value = f });

    return self.client.post(types.FolderPaste, endpoints.folder.paste, params.items);
}

pub const FolderUploadInfoOptions = struct {
    id: []const u8, // Target folder ID. Optional; defaults to root.
};

/// POST /folder/uploadinfo : Returns an upload token and URL for direct file upload to a folder.
/// Two-step flow: call this endpoint to get a one-shot upload url and token, then POST your file to that url.
pub fn uploadinfo(self: Folder, opts: FolderUploadInfoOptions) !std.json.Parsed(types.FolderUploadInfo) {
    var buf: [1]Client.Param = undefined;
    var n: usize = 0;

    if (opts.id) |id| {
        buf[n] = .{ .name = "id", .value = id };
        n += 1;
    }

    return self.client.post(types.FolderUploadInfo, endpoints.folder.uploadinfo, buf[0..n]);
}
