//! Response types for the Premiumize API.
const std = @import("std");
/// GET /account/info
pub const AccountInfo = struct {
    customer_id: []const u8,
    /// Unix timestamp; null when the account has no premium.
    premium_until: ?i64 = null,
    /// Fraction of the fair-use limit used, 0..1.
    limit_used: f64 = 0,
    /// Bytes of cloud storage used.
    space_used: f64 = 0,
};

/// GET /folder/list
pub const FolderList = struct {
    name: []const u8 = "",
    /// Null/absent for the root folder.
    parent_id: ?[]const u8 = null,
    folder_id: ?[]const u8 = null,
    breadcrumbs: []const Breadcrumb = &.{},
    content: []const Content = &.{},
};

pub const Breadcrumb = struct {
    id: ?[]const u8 = null,
    name: []const u8,
};

pub const Content = struct {
    id: []const u8,
    name: []const u8,
    /// "file" or "folder".
    type: []const u8,
    created_at: i64 = 0,
    // File-only fields; folders leave them out, so each needs a default.
    size: ?u64 = null,
    mime_type: ?[]const u8 = null,
    link: ?[]const u8 = null,
};

/// POST /folder/create
pub const FolderCreate = struct { id: []const u8 };

/// POST /folder/rename
pub const FolderRename = struct {};

/// POST /folder/delete
pub const FolderDelete = struct {};

/// POST /folder/paste
pub const FolderPaste = struct {};

/// POST /folder/uploadinfo
pub const FolderUploadInfo = struct { token: []const u8, url: []const u8 };

/// GET /folder/search
/// Folder entries always carry id, name, type, created_at.
/// File entries additionally carry size (bytes), mime_type, and link (download URL).
/// created_at is a Unix timestamp.
pub const FolderSearch = struct {
    name: []const u8 = "",
    content: []const Content = &.{},
};

/// GET /item/details
pub const ItemDetails = struct { id: []const u8, name: []const u8, size: u64, created_at: i64, folder_id: []const u8, mime_type: []const u8, link: []const u8 };

/// POST /item/rename
pub const ItemRename = struct {};

/// POST /item/delete
pub const ItemDelete = struct {};

/// GET /item/listall
pub const ItemListAll = struct {
    files: []const ItemFile = &.{},
};

pub const ItemFile = struct {
    id: []const u8,
    name: []const u8,
    path: []const u8, // full path from the root
    size: u64, // in bytes
    created_at: i64,
    mime_type: ?[]const u8 = null,
};

/// POST /transfer/create
pub const TransferCreate = struct { id: []const u8, name: []const u8 };

/// POST /transfer/directdl
pub const TransferDirectDl = struct {
    content: []const DirectDlFile = &.{},
};

pub const DirectDlFile = struct { path: []const u8, size: u64, link: []const u8 };

/// GET /transfer/list
pub const TransferList = struct {
    transfers: []const TransferEntry = &.{},
};

pub const TransferEntry = struct {
    id: []const u8,
    name: []const u8,
    status: []const u8, // one of queued, running, finished, seeding, error
    progress: f64, // 0.0 to 1.0
    message: []const u8 = "",
    folder_id: ?[]const u8 = null, // null until finished/seeding, or if routed to an external cloud
    file_id: ?[]const u8 = null, // null until finished, for multi-file sources, or if routed to an external cloud
    created_at: i64,
};

/// POST /transfer/retry
pub const TransferRetry = struct {};

/// POST /transfer/delete
pub const TransferDelete = struct {};

/// POST /transfer/clearfinished
pub const TransferClearFinished = struct {};

/// POST /cache/check
pub const CacheCheck = struct {
    response: []const bool = &.{},
    filename: []const ?[]const u8 = &.{},
    filesize: []const FileSize = &.{},
};

pub const FileSize = struct {
    bytes: u64,

    pub fn jsonParse(a: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !FileSize {
        _ = options;
        return switch (try source.nextAlloc(a, .alloc_if_needed)) {
            .number, .allocated_number, .string, .allocated_string => |s| .{
                .bytes = std.fmt.parseInt(u64, s, 10) catch return error.InvalidNumber,
            },
            .null => .{ .bytes = 0 },
            else => error.UnexpectedToken,
        };
    }
};

/// GET /services/list
/// Object fields keyed by service name use std.json.ArrayHashMap; read them via `.map.get(name)`.
pub const ServicesList = struct {
    cache: []const []const u8 = &.{}, // services usable with /cache/check
    directdl: []const []const u8 = &.{}, // services usable with /transfer/directdl
    queue: []const []const u8 = &.{}, // services usable with /transfer/create
    fairusefactor: std.json.ArrayHashMap(f64) = .{}, // per-service fair-use multiplier
    aliases: std.json.ArrayHashMap([]const []const u8) = .{}, // extra domains per service; best-effort
    regexpatterns: std.json.ArrayHashMap([]const []const u8) = .{}, // URL regexes per service; best-effort
};
