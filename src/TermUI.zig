const std = @import("std");

const TermUI = @This();

const TermInfo = std.os.termios;

const ESCAPE = 27; // escape code
const ARROW_UP = 'A';
const ARROW_DOWN = 'B';
const ARROW_RIGHT = 'C';
const ARROW_LEFT = 'D';

const CURSOR_COLUMN = 'G';
const CURSOR_HIDE = "\x1b[?25l";
const CURSOR_VISIBLE = "\x1b[?25h";

const LINE_CLEAR = 'K';

pub const TerminalError = error{IOCTLError};

pub const Input = union(enum) {
    char: u8,
    escaped: u8,
    Up,
    Down,
    Right,
    Left,

    pub fn translateEscaped(num: u8, c: u8) Input {
        _ = num;
        return switch (c) {
            ARROW_UP => .Up,
            ARROW_DOWN => .Down,
            ARROW_RIGHT => .Right,
            ARROW_LEFT => .Left,
            else => .{ .escaped = c },
        };
    }
};

pub const TtyFd = struct {
    file: std.fs.File,
    original: std.os.termios,
    current: std.os.termios,

    fn setTerm(handle: std.fs.File.Handle, term: std.os.termios) !void {
        try std.os.tcsetattr(handle, .FLUSH, term);
    }

    pub fn deinit(tf: *TtyFd) void {
        setTerm(tf.file.handle, tf.original) catch unreachable;
        tf.* = undefined;
    }

    pub fn init(file: std.fs.File) !TtyFd {
        const original = try std.os.tcgetattr(file.handle);
        var current = original;

        current.lflag &= ~@as(
            u32,
            // local: no echo, canonical mode, remove signals
            std.os.linux.ECHO | std.os.linux.ICANON | std.os.linux.ISIG,
        );
        current.iflag &= ~@as(
            u32,
            // input: translate carriage return to newline
            std.os.linux.ICRNL,
        );

        // return read after each byte is sent
        current.cc[std.os.linux.V.MIN] = 1;
        try setTerm(file.handle, current);

        return .{ .file = file, .original = original, .current = current };
    }

    pub fn getSize(tf: *const TtyFd) !std.os.linux.winsize {
        var size: std.os.linux.winsize = undefined;
        const ret_code = std.os.linux.ioctl(
            tf.file.handle,
            std.os.linux.T.IOCGWINSZ,
            @intFromPtr(&size),
        );
        if (ret_code == -1) return TerminalError.IOCTLError;
        return size;
    }
};

allocator: std.mem.Allocator,
in: TtyFd,
out: TtyFd,

fn writeEscaped(tui: *TermUI, mod: usize, key: u8) !void {
    try tui.print("\x1b[{d}{c}", .{ mod, key });
}

pub fn writer(tui: *TermUI) std.fs.File.Writer {
    return tui.out.file.writer();
}

pub fn reader(tui: *TermUI) std.fs.File.Reader {
    return tui.in.file.reader();
}

/// Blocks until next input is read. Translates escaped keycodes.
pub fn nextInput(tui: *TermUI) !Input {
    const rdr = tui.reader();
    const c = try rdr.readByte();
    switch (c) {
        ESCAPE => {
            const num = try rdr.readByte();
            const key = try rdr.readByte();
            return Input.translateEscaped(num, key);
        },
        else => return .{ .char = c },
    }
}

/// Formatted printing via the TUI's out TtyFd.
pub fn print(tui: *TermUI, comptime fmt: []const u8, args: anytype) !void {
    try tui.writer().print(fmt, args);
}

/// Get terminal size
pub fn getSize(tui: *TermUI) !std.os.linux.winsize {
    return try tui.out.getSize();
}

pub fn init(
    allocator: std.mem.Allocator,
    stdin: std.fs.File,
    stdout: std.fs.File,
) !TermUI {
    var in = try TtyFd.init(stdin);
    errdefer in.deinit();
    var out = try TtyFd.init(stdout);
    errdefer out.deinit();
    return .{
        .allocator = allocator,
        .in = in,
        .out = out,
    };
}

pub fn deinit(tui: *TermUI) void {
    tui.out.deinit();
    tui.in.deinit();
    tui.* = undefined;
}

// Cursor control

pub fn cursorUp(tui: *TermUI, num: usize) !void {
    try tui.writeEscaped(num, ARROW_UP);
}
pub fn cursorDown(tui: *TermUI, num: usize) !void {
    try tui.writeEscaped(num, ARROW_DOWN);
}
pub fn cursorRight(tui: *TermUI, num: usize) !void {
    try tui.writeEscaped(num, ARROW_RIGHT);
}
pub fn cursorLeft(tui: *TermUI, num: usize) !void {
    try tui.writeEscaped(num, ARROW_LEFT);
}
pub fn cursorToColumn(tui: *TermUI, col: usize) !void {
    try tui.writeEscaped(col, CURSOR_COLUMN);
}
pub fn setCursorVisible(tui: *TermUI, visible: bool) !void {
    if (visible) {
        try tui.writer().writeAll(CURSOR_VISIBLE);
    } else {
        try tui.writer().writeAll(CURSOR_HIDE);
    }
}

pub fn clearCurrentLine(tui: *TermUI) !void {
    try tui.cursorToColumn(1);
    try tui.writeEscaped(2, LINE_CLEAR);
}
