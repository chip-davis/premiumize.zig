//! /folder/* endpoints. Get one with `client.folder()`.

const Folder = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
const mock = @import("../testing.zig");

client: *Client,

pub const FolderListOptions = struct { id: ?[]const u8 = null, path: ?[]const u8 = null, include_breadcrumbs: bool = false, diag: ?*Client.Diagnostics = null };
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

    return self.client.get(types.FolderList, endpoints.folder.list, buf[0..n], opts.diag);
}

pub const FolderCreateOptions = struct {
    name: []const u8, // Folder name. Required.
    parent_id: ?[]const u8 = null, // Parent folder ID. Optional; defaults to root.
    diag: ?*Client.Diagnostics = null, // Filled with error details on failure. Optional.
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

    return self.client.post(types.FolderCreate, endpoints.folder.create, buf[0..n], opts.diag);
}

pub const FolderRenameOptions = struct {
    id: []const u8, // Folder ID. Required.
    name: []const u8, // New name. Required.
    diag: ?*Client.Diagnostics = null, // Filled with error details on failure. Optional.
};
/// POST /folder/rename : Renames a folder.
pub fn rename(self: Folder, opts: FolderRenameOptions) !void {
    return self.client.postOk(endpoints.folder.rename, &.{ .{ .name = "id", .value = opts.id }, .{ .name = "name", .value = opts.name } }, opts.diag);
}

pub const FolderDeleteOptions = struct {
    id: []const u8, // Folder ID. Required.
    diag: ?*Client.Diagnostics = null, // Filled with error details on failure. Optional.
};
/// POST /folder/delete : Deletes a folder and its contents.
pub fn delete(self: Folder, opts: FolderDeleteOptions) !void {
    return self.client.postOk(endpoints.folder.delete, &.{.{ .name = "id", .value = opts.id }}, opts.diag);
}

/// At least one of files[] or folders[] is required.
pub const FolderPasteOptions = struct {
    id: []const u8, // Target folder ID.
    files: []const []const u8 = &.{}, // File IDs to move. Optional
    folders: []const []const u8 = &.{}, // Folder IDs to move. Optional.
    diag: ?*Client.Diagnostics = null, // Filled with error details on failure. Optional.
};
/// POST /folder/paste : Moves files and/or folders into a target folder.
pub fn paste(self: Folder, opts: FolderPasteOptions) !void {
    if (opts.files.len == 0 and opts.folders.len == 0) return Client.Error.InvalidArgument;

    const a = self.client.allocator;
    var params: std.ArrayList(Client.Param) = .empty;
    defer params.deinit(a);

    try params.ensureTotalCapacity(a, 1 + opts.files.len + opts.folders.len);

    params.appendAssumeCapacity(.{ .name = "id", .value = opts.id });

    for (opts.files) |f| params.appendAssumeCapacity(.{ .name = "files[]", .value = f });
    for (opts.folders) |f| params.appendAssumeCapacity(.{ .name = "folders[]", .value = f });

    return self.client.postOk(endpoints.folder.paste, params.items, opts.diag);
}

pub const FolderUploadInfoOptions = struct {
    id: ?[]const u8 = null, // Target folder ID. Optional; defaults to root.
    diag: ?*Client.Diagnostics = null, // Filled with error details on failure. Optional.
};

/// POST /folder/uploadinfo : Returns an upload token and URL for direct file upload to a folder.
/// Two-step flow: call this endpoint to get a one-shot upload url and token, then POST your file to that url.
pub fn uploadInfo(self: Folder, opts: FolderUploadInfoOptions) !std.json.Parsed(types.FolderUploadInfo) {
    var buf: [1]Client.Param = undefined;
    var n: usize = 0;

    if (opts.id) |id| {
        buf[n] = .{ .name = "id", .value = id };
        n += 1;
    }

    return self.client.post(types.FolderUploadInfo, endpoints.folder.uploadinfo, buf[0..n], opts.diag);
}

pub const FolderSearchOptions = struct {
    q: []const u8, // Search query string.
    diag: ?*Client.Diagnostics = null, // Filled with error details on failure. Optional.
};

/// GET /folder/search : Searches for matching files and folders across the user's storage.
pub fn search(self: Folder, opts: FolderSearchOptions) !std.json.Parsed(types.FolderSearch) {
    return self.client.get(types.FolderSearch, endpoints.folder.search, &.{
        .{ .name = "q", .value = opts.q },
    }, opts.diag);
}

test "folder/list root" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","name":"My Files","content":[
        \\  {"id":"d1","name":"MyFolder","type":"folder","created_at":1700000000},
        \\  {"id":"f1","name":"video.mkv","type":"file","created_at":1700000001,"size":123456789,"mime_type":"video/x-matroska","link":"https://dl/x"}
        \\]}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.folder().list(.{});
    defer res.deinit();

    try srv.expectGet("GET /api/folder/list?apikey=test-key");
    try std.testing.expectEqual(@as(?[]const u8, null), res.value.folder_id);
    try std.testing.expectEqual(@as(usize, 2), res.value.content.len);
    try std.testing.expectEqual(types.ContentType.folder, res.value.content[0].type);
    try std.testing.expectEqual(types.ContentType.file, res.value.content[1].type);
    try std.testing.expectEqual(@as(?u64, null), res.value.content[0].size);
    try std.testing.expectEqual(@as(?u64, 123456789), res.value.content[1].size);
    try std.testing.expectEqualStrings("https://dl/x", res.value.content[1].link.?);
}

test "folder/list with id, path and breadcrumbs" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","name":"MyFolder","parent_id":"p1","folder_id":"d1",
        \\ "breadcrumbs":[{"id":"r","name":"My Files"},{"id":"p1","name":"Parent"},{"id":"d1","name":"MyFolder"}],
        \\ "content":[]}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.folder().list(.{ .id = "d1", .path = "Parent/MyFolder", .include_breadcrumbs = true });
    defer res.deinit();

    try srv.expectGet("GET /api/folder/list?apikey=test-key&id=d1&path=Parent%2FMyFolder&includebreadcrumbs=true");
    try std.testing.expectEqualStrings("d1", res.value.folder_id.?);
    try std.testing.expectEqual(@as(usize, 3), res.value.breadcrumbs.len);
    try std.testing.expectEqualStrings("Parent", res.value.breadcrumbs[1].name);
}

test "folder/create" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","id":"new1"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.folder().create(.{ .name = "My Folder", .parent_id = "p1" });
    defer res.deinit();

    try srv.expectPost("POST /api/folder/create?apikey=test-key", "parent_id=p1&name=My%20Folder");
    try std.testing.expectEqualStrings("new1", res.value.id);
}

test "folder/create in root" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","id":"new1"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.folder().create(.{ .name = "x" });
    defer res.deinit();

    try srv.expectPost("POST /api/folder/create?apikey=test-key", "name=x");
}

test "folder/rename" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    try c.folder().rename(.{ .id = "d1", .name = "New Name" });

    try srv.expectPost("POST /api/folder/rename?apikey=test-key", "id=d1&name=New%20Name");
}

test "folder/delete" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    try c.folder().delete(.{ .id = "d1" });

    try srv.expectPost("POST /api/folder/delete?apikey=test-key", "id=d1");
}

test "folder/paste" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    try c.folder().paste(.{ .id = "t1", .files = &.{ "f1", "f2" }, .folders = &.{"d1"} });

    try srv.expectPost("POST /api/folder/paste?apikey=test-key", "id=t1&files%5B%5D=f1&files%5B%5D=f2&folders%5B%5D=d1");
}

test "folder/paste requires files or folders" {
    var c = Client.init(std.testing.allocator, undefined, .{ .auth = .{ .api_key = mock.api_key } });
    try std.testing.expectError(error.InvalidArgument, c.folder().paste(.{ .id = "t1" }));
}

test "folder/uploadinfo" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","token":"tok","url":"https://up/x"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.folder().uploadInfo(.{ .id = "d1" });
    defer res.deinit();

    try srv.expectPost("POST /api/folder/uploadinfo?apikey=test-key", "id=d1");
    try std.testing.expectEqualStrings("tok", res.value.token);
    try std.testing.expectEqualStrings("https://up/x", res.value.url);
}

test "folder/uploadinfo to root" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","token":"tok","url":"https://up/x"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.folder().uploadInfo(.{});
    defer res.deinit();

    try srv.expectPost("POST /api/folder/uploadinfo?apikey=test-key", "");
}

test "folder/search" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","name":"Search Results","content":[
        \\  {"id":"f1","name":"video.mkv","type":"file","created_at":1700000000,"size":1,"mime_type":"video/x-matroska","link":"https://dl/x",
        \\   "directlink":"https://dl/x","stream_link":"https://dl/x","unpackable":false}
        \\]}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.folder().search(.{ .q = "my show & stuff" });
    defer res.deinit();

    try srv.expectGet("GET /api/folder/search?apikey=test-key&q=my%20show%20%26%20stuff");
    try std.testing.expectEqualStrings("Search Results", res.value.name);
    try std.testing.expectEqualStrings("video.mkv", res.value.content[0].name);
}
