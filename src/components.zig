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
    choices: []const []const u8,
    selection: usize = 0,
    opts: Options,

    pub fn interact(tui: *TermUI, choices: []const []const u8, opts: Options) !usize {
        var s = Selector{ .ctrl = tui.bufferedController(), .choices = choices, .opts = opts };
        try s.ctrl.setCursorVisible(false);

        var writer = s.ctrl.writer();

        // setup the screen
        if (s.opts.newlines) {
            try writer.writeAll("\n");
        }
        try s.redraw();

        // interaction loop
        while (try s.update()) {
            try s.ctrl.cursorUp(s.choices.len - 1);
            try s.redraw();
        }

        if (s.opts.clear) {
            const num = if (s.opts.newlines) s.choices.len + 1 else s.choices.len;
            try s.ctrl.cursorUp(num);
        }

        // restore the terminal look and feel
        try writer.writeAll("\n");
        try s.ctrl.clearCurrentLine();
        try s.ctrl.setCursorVisible(true);

        try s.ctrl.flush();

        return s.choices.len - 1 - s.selection;
    }

    fn redraw(s: *Selector) !void {
        var writer = s.ctrl.writer();

        for (0..s.choices.len) |index| {
            const choice = s.choices[s.choices.len - 1 - index];
            try s.ctrl.clearCurrentLine();
            if (index == s.selection) {
                try writer.writeAll(" > ");
            } else {
                try writer.writeAll("   ");
            }
            try writer.writeAll(choice);

            if (s.choices.len - 1 != index) {
                try writer.writeAll("\n");
            }
        }

        try s.ctrl.flush();
    }

    fn incrementSelection(s: *Selector) void {
        if (s.selection + 1 < s.choices.len) {
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
                else => {},
            },
            .Down => s.incrementSelection(),
            .Up => s.decrementSelection(),
            else => {},
        }
        return true;
    }
};
