const std = @import("std");
const TermUI = @import("TermUI.zig");
const Key = TermUI.Key;

pub const ShowInput = struct {
    pub fn interact(tui: *TermUI) !void {
        const ctrl = tui.controller();

        try ctrl.writer().writeAll("Input:");

        try ctrl.setCursorVisible(false);

        while (true) {
            const inp = try tui.nextInputByte();
            switch (inp) {
                Key.CtrlC, Key.CtrlD, 'q' => break,
                else => {
                    try ctrl.writer().print(" {d}", .{inp});
                },
            }
        }

        try ctrl.writer().writeAll("\n");
        try ctrl.setCursorVisible(true);
    }
};

pub fn FormatFn(comptime T: type) type {
    return fn (T, anytype, usize) anyerror!void;
}

pub const Selector = struct {
    pub const Options = struct {
        /// Clear after drawing
        clear: bool = true,
        /// Enable vim keybindings for navigation
        vim: bool = true,
        /// Surround selection prompt with newlines
        newlines: bool = false,
    };

    ctrl: TermUI.BufferedController,
    num_choices: usize,
    selection: usize = 0,
    selected: bool = false,
    opts: Options,

    pub fn interactFmt(
        tui: *TermUI,
        ctx: anytype,
        comptime fmt: FormatFn(@TypeOf(ctx)),
        num_choices: usize,
        opts: Options,
    ) !?usize {
        var s = Selector{ .ctrl = tui.bufferedController(), .num_choices = num_choices, .opts = opts };
        try s.ctrl.setCursorVisible(false);

        var writer = s.ctrl.writer();

        // setup the screen
        if (s.opts.newlines) {
            try writer.writeAll("\n");
        }
        try s.redraw(ctx, fmt);

        // interaction loop
        while (try s.update()) {
            try s.ctrl.cursorUp(s.num_choices - 1);
            try s.redraw(ctx, fmt);
        }

        if (s.opts.clear) {
            const num = if (s.opts.newlines) s.num_choices + 1 else s.num_choices;
            for (0..num) |_| {
                try s.ctrl.clearCurrentLine();
                try s.ctrl.cursorUp(1);
            }
        }

        // restore the terminal look and feel
        try writer.writeAll("\n");
        try s.ctrl.clearCurrentLine();
        try s.ctrl.setCursorVisible(true);

        try s.ctrl.flush();

        if (s.selected) {
            return s.num_choices - 1 - s.selection;
        } else {
            return null;
        }
    }

    pub fn interact(tui: *TermUI, choices: []const []const u8, opts: Options) !?usize {
        const ChoiceWrapper = struct {
            choices: []const []const u8,

            pub fn write(self: @This(), writer: anytype, index: usize) anyerror!void {
                try writer.writeAll(self.choices[index]);
            }
        };

        const cw: ChoiceWrapper = .{ .choices = choices };
        return try interactFmt(tui, cw, ChoiceWrapper.write, choices.len, opts);
    }

    fn redraw(s: *Selector, ctx: anytype, comptime fmt: FormatFn(@TypeOf(ctx))) !void {
        var writer = s.ctrl.writer();

        for (0..s.num_choices) |index| {
            const choice = s.num_choices - 1 - index;
            try s.ctrl.clearCurrentLine();
            if (index == s.selection) {
                try writer.writeAll(" > ");
            } else {
                try writer.writeAll("   ");
            }
            try fmt(ctx, writer, choice);

            if (s.num_choices - 1 != index) {
                try writer.writeAll("\n");
            }
        }

        try s.ctrl.flush();
    }

    fn incrementSelection(s: *Selector) void {
        if (s.selection + 1 < s.num_choices) {
            s.selection += 1;
        }
    }

    fn decrementSelection(s: *Selector) void {
        if (s.selection > 0) {
            s.selection -= 1;
        }
    }

    pub fn update(s: *Selector) !bool {
        switch (try s.ctrl.tui.nextInput()) {
            .char => |c| switch (c) {
                Key.CtrlC, Key.CtrlD, 'q' => return false,
                'j' => if (s.opts.vim) s.incrementSelection(),
                'k' => if (s.opts.vim) s.decrementSelection(),
                Key.Enter => {
                    s.selected = true;
                    return false;
                },
                else => {},
            },
            .Down => s.incrementSelection(),
            .Up => s.decrementSelection(),
            else => {},
        }
        return true;
    }
};
