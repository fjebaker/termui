const std = @import("std");
const termui = @import("termui");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    var tui = try termui.TermUI.init(
        alloc,
        std.io.getStdIn(),
        std.io.getStdOut(),
    );
    defer tui.deinit();

    // get information about the terminal
    const size = try tui.getSize();

    var writer = tui.writer();
    try writer.print(
        "Terminal size: {d} x {d}\n",
        .{ size.ws_col, size.ws_row },
    );

    const options = [_][]const u8{
        "Hello",
        "World",
        "These are the options",
    };

    var selector = termui.components.Selector.init(
        &tui,
        &options,
        .{ .clear = true },
    );
    const choice = try selector.interact();
    try tui.writer().print("You selected: {s}\n", .{options[choice]});
}
