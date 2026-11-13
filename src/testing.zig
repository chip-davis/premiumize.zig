//! Test helpers. A local HTTP server that answers a fixed sequence of requests
//! with canned JSON bodies and records what it receives, so endpoints can be
//! tested end to end without touching the real API.
const std = @import("std");
const net = std.Io.net;
const Client = @import("Client.zig");

pub const api_key = "test-key";

pub const Reply = struct { status: u16 = 200, body: []const u8 };

pub const MockServer = struct {
    const max_requests = 8;

    allocator: std.mem.Allocator,
    io: std.Io,
    server: net.Server,
    port: u16,
    thread: std.Thread,
    replies: []const Reply,
    one: [1]Reply = undefined, // Backing for start()'s single reply.
    stop: std.atomic.Value(bool) = .init(false),
    req_buf: [16 * 1024]u8 = undefined, // First request, in full.
    req_len: usize = 0,
    target_buf: [max_requests][256]u8 = undefined, // Request line of each request.
    target_lens: [max_requests]usize = @splat(0),
    count: usize = 0, // Requests answered so far.
    url_buf: [64]u8 = undefined,
    base_url: []const u8 = "",

    /// Starts a server that answers exactly one request with `status` and `reply`.
    pub fn start(a: std.mem.Allocator, status: u16, reply: []const u8) !*MockServer {
        const self = try create(a);
        self.one = .{.{ .status = status, .body = reply }};
        self.replies = &self.one;
        return self.launch();
    }

    /// Starts a server that answers one request per reply, in order.
    /// `replies` must outlive the server.
    pub fn startSeq(a: std.mem.Allocator, replies: []const Reply) !*MockServer {
        std.debug.assert(replies.len <= max_requests);
        const self = try create(a);
        self.replies = replies;
        return self.launch();
    }

    /// Heap-allocated so the server thread's pointer stays valid.
    fn create(a: std.mem.Allocator) !*MockServer {
        const self = try a.create(MockServer);
        errdefer a.destroy(self);
        const io = std.testing.io;
        const addr = try net.IpAddress.parseIp4("127.0.0.1", 0);
        self.* = .{
            .allocator = a,
            .io = io,
            .server = try addr.listen(io, .{}),
            .port = undefined,
            .thread = undefined,
            .replies = &.{},
        };
        errdefer self.server.deinit(io);
        self.port = self.server.socket.address.getPort();
        self.base_url = try std.fmt.bufPrint(&self.url_buf, "http://127.0.0.1:{d}/api", .{self.port});
        return self;
    }

    fn launch(self: *MockServer) !*MockServer {
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch |e| {
            self.server.deinit(self.io);
            self.allocator.destroy(self);
            return e;
        };
        return self;
    }

    pub fn deinit(self: *MockServer) void {
        // Wake the acceptor in case the client stopped before using every reply.
        self.stop.store(true, .release);
        const addr = net.IpAddress.parseIp4("127.0.0.1", self.port) catch unreachable;
        if (addr.connect(self.io, .{ .mode = .stream })) |waker| waker.close(self.io) else |_| {}
        self.thread.join();
        self.server.deinit(self.io);
        self.allocator.destroy(self);
    }

    /// A Client pointed at this server, using API key auth.
    pub fn client(self: *MockServer) Client {
        return self.clientWithAuth(.{ .api_key = api_key });
    }

    pub fn clientWithAuth(self: *MockServer, auth: Client.Auth) Client {
        return Client.init(self.allocator, self.io, .{ .auth = auth, .base_url = self.base_url });
    }

    /// The raw request bytes. Only valid after the client call has returned.
    pub fn request(self: *const MockServer) []const u8 {
        return self.req_buf[0..self.req_len];
    }

    /// Request line of the first request without the trailing " HTTP/1.1", e.g. "GET /api/account/info?apikey=test-key".
    pub fn target(self: *const MockServer) []const u8 {
        return self.targetAt(0);
    }

    /// Request line of the i-th request (0-based). Empty if it never arrived.
    pub fn targetAt(self: *const MockServer, i: usize) []const u8 {
        return self.target_buf[i][0..self.target_lens[i]];
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
        var buf: [16 * 1024]u8 = undefined;
        for (self.replies, 0..) |reply, i| {
            const conn = self.server.accept(self.io) catch return;
            defer conn.close(self.io);
            if (self.stop.load(.acquire)) return;

            var len: usize = 0;
            while (len < buf.len) {
                var bufs = [_][]u8{buf[len..]};
                const n = conn.read(self.io, &bufs) catch return;
                if (n == 0) break;
                len += n;
                if (requestComplete(buf[0..len])) break;
            }
            const req = buf[0..len];
            if (i == 0) {
                @memcpy(self.req_buf[0..len], req);
                self.req_len = len;
            }
            const line = req[0 .. std.mem.indexOf(u8, req, "\r\n") orelse req.len];
            const t = line[0 .. std.mem.lastIndexOfScalar(u8, line, ' ') orelse line.len];
            const tn = @min(t.len, self.target_buf[i].len);
            @memcpy(self.target_buf[i][0..tn], t[0..tn]);
            self.target_lens[i] = tn;

            var head: [160]u8 = undefined;
            const h = std.fmt.bufPrint(&head, "HTTP/1.1 {d} Mock\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ reply.status, reply.body.len }) catch return;
            var wbuf: [1024]u8 = undefined;
            var w = conn.writer(self.io, &wbuf);
            w.interface.writeAll(h) catch return;
            w.interface.writeAll(reply.body) catch return;
            w.interface.flush() catch return;
            self.count = i + 1;
        }
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
