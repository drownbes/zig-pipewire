const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    // b.setPreferredReleaseMode(.Debug);
    //const mode = b.standardReleaseOptions();

    //const optimize = b.standardOptimizeOption(.{});

    // const exe = b.addExecutable("zig-pw", "examples/roundtrip.zig");
    // exe.setTarget(target);
    // exe.setBuildMode(mode);
    // exe.linkLibC();
    // exe.linkSystemLibrary("libpipewire-0.3");
    // exe.addPackage(pipewire);

    // exe.install();
    const pretty = b.dependency("pretty", .{ .target = target });

    inline for ([_][]const u8{ "roundtrip", "volume" }) |example| {
        const exe = b.addExecutable(.{
            .name = example,
            .root_source_file = b.path("examples/" ++ example ++ ".zig"),
            .target = target,
        });
        // const exe = b.addExecutable("zig-pw", "examples/roundtrip.zig");
        exe.addIncludePath(std.Build.LazyPath{ .src_path = .{ .owner = b, .sub_path = "/nix/store/cw78ndjp827zan6hpdk41c45ynfwqrvk-pipewire-1.2.1-dev/include/pipewire-0.3/" } });
        exe.addIncludePath(std.Build.LazyPath{ .src_path = .{ .owner = b, .sub_path = "/nix/store/cw78ndjp827zan6hpdk41c45ynfwqrvk-pipewire-1.2.1-dev/include/spa-0.2/" } });
        exe.linkLibC();
        exe.linkSystemLibrary("libpipewire-0.3");
        const pipewire = b.addModule("pipewire", .{
            .root_source_file = b.path("src/pipewire.zig"),
        });

        pipewire.addIncludePath(std.Build.LazyPath{ .src_path = .{ .owner = b, .sub_path = "/nix/store/cw78ndjp827zan6hpdk41c45ynfwqrvk-pipewire-1.2.1-dev/include/pipewire-0.3/" } });
        pipewire.addIncludePath(std.Build.LazyPath{ .src_path = .{ .owner = b, .sub_path = "/nix/store/cw78ndjp827zan6hpdk41c45ynfwqrvk-pipewire-1.2.1-dev/include/spa-0.2/" } });

        exe.root_module.addImport("pipewire", pipewire);
        exe.root_module.addImport("pretty", pretty.module("pretty"));

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run-" ++ example, "Run " ++ example);
        run_step.dependOn(&run_cmd.step);
    }

    //const exe_tests = b.addTest("src/pipewire.zig");
    //exe_tests.setTarget(target);
    //exe_tests.addCSourceFile("src/spa/test_pod.c", &[_][]const u8{});
    //exe_tests.linkLibC();
    //exe_tests.linkSystemLibrary("libpipewire-0.3");

    //const test_step = b.step("test", "Run unit tests");
    //test_step.dependOn(&exe_tests.step);
}
