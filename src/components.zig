const std = @import("std");

pub const TermUI = @import("TermUI.zig");
pub const Key = TermUI.Key;
pub const ctrl = Key.ctrl;

pub const ShowInput = struct {
    pub fn interact(tui: *TermUI) !void {
        const controller = tui.controller();

        try controller.writer().writeAll("Input:");

        try controller.setCursorVisible(false);

        while (true) {
            const inp = try tui.nextInputByte();
            switch (inp) {
                Key.controller('c'), Key.controller('d'), 'q' => break,
                else => {
                    try controller.writer().print(" {d}", .{inp});
                },
            }
        }

        try controller.writer().writeAll("\n");
        try controller.setCursorVisible(true);
    }
};

pub fn FormatFn(comptime T: type) type {
    return fn (T, *Selector, anytype, usize) anyerror!void;
}

pub const InputHandleOutcome = enum {
    /// Let the component handle input
    handle,
    /// Do not let the component handle input
    skip,
    /// Stop the interaction loop
    exit,
};

/// Input function should return true to continue the main display loop, or
/// false to stop.
pub fn InputFn(comptime T: type) type {
    return fn (T, *Selector, TermUI.Input) anyerror!InputHandleOutcome;
}

pub fn PredrawFn(comptime T: type) type {
    return fn (T, *Selector) anyerror!void;
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

        /// Padding rows above and below (useful for e.g. status messages)
        pad_above: usize = 0,
        pad_below: usize = 0,

        /// Show the cursor (user will have to place it).
        show_cursor: bool = false,
    };

    display: TermUI.RowDisplay,
    num_choices: usize,

    /// Index currently selected
    selection: usize = 0,

    /// User has made a selection
    selected: bool = false,

    /// Which column to park the cursor in
    cursor_column: usize = 0,

    // used to control overflowing the display
    scroll_offset: usize = 0,
    // used to buffer the top of the display when reversed
    row_offset: usize = 0,
    opts: Options,

    fn interactImpl(
        tui: *TermUI,
        ctx: anytype,
        comptime predraw: ?PredrawFn(@TypeOf(ctx)),
        comptime fmt: FormatFn(@TypeOf(ctx)),
        comptime input: ?InputFn(@TypeOf(ctx)),
        num_choices: usize,
        opts: Options,
    ) !?usize {
        var s = Selector{
            .display = try tui.rowDisplay(
                opts.max_rows + opts.pad_above + opts.pad_below,
            ),
            .num_choices = num_choices,
            .opts = opts,
        };
        try s.display.ctrl.setCursorVisible(opts.show_cursor);

        if (s.opts.reverse) {
            s.selection = s.num_choices - 1;
            s.scroll_offset = s.num_choices -| s.opts.max_rows;
            if (s.opts.max_rows > s.num_choices) {
                s.row_offset = s.opts.max_rows - (s.num_choices + 1);
            }
        }

        var writer = s.display.ctrl.writer();

        // setup the screen
        if (s.opts.newlines) {
            try writer.writeAll("\n");
        }
        try s.display.clear(false);

        if (predraw) |pd| try pd(ctx, &s);
        try s.redraw(ctx, fmt);

        // interaction loop
        while (try s.pollEvent()) |event| {
            // have to clear the display here as the user might have drawn to
            // the screen
            try s.display.clear(false);

            // let user handle the input first
            if (input) |inp| {
                switch (try inp(ctx, &s, event)) {
                    .exit => break,
                    .handle => {
                        if (!try s.handleInput(event)) break;
                    },
                    .skip => {},
                }
            } else {
                if (!try s.handleInput(event)) break;
            }

            if (predraw) |pd| try pd(ctx, &s);
            try s.redraw(ctx, fmt);
        }

        if (s.opts.clear) {
            try s.cleanup();
        }

        // restore the terminal look and feel
        try s.display.ctrl.setCursorVisible(true);
        try s.display.ctrl.flush();

        if (s.selected) {
            return s.getSelected();
        } else {
            return null;
        }
    }

    /// Get the index of the currently selected item
    pub fn getSelected(s: *const Selector) usize {
        return if (s.opts.reverse)
            s.num_choices - (s.selection + 1)
        else
            s.selection;
    }

    pub fn interactAlt(
        tui: *TermUI,
        ctx: anytype,
        comptime predraw: ?PredrawFn(@TypeOf(ctx)),
        comptime fmt: FormatFn(@TypeOf(ctx)),
        comptime input: InputFn(@TypeOf(ctx)),
        num_choices: usize,
        opts: Options,
    ) !?usize {
        return try interactImpl(
            tui,
            ctx,
            predraw,
            fmt,
            input,
            num_choices,
            opts,
        );
    }

    pub fn interactFmt(
        tui: *TermUI,
        ctx: anytype,
        comptime fmt: FormatFn(@TypeOf(ctx)),
        num_choices: usize,
        opts: Options,
    ) !?usize {
        return try interactImpl(
            tui,
            ctx,
            null,
            fmt,
            null,
            num_choices,
            opts,
        );
    }

    /// Given a list of choices, display them to the user and return the choice
    /// that they selected, or null otherwise. For more fine control over how
    /// the selector is displayed, use `interactFmt`.
    pub fn interact(tui: *TermUI, choices: []const []const u8, opts: Options) !?usize {
        const ChoiceWrapper = struct {
            choices: []const []const u8,

            pub fn write(
                self: @This(),
                _: *Selector,
                writer: anytype,
                index: usize,
            ) anyerror!void {
                try writer.writeAll(self.choices[index]);
            }
        };

        const cw: ChoiceWrapper = .{ .choices = choices };
        return try interactFmt(tui, cw, ChoiceWrapper.write, choices.len, opts);
    }

    fn redraw(s: *Selector, ctx: anytype, comptime fmt: FormatFn(@TypeOf(ctx))) !void {
        var writer = s.display.ctrl.writer();

        // loop over each row that we are drawing
        for (s.row_offset..s.opts.max_rows) |row| {
            try s.moveAndClear(row + s.opts.pad_above);
            // get the corresponding index to display
            const index = row + s.scroll_offset - s.row_offset;

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
                try fmt(ctx, s, writer, draw_index);
            }
        }

        try s.display.moveToEnd();
        try s.display.ctrl.cursorToColumn(s.cursor_column);
        try s.display.draw();
    }

    fn pollEvent(s: *Selector) !?TermUI.Input {
        return try s.display.ctrl.tui.nextInput();
    }

    fn handleInput(s: *Selector, input: TermUI.Input) !bool {
        switch (input) {
            .char => |c| switch (c) {
                Key.ctrl('c'),
                'q',
                => return false,
                Key.ctrl('d') => s.pageDown(),
                Key.ctrl('u') => s.pageUp(),
                Key.ctrl('j') => s.down(true),
                Key.ctrl('k') => s.up(true),
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

    /// Cap the selection to a given index.
    pub fn capSelection(s: *Selector, cap: usize) void {
        s.selection = @min(
            @max(s.selection, @max(s.num_choices - cap + 1, 1) - 1),
            s.num_choices - 1,
        );
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
