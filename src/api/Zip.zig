//! /zip/* endpoints. Get one with `client.zip()`.
const Zip = @This();

const std = @import("std");
const Client = @import("../Client.zig");
const types = @import("../types.zig");
const endpoints = @import("../endpoints.zig");
client: *Client,

/// At least one of files[] or folders[] is required.
pub const ZipGenerateOptions = struct {
    files: []const []const u8 = &.{}, // File IDs to include. Optional.
    folders: []const []const u8 = &.{}, // Folder IDs to include. Optional.
};

/// POST /zip/generate : Bundles selected files and folders into a single .zip download.
/// Synchronous: the location URL can be downloaded as soon as this returns. Fetch it with a single connection.
/// The filename is encoded in the location URL path (no Content-Disposition header).
pub fn generate(self: Zip, opts: ZipGenerateOptions) !std.json.Parsed(types.ZipGenerate) {
    if (opts.files.len == 0 and opts.folders.len == 0) return Client.Error.InvalidArgument;

    const a = self.client.allocator;
    var params: std.ArrayList(Client.Param) = .empty;
    defer params.deinit(a);

    try params.ensureTotalCapacity(a, opts.files.len + opts.folders.len);

    for (opts.files) |f| params.appendAssumeCapacity(.{ .name = "files[]", .value = f });
    for (opts.folders) |f| params.appendAssumeCapacity(.{ .name = "folders[]", .value = f });

    return self.client.post(types.ZipGenerate, endpoints.zip.generate, params.items);
}
