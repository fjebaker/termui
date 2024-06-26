const std = @import("std");

pub fn build(b: *std.Build) void {
    const build_debug = b.option(
        bool,
        "debug",
        "Compile a debug executable.",
    ) orelse false;

    const build_shared = b.option(
        bool,
        "shared",
        "Compile a shared library.",
    ) orelse false;

    const build_static = b.option(
        bool,
        "static",
        "Compile a static library.",
    ) orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // install a module for use in downstream libraries
    const termui_module = b.addModule(
        "termui",
        .{ .root_source_file = b.path("src/main.zig") },
    );

    if (build_debug) {
        const debug_exe = b.addExecutable(.{
            .name = "debug-termui",
            .root_source_file = b.path("src/debug-exe.zig"),
            .target = target,
            .optimize = optimize,
        });
        debug_exe.root_module.addImport("termui", termui_module);
        // debug_exe.linkLibC();
        b.installArtifact(debug_exe);
    }

    if (build_shared) {
        const lib = b.addSharedLibrary(.{
            .name = "termui",
            .root_source_file = b.path("src/debug-exe.zig"),
            .target = target,
            .optimize = optimize,
        });
        b.installArtifact(lib);
    }

    if (build_static) {
        const lib = b.addStaticLibrary(.{
            .name = "termui",
            .root_source_file = b.path("src/debug-exe.zig"),
            .target = target,
            .optimize = optimize,
        });
        b.installArtifact(lib);
    }

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
