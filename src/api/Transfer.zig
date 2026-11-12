const Transfer = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");

client: *Client,

pub const TransferCreateOptions = struct {
    src: []const u8, // A URI for the transfer (as a string) or a source file for the transfer (multipart upload)
    folder_id: ?[]const u8 = .{}, // Target folder. Optional
    password: ?[]const u8 = .{}, // Password for thr tranfer. Optional
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

pub const TransferDirectdlOptions = struct {
    src: []const u8, // Transfer source URL
};

/// POST /transfer/directdl
/// Generates direct download links from a transfer source without storing it in your cloud. The content array can hold one or many file entries
/// — a single hoster URL typically resolves to one file, while a magnet or torrent source resolves to every file inside the archive.
pub fn directdl(self: Transfer, opts: TransferDirectdlOptions) !std.json.Parsed(types.TransferDirectDl) {
    return self.client.post(types.TransferDirectDl, endpoints.transfer.directdl, .{.{ .name = "src", .value = opts.src }});
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
pub fn retry(self: Transfer, opts: TransferRetryOptions) !std.json.Parsed(types.TransferRetry) {
    return self.client.post(types.TransferRetry, endpoints.transfer.retry, &.{.{ .name = "id", .value = opts.id }});
}

pub const TransferDeleteOptions = struct {
    id: []const u8, // Transfer ID. Required.
};
/// POST /transfer/delete : Deletes a transfer record.
pub fn delete(self: Transfer, opts: TransferDeleteOptions) !std.json.Parsed(types.TransferDelete) {
    return self.client.post(types.TransferDelete, endpoints.transfer.delete, &.{.{ .name = "id", .value = opts.id }});
}

/// POST /transfer/clearfinished : Removes all finished transfers from the list.
pub fn clearfinished(self: Transfer) !std.json.Parsed(types.TransferClearFinished) {
    return self.client.post(types.TransferClearFinished, endpoints.transfer.clearfinished, &.{});
}
