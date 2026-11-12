pub const Client = @import("Client.zig");
pub const types = @import("types.zig");

test {
    // Pull in tests from all files.
    @import("std").testing.refAllDecls(@This());
    _ = Client;
    _ = @import("api/Account.zig");
    _ = @import("api/Folder.zig");
}
