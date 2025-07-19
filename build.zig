const std = @import("std");

pub fn build(b: *std.Build) void {
    const build_debug = b.option(
        bool,
        "debug",
        "Compile a debug executable.",
    ) orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // install a module for use in downstream libraries
    const termui_module = b.addModule(
        "termui",
        .{
            .root_source_file = b.path("src/components.zig"),
            .target = target,
            .optimize = optimize,
        },
    );

    if (build_debug) {
        const debug_exe = b.addExecutable(.{
            .name = "debug-termui",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/debug-exe.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "termui", .module = termui_module },
                },
            }),
        });
        b.installArtifact(debug_exe);
    }

    const main_tests = b.addTest(.{
        .root_module = termui_module,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
