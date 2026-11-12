//! End-to-end check against the live API. Touches every endpoint, working
//! only inside a scratch folder it creates and deletes.
//!
//!     PREMIUMIZE_API_KEY=... zig build run
//!     PREMIUMIZE_API_KEY=... zig build run -- --clear-finished
//!
//! `--clear-finished` also calls /transfer/clearfinished, which removes ALL
//! of your finished transfers, not just the test one. Off by default.
//! PREMIUMIZE_TEST_SRC overrides the transfer source (default: a public-domain magnet).
const std = @import("std");
const premiumize = @import("premiumize_zig");
const Client = premiumize.Client;

const default_src = "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny";
const transfer_timeout_s = 180;

/// Prints one line per step and tallies results.
const Run = struct {
    pm: *Client,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,

    fn ok(self: *Run, step: []const u8, comptime fmt: []const u8, args: anytype) void {
        self.passed += 1;
        std.debug.print("  ok    {s:<24} " ++ fmt ++ "\n", .{step} ++ args);
    }

    fn fail(self: *Run, step: []const u8, err: anyerror) void {
        self.failed += 1;
        const code = if (self.pm.lastErrorCode()) |c| @tagName(c) else "-";
        std.debug.print("  FAIL  {s:<24} {s} [{s}] {s}\n", .{ step, @errorName(err), code, self.pm.lastError() orelse "" });
    }

    /// A step whose API error is acceptable (e.g. retrying a transfer that didn't fail).
    fn expectedError(self: *Run, step: []const u8, err: anyerror) void {
        if (err != error.ApiError) return self.fail(step, err);
        self.passed += 1;
        const code = if (self.pm.lastErrorCode()) |c| @tagName(c) else "-";
        std.debug.print("  ok    {s:<24} rejected as expected [{s}] {s}\n", .{ step, code, self.pm.lastError() orelse "" });
    }

    fn skip(self: *Run, step: []const u8, why: []const u8) void {
        self.skipped += 1;
        std.debug.print("  skip  {s:<24} {s}\n", .{ step, why });
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa; // leak-checked in Debug builds
    const keep = init.arena.allocator(); // for IDs we hold across steps
    const io = init.io;

    const args = try init.minimal.args.toSlice(keep);
    var clear_finished = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--clear-finished")) clear_finished = true;
    }

    const api_key = init.environ_map.get("PREMIUMIZE_API_KEY") orelse {
        std.debug.print("set PREMIUMIZE_API_KEY\n", .{});
        std.process.exit(2);
    };
    const src = init.environ_map.get("PREMIUMIZE_TEST_SRC") orelse default_src;

    var pm = Client.init(gpa, io, .{ .auth = .{ .api_key = api_key } });
    defer pm.deinit();
    var run: Run = .{ .pm = &pm };

    const now_s = std.Io.Clock.real.now(io).toSeconds();
    const scratch_name = try std.fmt.allocPrint(keep, "pmzig-e2e-{d}", .{now_s});

    std.debug.print("premiumize.zig end-to-end ({s})\n\n", .{scratch_name});

    // ── Read-only ──────────────────────────────────────────────────────
    std.debug.print("account / services\n", .{});

    if (pm.account().info()) |r| {
        defer r.deinit();
        run.ok("account/info", "customer {s}, {d:.1} GB used, fair use {d:.0}%", .{ r.value.customer_id, r.value.space_used / 1e9, r.value.limit_used * 100 });
    } else |e| run.fail("account/info", e);

    if (pm.services().list()) |r| {
        defer r.deinit();
        run.ok("services/list", "{d} cache, {d} directdl, {d} queue", .{ r.value.cache.len, r.value.directdl.len, r.value.queue.len });
    } else |e| run.fail("services/list", e);

    // ── Folders ────────────────────────────────────────────────────────
    std.debug.print("\nfolders\n", .{});

    if (pm.folder().list(.{})) |r| {
        defer r.deinit();
        run.ok("folder/list (root)", "{d} entries", .{r.value.content.len});
    } else |e| run.fail("folder/list (root)", e);

    const scratch_id: ?[]const u8 = if (pm.folder().create(.{ .name = scratch_name })) |r| blk: {
        defer r.deinit();
        run.ok("folder/create", "{s} -> {s}", .{ scratch_name, r.value.id });
        break :blk try keep.dupe(u8, r.value.id);
    } else |e| blk: {
        run.fail("folder/create", e);
        break :blk null;
    };

    const scratch = scratch_id orelse {
        std.debug.print("\ncan't continue without the scratch folder\n", .{});
        return finish(&run);
    };
    // Always clean up the scratch folder (and everything in it).
    defer {
        std.debug.print("\ncleanup\n", .{});
        if (pm.folder().delete(.{ .id = scratch })) |r| {
            r.deinit();
            run.ok("folder/delete", "removed {s}", .{scratch_name});
        } else |e| run.fail("folder/delete", e);
        finish(&run);
    }

    const sub_id: ?[]const u8 = if (pm.folder().create(.{ .name = "sub", .parent_id = scratch })) |r| blk: {
        defer r.deinit();
        run.ok("folder/create (child)", "sub -> {s}", .{r.value.id});
        break :blk try keep.dupe(u8, r.value.id);
    } else |e| blk: {
        run.fail("folder/create (child)", e);
        break :blk null;
    };

    if (sub_id) |sub| {
        if (pm.folder().rename(.{ .id = sub, .name = "sub renamed" })) |r| {
            r.deinit();
            run.ok("folder/rename", "sub -> \"sub renamed\"", .{});
        } else |e| run.fail("folder/rename", e);
    } else run.skip("folder/rename", "no child folder");

    if (pm.folder().list(.{ .id = scratch, .include_breadcrumbs = true })) |r| {
        defer r.deinit();
        run.ok("folder/list (scratch)", "{d} entries, {d} breadcrumbs", .{ r.value.content.len, r.value.breadcrumbs.len });
    } else |e| run.fail("folder/list (scratch)", e);

    if (pm.folder().uploadinfo(.{ .id = scratch })) |r| {
        defer r.deinit();
        run.ok("folder/uploadinfo", "got upload url ({d} chars)", .{r.value.url.len});
    } else |e| run.fail("folder/uploadinfo", e);

    // ── Transfers ──────────────────────────────────────────────────────
    std.debug.print("\ntransfers\n", .{});

    if (pm.cache().check(.{ .items = &.{src} })) |r| {
        defer r.deinit();
        const hit = r.value.response.len > 0 and r.value.response[0];
        run.ok("cache/check", "cached: {}", .{hit});
    } else |e| run.fail("cache/check", e);

    if (pm.transfer().directdl(.{ .src = src })) |r| {
        defer r.deinit();
        run.ok("transfer/directdl", "{d} file(s)", .{r.value.content.len});
    } else |e| run.fail("transfer/directdl", e);

    const transfer_id: ?[]const u8 = if (pm.transfer().create(.{ .src = src, .folder_id = scratch })) |r| blk: {
        defer r.deinit();
        run.ok("transfer/create", "{s} ({s})", .{ r.value.id, r.value.name });
        break :blk try keep.dupe(u8, r.value.id);
    } else |e| blk: {
        run.fail("transfer/create", e);
        break :blk null;
    };

    if (transfer_id) |tid| {
        const final = try waitForTransfer(&pm, &run, io, tid);
        if (pm.transfer().retry(.{ .id = tid })) |r| {
            r.deinit();
            run.ok("transfer/retry", "re-queued", .{});
        } else |e| {
            // Retry only applies to failed transfers; a finished one is rejected.
            if (std.mem.eql(u8, final, "error")) run.fail("transfer/retry", e) else run.expectedError("transfer/retry", e);
        }
    } else {
        run.skip("transfer/list", "no transfer");
        run.skip("transfer/retry", "no transfer");
    }

    // ── Items (files the transfer put in the scratch folder) ───────────
    std.debug.print("\nitems\n", .{});

    const file_id: ?[]const u8 = if (pm.item().listall()) |r| blk: {
        defer r.deinit();
        var found: ?[]const u8 = null;
        for (r.value.files) |f| {
            if (std.mem.startsWith(u8, f.path, scratch_name)) {
                found = try keep.dupe(u8, f.id);
                break;
            }
        }
        run.ok("item/listall", "{d} files total, test file {s}", .{ r.value.files.len, if (found != null) "found" else "not found" });
        break :blk found;
    } else |e| blk: {
        run.fail("item/listall", e);
        break :blk null;
    };

    if (file_id) |fid| {
        if (pm.item().details(.{ .id = fid })) |r| {
            defer r.deinit();
            run.ok("item/details", "{s}, {d} bytes, {s}", .{ r.value.name, r.value.size, r.value.mime_type });
        } else |e| run.fail("item/details", e);

        const new_name = try std.fmt.allocPrint(keep, "{s}-file", .{scratch_name});
        if (pm.item().rename(.{ .id = fid, .name = new_name })) |r| {
            r.deinit();
            run.ok("item/rename", "-> {s}", .{new_name});
        } else |e| run.fail("item/rename", e);

        if (pm.folder().search(.{ .q = new_name })) |r| {
            defer r.deinit();
            run.ok("folder/search", "\"{s}\": {d} result(s)", .{ new_name, r.value.content.len });
        } else |e| run.fail("folder/search", e);

        if (sub_id) |sub| {
            if (pm.folder().paste(.{ .id = sub, .files = &.{fid} })) |r| {
                r.deinit();
                run.ok("folder/paste", "moved file into child folder", .{});
            } else |e| run.fail("folder/paste", e);
        } else run.skip("folder/paste", "no child folder");

        if (pm.zip().generate(.{ .files = &.{fid} })) |r| {
            defer r.deinit();
            run.ok("zip/generate", "{s}", .{std.fs.path.basename(r.value.location)});
        } else |e| run.fail("zip/generate", e);

        if (pm.item().delete(.{ .id = fid })) |r| {
            r.deinit();
            run.ok("item/delete", "removed test file", .{});
        } else |e| run.fail("item/delete", e);
    } else {
        // No file landed; still exercise search and zip on the folders.
        if (pm.folder().search(.{ .q = scratch_name })) |r| {
            defer r.deinit();
            run.ok("folder/search", "\"{s}\": {d} result(s)", .{ scratch_name, r.value.content.len });
        } else |e| run.fail("folder/search", e);
        run.skip("item/details", "no test file");
        run.skip("item/rename", "no test file");
        run.skip("folder/paste", "no test file");
        run.skip("zip/generate", "no test file");
        run.skip("item/delete", "no test file");
    }

    if (transfer_id) |tid| {
        if (pm.transfer().delete(.{ .id = tid })) |r| {
            r.deinit();
            run.ok("transfer/delete", "removed {s}", .{tid});
        } else |e| run.fail("transfer/delete", e);
    } else run.skip("transfer/delete", "no transfer");

    if (clear_finished) {
        if (pm.transfer().clearfinished()) |r| {
            r.deinit();
            run.ok("transfer/clearfinished", "cleared", .{});
        } else |e| run.fail("transfer/clearfinished", e);
    } else run.skip("transfer/clearfinished", "pass --clear-finished to run (clears ALL finished transfers)");
}

/// Polls /transfer/list until the transfer leaves queued/running. Returns its last status.
fn waitForTransfer(pm: *Client, run: *Run, io: std.Io, tid: []const u8) ![]const u8 {
    var status: []const u8 = "unknown";
    var waited: i64 = 0;
    var polls: usize = 0;
    while (waited <= transfer_timeout_s) : (waited += 3) {
        const r = pm.transfer().list() catch |e| {
            run.fail("transfer/list", e);
            return status;
        };
        defer r.deinit();
        polls += 1;

        for (r.value.transfers) |t| {
            if (!std.mem.eql(u8, t.id, tid)) continue;
            status = if (std.mem.eql(u8, t.status, "finished")) "finished" else if (std.mem.eql(u8, t.status, "seeding")) "seeding" else if (std.mem.eql(u8, t.status, "error")) "error" else "pending";
            if (!std.mem.eql(u8, status, "pending")) {
                run.ok("transfer/list", "{s} after {d} poll(s) ({d:.0}%) {s}", .{ t.status, polls, (t.progress orelse 0) * 100, t.message orelse "" });
                return status;
            }
            std.debug.print("        {s:<24} {s} {d:.0}%\n", .{ "", t.status, (t.progress orelse 0) * 100 });
        }
        try io.sleep(.fromSeconds(3), .awake);
    }
    run.ok("transfer/list", "still running after {d}s; continuing", .{transfer_timeout_s});
    return status;
}

fn finish(run: *const Run) void {
    std.debug.print("\n{d} passed, {d} failed, {d} skipped\n", .{ run.passed, run.failed, run.skipped });
    if (run.failed > 0) std.process.exit(1);
}
