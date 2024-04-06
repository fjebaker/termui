const std = @import("std");
const termui = @import("termui");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tui = try termui.TermUI.init(
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

    // try inputExample(&tui);
    // try selectorExample(&tui);
    try rowWriterExample(&tui);
}

fn rowWriterExample(tui: *termui.TermUI) !void {
    var rows = try tui.rowDisplay(10);
    try rows.clear();

    try rows.writeToRowC(4, "4 Hello World");
    try rows.writeToRowC(2, "2 Hello World");
    try rows.writeToRowC(0, "0 Hello World");
    try rows.writeToRowC(9, "9 Hello World");
    try rows.moveToEnd();

    try rows.draw();
    _ = try tui.nextInput();
    try rows.clear();

    try rows.writeToRowC(0, "0 Goobye World");
    try rows.writeToRowC(1, "1 Goobye World");
    try rows.writeToRowC(8, "8 Goobye World");
    try rows.moveToEnd();
    try rows.draw();

    _ = try tui.nextInput();
    try tui.writer().writeByte('\n');
}

fn inputExample(tui: *termui.TermUI) !void {
    try termui.ShowInput.interact(tui);
}

fn selectorExample(tui: *termui.TermUI) !void {
    var writer = tui.writer();

    const options = [_][]const u8{
        "Hello",
        "World",
        "These are the options",
    };

    const choice = try termui.Selector.interact(
        tui,
        &options,
        .{ .clear = false },
    );
    try writer.print("\nYou selected: {s}\n", .{options[choice]});
}
