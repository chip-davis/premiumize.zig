const Client = @This();

const std = @import("std");
const httpx = @import("httpx");
const Allocator = std.mem.Allocator;

pub const Param = @typeInfo(@FieldType(httpx.client.requestPayload, "headers")).pointer.child;

pub const default_base_url = "https://www.premiumize.me/api";

pub const Auth = union(enum) { api_key: []const u8, access_token: []const u8 };

pub const Options = struct { auth: Auth, base_url: []const u8 = default_base_url, timeout_ms: u64 = 30_000 };

pub const Error = error{ ApiError, BadStatus, InvalidResponse, InvalidArgument };

/// The `code` field of an error response. Read it with `lastErrorCode()` after `error.ApiError`.
pub const ErrorCode = enum {
    // Transient — retry now may succeed
    link_generation_failed,
    transient_error,
    // Semi-permanent — wait, raise quota, or upgrade, then retry
    service_down,
    service_limit_reached,
    account_limit_reached,
    rate_limit_reached,
    semi_permanent_error,
    // Permanent — same request will keep failing
    service_unsupported,
    not_found,
    authentication_failed,
    permission_denied,
    invalid_request,
    permanent_error,
    // Unknown — catastrophic failure outside the normal envelope (HTTP 500). Also used for codes this library doesn't know yet.
    unknown_error,

    pub const Retry = enum { transient, semi_permanent, permanent, unknown };

    pub fn retry(self: ErrorCode) Retry {
        return switch (self) {
            .link_generation_failed, .transient_error => .transient,
            .service_down, .service_limit_reached, .account_limit_reached, .rate_limit_reached, .semi_permanent_error => .semi_permanent,
            .service_unsupported, .not_found, .authentication_failed, .permission_denied, .invalid_request, .permanent_error => .permanent,
            .unknown_error => .unknown,
        };
    }
};

allocator: Allocator,
http: httpx.Client,
options: Options,
err_buf: [256]u8 = undefined,
err_len: usize = 0,
err_code: ?ErrorCode = null,

pub fn init(allocator: Allocator, io: std.Io, options: Options) Client {
    return .{
        .allocator = allocator,
        .http = httpx.Client.init(allocator, io, .{}),
        .options = options,
    };
}

pub fn deinit(self: *Client) void {
    self.http.deinit();
    self.* = undefined;
}

pub fn lastError(self: *const Client) ?[]const u8 {
    return if (self.err_len == 0) null else self.err_buf[0..self.err_len];
}

/// Code from the most recent error.ApiError or error.BadStatus. Null when the response had no code. Not thread-safe.
pub fn lastErrorCode(self: *const Client) ?ErrorCode {
    return self.err_code;
}

pub fn get(self: *Client, comptime T: type, path: []const u8, params: []const Param) !std.json.Parsed(T) {
    return self.call(T, .GET, path, params);
}

pub fn post(self: *Client, comptime T: type, path: []const u8, params: []const Param) !std.json.Parsed(T) {
    return self.call(T, .POST, path, params);
}

fn call(
    self: *Client,
    comptime T: type,
    method: httpx.Method,
    path: []const u8,
    params: []const Param,
) !std.json.Parsed(T) {
    self.err_len = 0;
    self.err_code = null;
    const a = self.allocator;

    const url = try std.mem.concat(a, u8, &.{ self.options.base_url, path });
    defer a.free(url);

    var query: std.ArrayList(Param) = .empty;
    defer query.deinit(a);

    if (self.options.auth == .api_key)
        try query.append(a, .{ .name = "apikey", .value = self.options.auth.api_key });
    if (method == .GET) try query.appendSlice(a, params);

    const form: ?[]u8 = if (method == .GET) null else try formEncode(a, params);
    defer if (form) |f| a.free(f);

    const bearer: ?[]const u8 = switch (self.options.auth) {
        .access_token => |t| t,
        .api_key => null,
    };

    var res = try self.http.fetch(url, .{
        .method = method,
        .query = query.items,
        .form = form,
        .bearerAuth = bearer,
        .timeoutMs = self.options.timeout_ms,
    });
    defer res.deinit();

    return self.decode(T, res.status, res.bytes());
}

fn decode(self: *Client, comptime T: type, status: u16, body: []const u8) !std.json.Parsed(T) {
    const Envelope = struct { status: []const u8 = "", message: ?[]const u8 = null, code: ?[]const u8 = null };

    const env = std.json.parseFromSlice(Envelope, self.allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch |e| switch (e) {
        error.OutOfMemory => return e,
        else => {
            if (status / 100 == 2) return error.InvalidResponse;
            // Non-JSON failure outside the normal envelope.
            self.err_code = .unknown_error;
            return error.BadStatus;
        },
    };
    defer env.deinit();

    if (!std.mem.eql(u8, env.value.status, "success")) {
        self.setError(env.value.message orelse "unknown error");
        if (env.value.code) |c| self.err_code = std.meta.stringToEnum(ErrorCode, c) orelse .unknown_error;
        return error.ApiError;
    }

    return std.json.parseFromSlice(T, self.allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch |e| switch (e) {
        error.OutOfMemory => e,
        else => {
            // e.g. "MissingField", "Overflow", "UnexpectedToken"
            self.setError(@errorName(e));
            return error.InvalidResponse;
        },
    };
}

fn setError(self: *Client, msg: []const u8) void {
    self.err_len = @min(msg.len, self.err_buf.len);
    @memcpy(self.err_buf[0..self.err_len], msg[0..self.err_len]);
}

fn formEncode(a: Allocator, params: []const Param) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    for (params, 0..) |p, i| {
        if (i != 0) try out.append(a, '&');
        try percentEncode(a, &out, p.name);
        try out.append(a, '=');
        try percentEncode(a, &out, p.value);
    }
    return out.toOwnedSlice(a);
}

fn percentEncode(a: Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => try out.append(a, c),
        else => try out.print(a, "%{X:0>2}", .{c}),
    };
}

// Endpoint namespaces (src/api/*.zig)

pub const Account = @import("api/Account.zig");

pub fn account(self: *Client) Account {
    return .{ .client = self };
}

pub const Folder = @import("api/Folder.zig");

pub fn folder(self: *Client) Folder {
    return .{ .client = self };
}

pub const Item = @import("api/Item.zig");

pub fn item(self: *Client) Item {
    return .{ .client = self };
}

pub const Transfer = @import("api/Transfer.zig");

pub fn transfer(self: *Client) Transfer {
    return .{ .client = self };
}

pub const Cache = @import("api/Cache.zig");

pub fn cache(self: *Client) Cache {
    return .{ .client = self };
}

pub const Services = @import("api/Services.zig");

pub fn services(self: *Client) Services {
    return .{ .client = self };
}

pub const Zip = @import("api/Zip.zig");

pub fn zip(self: *Client) Zip {
    return .{ .client = self };
}

test "decode maps error codes" {
    var c: Client = .{ .allocator = std.testing.allocator, .http = undefined, .options = .{ .auth = .{ .api_key = "" } } };
    const T = struct {};

    try std.testing.expectError(error.ApiError, c.decode(T, 200,
        \\{"status":"error","code":"rate_limit_reached","message":"slow down"}
    ));
    try std.testing.expectEqual(ErrorCode.rate_limit_reached, c.lastErrorCode().?);
    try std.testing.expectEqual(ErrorCode.Retry.semi_permanent, c.lastErrorCode().?.retry());
    try std.testing.expectEqualStrings("slow down", c.lastError().?);

    // Unrecognised code falls back to unknown_error.
    try std.testing.expectError(error.ApiError, c.decode(T, 200,
        \\{"status":"error","code":"brand_new_code","message":"x"}
    ));
    try std.testing.expectEqual(ErrorCode.unknown_error, c.lastErrorCode().?);

    // HTTP 500 with a non-JSON body.
    try std.testing.expectError(error.BadStatus, c.decode(T, 500, "Internal Server Error"));
    try std.testing.expectEqual(ErrorCode.unknown_error, c.lastErrorCode().?);
}

test formEncode {
    const a = std.testing.allocator;
    const s = try formEncode(a, &.{
        .{ .name = "src", .value = "magnet:?xt=urn:btih:abc&dn=a b" },
        .{ .name = "folder_id", .value = "123" },
    });
    defer a.free(s);
    try std.testing.expectEqualStrings(
        "src=magnet%3A%3Fxt%3Durn%3Abtih%3Aabc%26dn%3Da%20b&folder_id=123",
        s,
    );
}
