//! Response types for the Premiumize API.

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
