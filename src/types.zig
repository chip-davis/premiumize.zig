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
