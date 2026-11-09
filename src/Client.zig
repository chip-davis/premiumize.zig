const Client = @This();

const std = @import("std");
const httpx = @import("httpx");
const Allocator = std.mem.Allocator;

pub const Param = @typeInfo(@FieldType(httpx.client.requestPayload, "headers")).pointer.child;

pub const default_base_url = "https://www.premiumize.me/api";

pub const Auth = union(enum) { api_key: []const u8, access_token: []const u8 };

pub const Options = struct { auth: Auth, base_url: []const u8 = default_base_url, timeout_ms: u64 = 30_000 };

pub const Error = error{ ApiError, BadStatus, InvalidResponse };

allocator: Allocator,
http: httpx.Client,
options: Options,
err_buf: [256]u8 = undefined,
err_len: usize = 0,

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

pub fn account(self: *Client) Account {
    return .{ .client = self };
}

pub const Account = struct {
    client: *Client,

    pub const Info = struct {
        customer_id: []const u8,
        premium_unitil: ?i64 = null, // unix timestamp
        limit_used: f64 = 0, // fraction of fair-use limit        
        space_used: f64 = 0 // bytes
    };

    pub fn info(self: Account) !std.json.Parsed(Info) {
        return self.client.get(Info, "/account/info", &.{});
    }
};

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
    const a = self.allocator;

    const url = try std.mem.concat(a, u8, &.{self.options.base_url, path});
    defer a.free(url);

    var query: std.ArrayList(Param) = .empty;
    defer query.deinit(a);

    if (self.options.auth == .api_key)
        try query.append(a, .{.name="apikey", .value=self.options.auth.api_key});
    if (method == .GET) try query.appendSlice(a, params);

    const form: ?[]u8 = if (method == .GET) null else try formEncode(a, params);
    defer if (form) |f| a.free(f);

    const bearer: ?[]const u8 = switch (self.optios.auth) {
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
};

