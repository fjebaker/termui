const std = @import("std");
const TermUI = @import("TermUI.zig");

pub const Selector = struct {
    pub const Options = struct {
        /// Clear after drawing
        clear: bool = true,
    };

    tui: *TermUI,
    choices: []const []const u8,
    selection: usize = 0,
    opts: Options,

    pub fn init(
        tui: *TermUI,
        choices: []const []const u8,
        opts: Options,
    ) Selector {
        return .{ .tui = tui, .choices = choices, .opts = opts };
    }

    pub fn interact(s: *Selector) !usize {
        try s.tui.setCursorVisible(false);

        var writer = s.tui.writer();

        // setup the screen
        try writer.writeAll("\n");
        try s.redraw();

        // interaction loop
        while (try s.update()) {
            try s.tui.cursorUp(s.choices.len);
            try s.redraw();
        }

        if (s.opts.clear) {
            try s.tui.cursorUp(s.choices.len + 2);
        }

        try writer.writeAll("\n");
        try s.tui.setCursorVisible(true);

        return s.choices.len - 1 - s.selection;
    }

    fn redraw(s: *Selector) !void {
        var writer = s.tui.writer();

        for (0..s.choices.len) |index| {
            const choice = s.choices[s.choices.len - 1 - index];
            try s.tui.clearCurrentLine();
            if (index == s.selection) {
                try writer.writeAll(" > ");
            } else {
                try writer.writeAll("   ");
            }
            try writer.writeAll(choice);
            try writer.writeAll("\n");
        }
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
        switch (try s.tui.nextInput()) {
            .char => |c| switch (c) {
                'q' => return false,
                else => {},
            },
            .Down => s.incrementSelection(),
            .Up => s.decrementSelection(),
            else => {},
        }
        return true;
    }
};
