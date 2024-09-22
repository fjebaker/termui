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
        /// Maximum number of selections to draw
        max_rows: usize = 10,
        /// Reverse the display of the selection (if true shows from bottom)
        reverse: bool = true,
    };

    display: TermUI.RowDisplay,
    num_choices: usize,
    /// Index currently selected
    selection: usize = 0,
    /// User has made a selection
    selected: bool = false,

    // used to control overflowing the display
    scroll_offset: usize = 0,
    opts: Options,

    pub fn interactFmt(
        tui: *TermUI,
        ctx: anytype,
        comptime fmt: FormatFn(@TypeOf(ctx)),
        num_choices: usize,
        opts: Options,
    ) !?usize {
        var s = Selector{
            .display = try tui.rowDisplay(opts.max_rows),
            .num_choices = num_choices,
            .opts = opts,
        };
        try s.display.ctrl.setCursorVisible(false);

        if (s.opts.reverse) {
            s.selection = s.num_choices - 1;
            s.scroll_offset = (s.num_choices - s.opts.max_rows);
        }

        var writer = s.display.ctrl.writer();

        // setup the screen
        if (s.opts.newlines) {
            try writer.writeAll("\n");
        }
        try s.redraw(ctx, fmt);

        // interaction loop
        while (try s.update()) {
            try s.redraw(ctx, fmt);
        }

        if (s.opts.clear) {
            try s.cleanup();
        }

        // restore the terminal look and feel
        try writer.writeAll("\n");
        try s.display.ctrl.clearCurrentLine();
        try s.display.ctrl.setCursorVisible(true);

        try s.display.ctrl.flush();

        if (s.selected) {
            return if (s.opts.reverse)
                s.num_choices - (s.selection + 1)
            else
                s.selection;
        } else {
            return null;
        }
    }

    /// Given a list of choices, display them to the user and return the choice
    /// that they selected, or null otherwise. For more fine control over how
    /// the selector is displayed, use `interactFmt`.
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
        try s.display.clear(false);

        var writer = s.display.ctrl.writer();

        // loop over each row that we are drawing
        for (0..s.opts.max_rows) |row| {
            try s.moveAndClear(row);
            // get the corresponding index to display
            const index = row + s.scroll_offset;

            if (index == s.selection) {
                try writer.writeAll(" > ");
            } else {
                try writer.writeAll("   ");
            }

            if (index < s.num_choices) {
                // draw in the reverse order
                const draw_index = if (s.opts.reverse)
                    s.num_choices - (index + 1)
                else
                    index;
                try fmt(ctx, writer, draw_index);
            }
        }

        try s.display.moveToEnd();
        try s.display.draw();
    }

    pub fn update(s: *Selector) !bool {
        switch (try s.display.ctrl.tui.nextInput()) {
            .char => |c| switch (c) {
                Key.CtrlC, 'q' => return false,
                Key.CtrlD => s.pageDown(),
                Key.CtrlU => s.pageUp(),
                Key.CtrlJ => s.down(true),
                Key.CtrlK => s.up(true),
                'j' => s.down(true),
                'k' => s.up(true),
                Key.Enter => {
                    s.selected = true;
                    return false;
                },
                else => {},
            },
            .Down => s.down(false),
            .Up => s.up(false),
            else => {},
        }
        return true;
    }

    /// Clear the display
    pub fn clear(s: *Selector, flush: bool) !void {
        try s.display.clear(flush);
    }

    /// Utility method to cleanup the screen
    pub fn cleanup(s: *Selector) !void {
        try s.clear(false);
        try s.display.moveToRow(0);
        try s.display.draw();
    }

    /// Move the cursor to a specific row and clear it
    fn moveAndClear(s: *Selector, row: usize) !void {
        try s.display.moveToRow(row);
        try s.display.ctrl.clearCurrentLine();
    }

    fn up(s: *Selector, vim: bool) void {
        if (vim and !s.opts.vim) return;
        s.selectUp();
    }

    fn down(s: *Selector, vim: bool) void {
        if (vim and !s.opts.vim) return;
        s.selectDown();
    }

    fn selectUp(s: *Selector) void {
        s.selection -|= 1;
        if (s.selection <= s.scroll_offset) {
            s.scroll_offset -|= 1;
        }
    }

    fn selectDown(s: *Selector) void {
        s.selection = @min(s.selection + 1, s.num_choices - 1);
        if (s.selection >= s.scroll_offset + s.opts.max_rows) {
            s.scroll_offset += 1;
        }
    }

    fn pageUp(s: *Selector) void {
        for (0..10) |_| {
            _ = s.selectUp();
        }
    }

    fn pageDown(s: *Selector) void {
        for (0..10) |_| {
            _ = s.selectDown();
        }
    }
};
