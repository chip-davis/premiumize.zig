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
