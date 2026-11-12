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
