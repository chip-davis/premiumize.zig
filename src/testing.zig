//! Test helpers. A one-shot local HTTP server that records the request it
//! receives and answers with a canned JSON body, so endpoints can be tested
//! end to end without touching the real API.
const std = @import("std");
const httpx = @import("httpx");
const tcp = httpx.tcp;
const Client = @import("Client.zig");

pub const api_key = "test-key";

pub const MockServer = struct {
    allocator: std.mem.Allocator,
    ctx: tcp.IoContext,
    listener: tcp.Listener,
    thread: std.Thread,
    status: u16,
    reply: []const u8,
    req_buf: [16 * 1024]u8 = undefined,
    req_len: usize = 0,
    url_buf: [64]u8 = undefined,
    base_url: []const u8 = "",

    /// Starts a server that answers exactly one request with `status` and `reply`.
    /// Heap-allocated so the server thread's pointer stays valid.
    pub fn start(a: std.mem.Allocator, status: u16, reply: []const u8) !*MockServer {
        const self = try a.create(MockServer);
        errdefer a.destroy(self);
        self.* = .{
            .allocator = a,
            .ctx = try tcp.IoContext.init(a),
            .listener = undefined,
            .thread = undefined,
            .status = status,
            .reply = reply,
        };
        errdefer self.ctx.deinit();
        self.listener = try tcp.Listener.bind(self.ctx.io, 0);
        errdefer self.listener.close(self.ctx.io);
        self.base_url = try std.fmt.bufPrint(&self.url_buf, "http://127.0.0.1:{d}/api", .{self.listener.localPort()});
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }

    pub fn deinit(self: *MockServer) void {
        // Wake the acceptor in case the client never connected.
        if (tcp.connect(self.ctx.io, "127.0.0.1", self.listener.localPort())) |s| {
            var waker = s;
            waker.close();
        } else |_| {}
        self.thread.join();
        self.listener.close(self.ctx.io);
        self.ctx.deinit();
        self.allocator.destroy(self);
    }

    /// A Client pointed at this server, using API key auth.
    pub fn client(self: *MockServer) Client {
        return self.clientWithAuth(.{ .api_key = api_key });
    }

    pub fn clientWithAuth(self: *MockServer, auth: Client.Auth) Client {
        return Client.init(self.allocator, self.ctx.io, .{ .auth = auth, .base_url = self.base_url, .timeout_ms = 5_000 });
    }

    /// The raw request bytes. Only valid after the client call has returned.
    pub fn request(self: *const MockServer) []const u8 {
        return self.req_buf[0..self.req_len];
    }

    /// Request line without the trailing " HTTP/1.1", e.g. "GET /api/account/info?apikey=test-key".
    pub fn target(self: *const MockServer) []const u8 {
        const req = self.request();
        const line = req[0 .. std.mem.indexOf(u8, req, "\r\n") orelse req.len];
        return line[0 .. std.mem.lastIndexOfScalar(u8, line, ' ') orelse line.len];
    }

    pub fn body(self: *const MockServer) []const u8 {
        const req = self.request();
        const end = std.mem.indexOf(u8, req, "\r\n\r\n") orelse return "";
        return req[end + 4 ..];
    }

    /// Case-insensitive search of the request headers.
    pub fn hasHeader(self: *const MockServer, name: []const u8, value: []const u8) bool {
        const req = self.request();
        const head = req[0 .. std.mem.indexOf(u8, req, "\r\n\r\n") orelse req.len];
        var lines = std.mem.splitSequence(u8, head, "\r\n");
        _ = lines.next(); // request line
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (!std.ascii.eqlIgnoreCase(line[0..colon], name)) continue;
            if (std.ascii.findIgnoreCase(line[colon + 1 ..], value) != null) return true;
        }
        return false;
    }

    pub fn expectGet(self: *const MockServer, expected_target: []const u8) !void {
        try std.testing.expectEqualStrings(expected_target, self.target());
        try std.testing.expectEqualStrings("", self.body());
    }

    pub fn expectPost(self: *const MockServer, expected_target: []const u8, expected_body: []const u8) !void {
        try std.testing.expectEqualStrings(expected_target, self.target());
        try std.testing.expectEqualStrings(expected_body, self.body());
        if (expected_body.len > 0)
            try std.testing.expect(self.hasHeader("content-type", "application/x-www-form-urlencoded"));
    }

    fn run(self: *MockServer) void {
        var conn = self.listener.accept(self.ctx.io) catch return;
        defer conn.close();
        conn.setReadTimeoutMs(5_000);
        while (self.req_len < self.req_buf.len) {
            const n = conn.read(self.req_buf[self.req_len..]) catch return;
            if (n == 0) break;
            self.req_len += n;
            if (requestComplete(self.req_buf[0..self.req_len])) break;
        }
        var head: [160]u8 = undefined;
        const h = std.fmt.bufPrint(&head, "HTTP/1.1 {d} Mock\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ self.status, self.reply.len }) catch return;
        conn.writeAll(h) catch return;
        conn.writeAll(self.reply) catch return;
    }

    fn requestComplete(req: []const u8) bool {
        const end = std.mem.indexOf(u8, req, "\r\n\r\n") orelse return false;
        var lines = std.mem.splitSequence(u8, req[0..end], "\r\n");
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (!std.ascii.eqlIgnoreCase(line[0..colon], "content-length")) continue;
            const len = std.fmt.parseInt(usize, std.mem.trim(u8, line[colon + 1 ..], " "), 10) catch return true;
            return req.len - (end + 4) >= len;
        }
        return true;
    }
};
