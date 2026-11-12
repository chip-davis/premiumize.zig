pub const Client = @import("Client.zig");
pub const types = @import("types.zig");

test {
    // Pull in tests from all files.
    @import("std").testing.refAllDecls(@This());
    _ = Client;
    // Type-check every endpoint, even ones nothing calls yet.
    @import("std").testing.refAllDecls(Client.Account);
    @import("std").testing.refAllDecls(Client.Folder);
    @import("std").testing.refAllDecls(Client.Item);
    @import("std").testing.refAllDecls(Client.Transfer);
    @import("std").testing.refAllDecls(Client.Cache);
}
