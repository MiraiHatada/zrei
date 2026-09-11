const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const main = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const main_compile = b.addExecutable(.{
        .name = "zrei",
        .root_module = main,
    });
    b.installArtifact(main_compile);
    const main_run = b.addRunArtifact(main_compile);
    main_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| main_run.addArgs(args);

    const test_main = b.addTest(.{
        .name = "zrei_test_main",
        .root_module = main,
    });
    const test_main_run = b.addRunArtifact(test_main);

    const run_cmd = b.step("run", "run application");
    run_cmd.dependOn(&main_run.step);

    const test_cmd = b.step("test", "run all specs");
    test_cmd.dependOn(&test_main_run.step);

    const check_cmd = b.step("check", "check if it compiles (zls)");
    check_cmd.dependOn(&main_compile.step);
    check_cmd.dependOn(&test_main.step);
}
