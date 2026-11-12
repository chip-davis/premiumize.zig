const Transfer = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
const mock = @import("../testing.zig");

client: *Client,

pub const TransferCreateOptions = struct {
    src: []const u8, // A URI for the transfer (as a string) or a source file for the transfer (multipart upload)
    folder_id: ?[]const u8 = null, // Target folder. Optional
    password: ?[]const u8 = null, // Password for thr tranfer. Optional
};

/// POST /transfer/create
/// If src is a container (.dlc / .ccf / .rsdf) the response is instead {"status":"success","type":"container","content":[...links...]} — submit the extracted links one by one.
/// (The container case is the only situation in which type carries a stable value; see Deprecated values.)
pub fn create(self: Transfer, opts: TransferCreateOptions) !std.json.Parsed(types.TransferCreate) {
    var buf: [3]Client.Param = undefined;
    var n: usize = 0;

    buf[n] = .{ .name = "src", .value = opts.src };
    n += 1;

    if (opts.folder_id) |id| {
        buf[n] = .{ .name = "folder_id", .value = id };
        n += 1;
    }

    if (opts.password) |pw| {
        buf[n] = .{ .name = "password", .value = pw };
        n += 1;
    }

    return self.client.post(types.TransferCreate, endpoints.transfer.create, buf[0..n]);
}

pub const TransferDirectDlOptions = struct {
    src: []const u8, // Transfer source URL
};

/// POST /transfer/directdl
/// Generates direct download links from a transfer source without storing it in your cloud. The content array can hold one or many file entries
/// — a single hoster URL typically resolves to one file, while a magnet or torrent source resolves to every file inside the archive.
pub fn directDl(self: Transfer, opts: TransferDirectDlOptions) !std.json.Parsed(types.TransferDirectDl) {
    return self.client.post(types.TransferDirectDl, endpoints.transfer.directdl, &.{.{ .name = "src", .value = opts.src }});
}

/// GET /transfer/list : Returns every transfer the user has created — active, queued, finished, and errored — newest first.
/// Responses are not cached; expect to poll while a transfer is running.
pub fn list(self: Transfer) !std.json.Parsed(types.TransferList) {
    return self.client.get(types.TransferList, endpoints.transfer.list, &.{});
}

pub const TransferRetryOptions = struct {
    id: []const u8, // Transfer ID. Required.
};
/// POST /transfer/retry : Re-queues a failed transfer.
pub fn retry(self: Transfer, opts: TransferRetryOptions) !void {
    return self.client.postOk(endpoints.transfer.retry, &.{.{ .name = "id", .value = opts.id }});
}

pub const TransferDeleteOptions = struct {
    id: []const u8, // Transfer ID. Required.
};
/// POST /transfer/delete : Deletes a transfer record.
pub fn delete(self: Transfer, opts: TransferDeleteOptions) !void {
    return self.client.postOk(endpoints.transfer.delete, &.{.{ .name = "id", .value = opts.id }});
}

/// POST /transfer/clearfinished : Removes all finished transfers from the list.
pub fn clearFinished(self: Transfer) !void {
    return self.client.postOk(endpoints.transfer.clearfinished, &.{});
}

test "transfer/create" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","id":"t1","name":"My.Transfer"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.transfer().create(.{ .src = "magnet:?xt=urn:btih:abc&dn=a b", .folder_id = "d1", .password = "pw" });
    defer res.deinit();

    try srv.expectPost("POST /api/transfer/create?apikey=test-key", "src=magnet%3A%3Fxt%3Durn%3Abtih%3Aabc%26dn%3Da%20b&folder_id=d1&password=pw");
    try std.testing.expectEqualStrings("t1", res.value.id);
    try std.testing.expectEqualStrings("My.Transfer", res.value.name);
}

test "transfer/create minimal" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","id":"t1","name":"x"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.transfer().create(.{ .src = "https://host/file" });
    defer res.deinit();

    try srv.expectPost("POST /api/transfer/create?apikey=test-key", "src=https%3A%2F%2Fhost%2Ffile");
}

test "transfer/directdl" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","content":[
        \\  {"path":"Folder/video1.mkv","size":123456789,"link":"https://dl/1"},
        \\  {"path":"Folder/video2.mkv","size":234567890,"link":"https://dl/2"}
        \\]}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.transfer().directDl(.{ .src = "https://host/file" });
    defer res.deinit();

    try srv.expectPost("POST /api/transfer/directdl?apikey=test-key", "src=https%3A%2F%2Fhost%2Ffile");
    try std.testing.expectEqual(@as(usize, 2), res.value.content.len);
    try std.testing.expectEqualStrings("https://dl/2", res.value.content[1].link);
    try std.testing.expectEqual(@as(u64, 234567890), res.value.content[1].size);
}

test "transfer/list" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","transfers":[
        \\  {"id":"t1","name":"video.mkv","status":"running","progress":0.42,"message":"Downloading from server",
        \\   "folder_id":null,"file_id":null,"created_at":1700000000,"src":"https://old","other_cloud_id":null},
        \\  {"id":"t2","name":"movie.mkv","status":"finished","progress":null,"message":"",
        \\   "folder_id":"d1","file_id":"f1","created_at":1700000000},
        \\  {"id":"t3","name":"q","status":"queued","progress":0,"message":null,"folder_id":null,"file_id":null,"created_at":1700000000}
        \\]}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    const res = try c.transfer().list();
    defer res.deinit();

    try srv.expectGet("GET /api/transfer/list?apikey=test-key");
    const t = res.value.transfers;
    try std.testing.expectEqual(@as(usize, 3), t.len);
    try std.testing.expectEqual(types.TransferStatus.running, t[0].status);
    try std.testing.expectEqual(types.TransferStatus.finished, t[1].status);
    try std.testing.expectEqual(types.TransferStatus.queued, t[2].status);
    try std.testing.expectEqual(@as(?f64, 0.42), t[0].progress);
    try std.testing.expectEqual(@as(?f64, null), t[1].progress);
    try std.testing.expectEqual(@as(?[]const u8, null), t[0].folder_id);
    try std.testing.expectEqualStrings("f1", t[1].file_id.?);
    try std.testing.expectEqual(@as(?[]const u8, null), t[2].message);
}

test "transfer/retry" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    try c.transfer().retry(.{ .id = "t1" });

    try srv.expectPost("POST /api/transfer/retry?apikey=test-key", "id=t1");
}

test "transfer/delete" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    try c.transfer().delete(.{ .id = "t1" });

    try srv.expectPost("POST /api/transfer/delete?apikey=test-key", "id=t1");
}

test "transfer/clearfinished" {
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    try c.transfer().clearFinished();

    try srv.expectPost("POST /api/transfer/clearfinished?apikey=test-key", "");
}
