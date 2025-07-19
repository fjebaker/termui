const std = @import("std");
const termui = @import("termui");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tui = try termui.TermUI.init(
        std.fs.File.stdin(),
        std.fs.File.stdout(),
    );
    defer tui.deinit();

    // get information about the terminal
    const size = try tui.getSize();

    var writer = tui.writer();
    try writer.interface.print(
        "Terminal size: {d} x {d}\n",
        .{ size.col, size.row },
    );

    // try inputExample(&tui);
    try selectorExample(&tui);
    // try rowWriterExample(&tui);
}

fn rowWriterExample(tui: *termui.TermUI) !void {
    var rows = try tui.rowDisplay(10);
    try rows.clear(true);

    try rows.writeToRowC(4, "4 Hello World");
    try rows.writeToRowC(2, "2 Hello World");
    try rows.writeToRowC(0, "0 Hello World");
    try rows.writeToRowC(9, "9 Hello World");
    try rows.moveToEnd();

    try rows.draw();
    _ = try tui.nextInput();
    try rows.clear(true);

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
        "A",
        "B",
        "C",
        "D",
        "E",
        "F",
        "G",
        "H",
        "I",
        "J",
        "K",
        "L",
    };

    const choice = try termui.Selector.interact(
        tui,
        &options,
        .{ .clear = false, .max_rows = 5, .reverse = false },
    ) orelse return;
    try writer.interface.print("\nYou selected: {s}\n", .{options[choice]});
}
