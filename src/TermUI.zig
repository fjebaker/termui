const std = @import("std");

const TermInfo = std.os.linux.termios;
const tcgetattr = std.os.linux.tcgetattr;
const tcsetattr = std.os.linux.tcsetattr;

const TermUI = @This();

pub const Error = error{ SetAttrError, GetAttrError };

pub const Key = struct {
    pub const Tab = 9;
    pub const CtrlC = 3;
    pub const CtrlD = 4;
    pub const CtrlH = 8;
    pub const CtrlJ = 10;
    pub const CtrlK = 11;
    pub const CtrlL = 12;
    pub const CtrlN = 14;
    pub const Enter = 13;
    pub const Escape = 27;
    pub const Space = 32;
    pub const Backspace = 127;
};

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

pub const Writer = std.fs.File.Writer;
pub const BufferedWriter = std.io.BufferedWriter(4096, Writer);
pub const Reader = std.fs.File.Reader;

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

fn ControllerMixin(comptime Self: type) type {
    return struct {
        inline fn writeEscaped(s: Self, mod: usize, key: u8) !void {
            try s.writer().print("\x1b[{d}{c}", .{ mod, key });
        }
        /// Move the cursor up by `num` rows
        pub fn cursorUp(s: Self, num: usize) !void {
            try s.writeEscaped(num, ARROW_UP);
        }
        /// Move the cursor down by `num` rows
        pub fn cursorDown(s: Self, num: usize) !void {
            try s.writeEscaped(num, ARROW_DOWN);
        }
        /// Move the cursor right by `num` cols
        pub fn cursorRight(s: Self, num: usize) !void {
            try s.writeEscaped(num, ARROW_RIGHT);
        }
        /// Move the cursor left by `num` cols
        pub fn cursorLeft(s: Self, num: usize) !void {
            try s.writeEscaped(num, ARROW_LEFT);
        }
        /// Move the cursor to a specific column
        pub fn cursorToColumn(s: Self, col: usize) !void {
            try s.writeEscaped(col, CURSOR_COLUMN);
        }
        /// Enable or disable drawing the cursor
        pub fn setCursorVisible(s: Self, visible: bool) !void {
            if (visible) {
                try s.writer().writeAll(CURSOR_VISIBLE);
            } else {
                try s.writer().writeAll(CURSOR_HIDE);
            }
        }
        /// Formatted printing via the TUI's out TtyFd.
        pub fn print(s: Self, comptime fmt: []const u8, args: anytype) !void {
            try s.writer().print(fmt, args);
        }
        /// Clear the current line
        pub fn clearCurrentLine(s: Self) !void {
            try s.cursorToColumn(1);
            try s.writeEscaped(2, LINE_CLEAR);
        }
    };
}

pub const TtyFd = struct {
    file: std.fs.File,
    original: TermInfo,
    current: TermInfo,

    fn setTerm(handle: std.fs.File.Handle, term: TermInfo) !void {
        if (0 != tcsetattr(handle, .FLUSH, &term)) {
            return Error.SetAttrError;
        }
    }

    pub fn deinit(tf: *TtyFd) void {
        setTerm(tf.file.handle, tf.original) catch unreachable;
        tf.* = undefined;
    }

    pub fn init(file: std.fs.File) !TtyFd {
        var original: TermInfo = undefined;
        if (0 != tcgetattr(file.handle, &original)) {
            return Error.GetAttrError;
        }
        // original.lflag.ISIG = true;
        var current = original;

        // local: no echo, canonical mode, remove signals
        current.lflag.ECHO = false;
        current.lflag.ICANON = false;
        current.lflag.ISIG = false;
        // input: translate carriage return to newline
        current.iflag.ICRNL = false;

        // return read after each byte is sent
        current.cc[@intFromEnum(std.os.linux.V.MIN)] = 1;
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

in: TtyFd,
out: TtyFd,

pub const BufferedController = struct {
    const Self = @This();
    pub usingnamespace ControllerMixin(*Self);

    tui: TermUI,
    buffer: BufferedWriter,

    pub fn writer(s: *Self) BufferedWriter.Writer {
        return s.buffer.writer();
    }

    pub fn flush(s: *Self) !void {
        try s.buffer.flush();
    }
};

pub const Controller = struct {
    const Self = @This();
    pub usingnamespace ControllerMixin(Self);

    tui: TermUI,
    w: Writer,

    pub fn writer(s: Self) Writer {
        return s.w;
    }
};

/// Get an output controller for manipulating the output
pub fn controller(tui: TermUI) Controller {
    return .{ .tui = tui, .w = tui.writer() };
}

/// Get a buffered output controller for manipulating the output
pub fn bufferedController(tui: TermUI) BufferedController {
    return .{ .tui = tui, .buffer = tui.bufferedWriter() };
}

/// Get a writer to terminal output.
pub fn writer(tui: TermUI) Writer {
    return tui.out.file.writer();
}

/// Get a buffered writer that that must be flushed before content is written
/// to the screen. Useful for frames.
pub fn bufferedWriter(tui: TermUI) BufferedWriter {
    return std.io.bufferedWriter(tui.writer());
}

pub fn reader(tui: TermUI) std.fs.File.Reader {
    return tui.in.file.reader();
}

/// Blocks until next input is read. Returns the raw byte read.
pub fn nextInputByte(tui: TermUI) !u8 {
    const rdr = tui.reader();
    return try rdr.readByte();
}

/// Blocks until next input is read. Translates escaped keycodes.
pub fn nextInput(tui: TermUI) !Input {
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

/// Get terminal size
pub fn getSize(tui: *TermUI) !std.os.linux.winsize {
    return try tui.out.getSize();
}

pub fn init(
    stdin: std.fs.File,
    stdout: std.fs.File,
) !TermUI {
    var in = try TtyFd.init(stdin);
    errdefer in.deinit();
    var out = try TtyFd.init(stdout);
    errdefer out.deinit();
    return .{
        .in = in,
        .out = out,
    };
}

pub fn deinit(tui: *TermUI) void {
    tui.out.deinit();
    tui.in.deinit();
    tui.* = undefined;
}

/// Abstraction for displaying content in rows.
/// Row zero corresponds to the highest row on terminal screen.
pub const RowDisplay = struct {
    ctrl: BufferedController,
    max_rows: usize,
    current_row: usize = 0,

    /// Clear the entire row display of any content.
    pub fn clear(d: *RowDisplay, flush: bool) !void {
        const w = d.ctrl.writer();
        try d.moveToRow(0);
        for (0..d.max_rows - 1) |_| {
            try d.ctrl.clearCurrentLine();
            try w.writeByte('\n');
        }
        try d.ctrl.clearCurrentLine();
        d.current_row = d.max_rows - 1;
        if (flush) {
            try d.draw();
        }
    }

    pub fn draw(d: *RowDisplay) !void {
        try d.ctrl.flush();
    }

    /// Move the cursor to a specific row
    pub fn moveToRow(d: *RowDisplay, row: usize) !void {
        if (row > d.current_row) {
            // move cursor down
            try d.ctrl.cursorDown(row - d.current_row);
            d.current_row = row;
        } else if (row < d.current_row) {
            // move cursor up
            try d.ctrl.cursorUp(d.current_row - row);
            d.current_row = row;
        }
    }

    /// Move the cursor to the last row
    pub fn moveToEnd(d: *RowDisplay) !void {
        try d.moveToRow(d.max_rows - 1);
    }

    fn clearCurrentRow(d: *RowDisplay) !void {
        try d.ctrl.clearCurrentLine();
    }

    /// Write a string to a specific row
    pub fn writeToRow(
        d: *RowDisplay,
        row: usize,
        text: []const u8,
    ) !void {
        const w = try d.rowWriter(row);
        try d.ctrl.cursorToColumn(0);
        try w.writeAll(text);
    }

    /// Write a string to the current row, clearing existing content first
    pub fn writeToRowC(
        d: *RowDisplay,
        row: usize,
        text: []const u8,
    ) !void {
        const w = try d.rowWriter(row);
        try d.clearCurrentRow();
        try w.writeAll(text);
    }

    /// Print to the current row
    pub fn printToRow(
        d: *RowDisplay,
        row: usize,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const w = try d.rowWriter(row);
        try d.ctrl.cursorToColumn(0);
        try w.print(fmt, args);
    }

    /// Print to the current row, clearing existing content first
    pub fn printToRowC(
        d: *RowDisplay,
        row: usize,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const w = try d.rowWriter(row);
        try d.clearCurrentRow();
        try w.print(fmt, args);
    }

    pub fn rowWriter(d: *RowDisplay, row: usize) !BufferedWriter.Writer {
        try d.moveToRow(row);
        return d.ctrl.writer();
    }
};

/// Return a `RowDisplay` wrapper for reserving a fixed number of lines of the
/// screen and drawing text into it.
pub fn rowDisplay(tui: *TermUI, rows: usize) !RowDisplay {
    return .{ .ctrl = tui.bufferedController(), .max_rows = rows };
}
