const Client = @This();

const std = @import("std");
const httpx = @import("httpx");
const Allocator = std.mem.Allocator;

pub const Param = @typeInfo(@FieldType(httpx.client.requestPayload, "headers")).pointer.child;

pub const default_base_url = "https://www.premiumize.me/api";

pub const Auth = union(enum) { api_key: []const u8, access_token: []const u8 };

pub const Options = struct { auth: Auth, base_url: []const u8 = default_base_url, timeout_ms: u64 = 30_000 };

pub const Error = error{ ApiError, BadStatus, InvalidResponse, InvalidArgument, Timeout, TransferNotFound };

/// The `code` field of an error response. Read it from `Diagnostics.code` after `error.ApiError`.
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

/// Error details for one call. Pass a pointer in an endpoint's options; reset at the start of the call, filled only on failure.
pub const Diagnostics = struct {
    code: ?ErrorCode = null, // Set on ApiError (when the response has one) and BadStatus.
    buf: [256]u8 = undefined,
    len: usize = 0,

    pub fn message(self: *const Diagnostics) ?[]const u8 {
        return if (self.len == 0) null else self.buf[0..self.len];
    }

    fn set(self: *Diagnostics, code: ?ErrorCode, msg: []const u8) void {
        self.code = code;
        self.len = @min(msg.len, self.buf.len);
        @memcpy(self.buf[0..self.len], msg[0..self.len]);
    }
};

allocator: Allocator,
io: std.Io,
http: httpx.Client,
options: Options,

pub fn init(allocator: Allocator, io: std.Io, options: Options) Client {
    return .{
        .allocator = allocator,
        .io = io,
        .http = httpx.Client.init(allocator, io, .{}),
        .options = options,
    };
}

pub fn deinit(self: *Client) void {
    self.http.deinit();
    self.* = undefined;
}

pub fn get(self: *Client, comptime T: type, path: []const u8, params: []const Param, diag: ?*Diagnostics) !std.json.Parsed(T) {
    return self.call(T, .GET, path, params, diag);
}

pub fn post(self: *Client, comptime T: type, path: []const u8, params: []const Param, diag: ?*Diagnostics) !std.json.Parsed(T) {
    return self.call(T, .POST, path, params, diag);
}

/// POST for endpoints that only return {"status":"success"}.
pub fn postOk(self: *Client, path: []const u8, params: []const Param, diag: ?*Diagnostics) !void {
    const res = try self.call(struct {}, .POST, path, params, diag);
    res.deinit();
}

fn call(
    self: *Client,
    comptime T: type,
    method: httpx.Method,
    path: []const u8,
    params: []const Param,
    diag: ?*Diagnostics,
) !std.json.Parsed(T) {
    if (diag) |d| d.* = .{};
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

    return self.decode(T, res.status, res.bytes(), diag);
}

fn decode(self: *Client, comptime T: type, status: u16, body: []const u8, diag: ?*Diagnostics) !std.json.Parsed(T) {
    const Envelope = struct { status: []const u8 = "", message: ?[]const u8 = null, code: ?[]const u8 = null };

    const env = std.json.parseFromSlice(Envelope, self.allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch |e| switch (e) {
        error.OutOfMemory => return e,
        else => {
            if (status / 100 == 2) return error.InvalidResponse;
            // Non-JSON failure outside the normal envelope.
            if (diag) |d| d.set(.unknown_error, "");
            return error.BadStatus;
        },
    };
    defer env.deinit();

    if (!std.mem.eql(u8, env.value.status, "success")) {
        const msg = env.value.message orelse "unknown error";
        const code: ?ErrorCode = if (env.value.code) |c| std.meta.stringToEnum(ErrorCode, c) orelse .unknown_error else null;
        if (diag) |d| d.set(code, msg);
        return error.ApiError;
    }

    return std.json.parseFromSlice(T, self.allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch |e| switch (e) {
        error.OutOfMemory => e,
        else => {
            // e.g. "UnexpectedToken at byte 123: ...\"progress\":null..."
            var buf: [256]u8 = undefined;
            const msg = formatParseError(T, self.allocator, e, body, &buf);
            if (diag) |d| d.set(null, msg);
            return error.InvalidResponse;
        },
    };
}

/// Re-parses with diagnostics enabled to report where the body stopped matching T.
/// Writes the message into `buf` and returns it.
fn formatParseError(comptime T: type, a: Allocator, err: anyerror, body: []const u8, buf: []u8) []const u8 {
    var diag: std.json.Scanner.Diagnostics = .{};
    var scanner = std.json.Scanner.initCompleteInput(a, body);
    defer scanner.deinit();
    scanner.enableDiagnostics(&diag);
    if (std.json.parseFromTokenSource(T, a, &scanner, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    })) |p| p.deinit() else |_| {}

    const off: usize = @intCast(@min(diag.getByteOffset(), body.len));
    const snippet = body[off -| 60..@min(body.len, off + 20)];
    return std.fmt.bufPrint(buf, "{s} at byte {d}: ...{s}...", .{ @errorName(err), off, snippet }) catch @errorName(err);
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
    var c: Client = .{ .allocator = std.testing.allocator, .io = std.testing.io, .http = undefined, .options = .{ .auth = .{ .api_key = "" } } };
    const T = struct {};
    var d: Diagnostics = .{};

    try std.testing.expectError(error.ApiError, c.decode(T, 200,
        \\{"status":"error","code":"rate_limit_reached","message":"slow down"}
    , &d));
    try std.testing.expectEqual(ErrorCode.rate_limit_reached, d.code.?);
    try std.testing.expectEqual(ErrorCode.Retry.semi_permanent, d.code.?.retry());
    try std.testing.expectEqualStrings("slow down", d.message().?);

    // Unrecognised code falls back to unknown_error.
    try std.testing.expectError(error.ApiError, c.decode(T, 200,
        \\{"status":"error","code":"brand_new_code","message":"x"}
    , &d));
    try std.testing.expectEqual(ErrorCode.unknown_error, d.code.?);

    // HTTP 500 with a non-JSON body.
    d = .{};
    try std.testing.expectError(error.BadStatus, c.decode(T, 500, "Internal Server Error", &d));
    try std.testing.expectEqual(ErrorCode.unknown_error, d.code.?);
    try std.testing.expectEqual(@as(?[]const u8, null), d.message());
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

test "access_token auth sends a bearer header and no apikey" {
    const mock = @import("testing.zig");
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","customer_id":"1"}
    );
    defer srv.deinit();
    var c = srv.clientWithAuth(.{ .access_token = "tok123" });
    defer c.deinit();

    const res = try c.account().info(.{});
    defer res.deinit();

    try srv.expectGet("GET /api/account/info");
    try std.testing.expect(srv.hasHeader("authorization", "Bearer tok123"));
}

test "api error end to end" {
    const mock = @import("testing.zig");
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"error","code":"authentication_failed","message":"API key invalid"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    var d: Diagnostics = .{};
    try std.testing.expectError(error.ApiError, c.account().info(.{ .diag = &d }));
    try std.testing.expectEqual(ErrorCode.authentication_failed, d.code.?);
    try std.testing.expectEqual(ErrorCode.Retry.permanent, d.code.?.retry());
    try std.testing.expectEqualStrings("API key invalid", d.message().?);
}

test "response that doesn't match the type is InvalidResponse" {
    const mock = @import("testing.zig");
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    // AccountInfo requires customer_id.
    var d: Diagnostics = .{};
    try std.testing.expectError(error.InvalidResponse, c.account().info(.{ .diag = &d }));
    try std.testing.expect(std.mem.startsWith(u8, d.message().?, "MissingField"));
    try std.testing.expectEqual(@as(?ErrorCode, null), d.code);
}

test "http 500 is BadStatus with unknown_error" {
    const mock = @import("testing.zig");
    const srv = try mock.MockServer.start(std.testing.allocator, 500, "Internal Server Error");
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    var d: Diagnostics = .{};
    try std.testing.expectError(error.BadStatus, c.account().info(.{ .diag = &d }));
    try std.testing.expectEqual(ErrorCode.unknown_error, d.code.?);
}

test "diagnostics reset at the start of a call" {
    const mock = @import("testing.zig");
    const srv = try mock.MockServer.start(std.testing.allocator, 200,
        \\{"status":"success","customer_id":"1"}
    );
    defer srv.deinit();
    var c = srv.client();
    defer c.deinit();

    // Pretend a previous call failed.
    var d: Diagnostics = .{};
    d.set(.not_found, "stale");

    const res = try c.account().info(.{ .diag = &d });
    defer res.deinit();
    try std.testing.expectEqual(@as(?ErrorCode, null), d.code);
    try std.testing.expectEqual(@as(?[]const u8, null), d.message());
}

test "parse errors report where the body stopped matching" {
    var c: Client = .{ .allocator = std.testing.allocator, .io = std.testing.io, .http = undefined, .options = .{ .auth = .{ .api_key = "" } } };
    const T = struct { name: []const u8, size: u64 };
    var d: Diagnostics = .{};
    try std.testing.expectError(error.InvalidResponse, c.decode(T, 200,
        \\{"status":"success","name":null,"size":1}
    , &d));
    const msg = d.message().?;
    try std.testing.expect(std.mem.startsWith(u8, msg, "UnexpectedToken at byte "));
    try std.testing.expect(std.mem.indexOf(u8, msg, "\"name\":null") != null);
}
